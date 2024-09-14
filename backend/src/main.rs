use std::{net::SocketAddr, time::Duration};

use axum::{
  http::StatusCode,
  debug_handler,
  Router,
  routing::{get, post},
  extract::{self, ConnectInfo, FromRef, Json, Path, State},
  response::{ErrorResponse, IntoResponse, Result},
};

use axum_extra::{headers::IfMatch, TypedHeader};
use biscuit_auth::macros::authorizer;
use hyper::header;
use sqlx::{postgres::{PgConnectOptions, PgPoolOptions}, Pool, Postgres};
use tower_http::trace::TraceLayer;

use tracing::{debug, Level};
use futures::future::TryFutureExt;

use httpapi::{RouteMap, EtaggedJson};

use crate::httpapi::etag_for;
use semweb_api::{biscuits, routing::{route_config, VarsList}, spa};
use semweb_api::biscuits::Authentication;


// app modules
mod db;
mod httpapi;

#[derive(FromRef, Clone)]
struct AppState {
    pool: Pool<Postgres>,
    auth: Authentication,
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
  tracing_subscriber::fmt()
    .with_max_level(Level::TRACE)
    .init();

  let db_connection_str = std::env::var("DATABASE_URL").expect("DATABASE_URL must be provided");
  let frontend_path = std::env::var("FRONTEND_PATH").expect("FRONTEND_PATH must be provided");
  let authentication_path = std::env::var("AUTH_KEYPAIR").expect("AUTH_KEYPAIR must be provided");

  debug!("{:?}", db_connection_str);
  let dbopts: PgConnectOptions = db_connection_str.parse().expect("couldn't parse DATABASE_URL");

  debug!("{:?}", dbopts);
  let pool = PgPoolOptions::new()
    .max_connections(5)
    .acquire_timeout(Duration::from_secs(3))
    .connect_with(dbopts)
    .await
    .expect("can't connect to database");

  let auth = biscuits::Authentication::new(authentication_path)?;
  let state = AppState{pool, auth: auth.clone()};

  let app = Router::new()
    .nest("/api",
      open_api_router()
      .merge(secured_api_router(auth))
    );

  // XXX conditionally, include assets directly
  let (app, _watcher) = spa::livereload(app, frontend_path)?;

  let app = app
    .layer(TraceLayer::new_for_http())
    .with_state(state);

  let listener = tokio::net::TcpListener::bind("0.0.0.0:3000").await.expect("couldn't bind on port 3000");
  tracing::debug!("listening on {}", listener.local_addr().unwrap());

  axum::serve(listener, app.into_make_service_with_connect_info::<SocketAddr>()).await?; Ok(())
}

fn open_api_router() -> Router<AppState> {
  let path = |rm| route_config(rm).axum_route();

  use RouteMap::*;
  Router::new()
    .route(&path(Root), get(sitemap))

    .route(&path(Authenticate), post(authenticate))
}

fn secured_api_router(auth: biscuits::Authentication) -> Router<AppState> {
  let path = |rm| route_config(rm).axum_route();

  use RouteMap::*;
  let profile_path = path(Profile);
    Router::new()
        .route(&profile_path,
            get(get_profile))

        .route(&path(Events),
            get(get_event_list)
                .post(create_new_event)
        )

        .route(&path(Event),
            get(get_event)
                .put(update_event)
        )

        .route(&path(EventGames),
            get(get_event_games)
        )

        .layer(tower::ServiceBuilder::new()
            .layer(biscuits::AuthenticationSetup::new(auth, "Authorization"))
            .layer(biscuits::AuthenticationCheck::new(authorizer!(r#"
            allow if route({profile_path}), path_param("useri_id", $user), user($user);
            deny if route({profile_path});
            allow if user($user);
            "#, profile_path = profile_path))
            ))
}

#[debug_handler(state = AppState)]
async fn sitemap(nested_at: extract::NestedPath) -> impl IntoResponse {
  httpapi::api_doc(nested_at.as_str())
}

#[debug_handler(state = AppState)]
async fn get_profile(
  State(db): State<Pool<Postgres>>,
  nested_at: extract::NestedPath,
  Path(user_id): Path<String>
) -> impl IntoResponse {
  db::User::by_email(&db, user_id)
        .and_then(|profile| async {
            Ok(EtaggedJson(httpapi::UserResponse::from_query(nested_at.as_str(), profile)?))
        }).await
}

#[debug_handler(state = AppState)]
async fn get_event_list(
  State(db): State<Pool<Postgres>>,
  nested_at: extract::NestedPath
) -> impl IntoResponse {
  db::Event::get_all(&db)
    .and_then(|events| async {
      Ok(Json(httpapi::EventListResponse::from_query(nested_at.as_str(), events)?))
    })
    .await
}

#[debug_handler(state = AppState)]
async fn get_event(
  State(db): State<Pool<Postgres>>,
  nested_at: extract::NestedPath,
  Path(event_id): extract::Path<i64>,
) -> impl IntoResponse {
    retrieve_event(&db, nested_at, event_id)
        .and_then(|event_response| async {
          Ok(EtaggedJson(event_response))
        })
    .await
}

#[debug_handler(state = AppState)]
async fn update_event(
  State(db): State<Pool<Postgres>>,
  TypedHeader(if_match): TypedHeader<IfMatch>,
  nested_at: extract::NestedPath,
  Path(event_id): extract::Path<i64>,
  Json(body): extract::Json<httpapi::EventUpdateRequest>
) -> impl IntoResponse {
    retrieve_event(&db, nested_at.clone(), event_id)
        .and_then(|event| async {
            if if_match.precondition_passes( &etag_for(event)?) {
                Ok(())
            } else {
                Err(ErrorResponse::from(StatusCode::PRECONDITION_FAILED))
            }
        }).await?;

    body.db_param()
        .with_id(event_id)
        .update(&db)
        .and_then(|event| async move {
            let event_tmpl = route_config(RouteMap::Event).prefixed(nested_at.as_str());
            Ok(Json(httpapi::EventResponse::from_query(&event_tmpl, event)?))
        }).await
}

async fn retrieve_event(
    db: &Pool<Postgres>,
    nested_at: extract::NestedPath,
    event_id: i64
) -> Result<httpapi::EventResponse, ErrorResponse> {
  db::Event::get_by_id(db, event_id)
    .and_then(|maybe_event| async {
      match maybe_event {
        Some(event) => {
          let event_tmpl = route_config(RouteMap::Event).prefixed(nested_at.as_str());
          httpapi::EventResponse::from_query(&event_tmpl, event)
                    .map_err(|e| e.into())
        }
        None => Err(ErrorResponse::from(StatusCode::NOT_FOUND))
      }
    })
    .await
}

#[debug_handler(state = AppState)]
async fn get_event_games(
  State(db): State<Pool<Postgres>>,
  nested_at: extract::NestedPath,
  Path((event_id, user_id)): extract::Path<(i64, String)>,
) -> impl IntoResponse {
  db::Game::get_all_for_event_and_user(&db, event_id, user_id.clone())
    .and_then(|games| async {
      Ok(Json(httpapi::EventGameListResponse::from_query(nested_at.as_str(), event_id, user_id, games)?))
    })
    .await
}


#[debug_handler(state = AppState)]
async fn create_new_event(
  State(db): State<Pool<Postgres>>,
  nested_at: extract::NestedPath,
  Json(body): extract::Json<httpapi::EventUpdateRequest>
) -> impl IntoResponse {
    body.db_param()
        .add_new(&db)
        .and_then(|new_id| async move {
            route_config(RouteMap::Event)
                .prefixed(nested_at.as_str())
                .fill(VarsList(vec![("event_id".to_string(), new_id.to_string())]))
                .map(|location_uri| {
                    (StatusCode::CREATED, [(header::LOCATION, location_uri.to_string())])
                })
                .map_err(|e| e.into())
        }).await
}

const ONE_WEEK: u64 = 60 * 60 * 24 * 7; // A week


#[debug_handler(state = AppState)]
async fn authenticate(
  State(db): State<Pool<Postgres>>,
  State(auth): State<Authentication>,
  ConnectInfo(addr): ConnectInfo<SocketAddr>,
  nested_at: extract::NestedPath,
  Json(authreq): Json<httpapi::AuthnRequest>
) -> impl IntoResponse {
  db::User::by_email(&db, authreq.email.clone())
    .and_then(|user| async move {
      if bcrypt::verify(authreq.password.clone(), user.encrypted_password.as_ref()).map_err(internal_error)? {
        let token = biscuits::authority(&auth, user.email.clone(), ONE_WEEK, Some(addr))?;
        Ok(([("set-authorization", token)], Json(httpapi::UserResponse::from_query(nested_at.as_str(), user)?)))
      } else {
        Err((StatusCode::FORBIDDEN, "Authorization rejected".to_string()).into())
      }
    })
  .await
}

fn internal_error<E: std::error::Error>(err: E) -> ErrorResponse {
    debug!("internal error: {:?}", err);
  (StatusCode::INTERNAL_SERVER_ERROR, err.to_string()).into()
}
