use std::{net::SocketAddr, time::Duration};

use axum::{
    debug_handler,
    extract::{Path, ConnectInfo, FromRef, Json, State},
    http::StatusCode,
    response::{ErrorResponse, IntoResponse, Result},
    routing::{get, post},
    Router
};
use biscuit_auth::macros::authorizer;
use biscuits::Authentication;
use sqlx::{postgres::{PgConnectOptions, PgPoolOptions}, Pool, Postgres};
use tower_http::trace::TraceLayer;

use tracing::{debug, Level};
use futures::future::TryFutureExt;


use serde_json::json;

// crate candidates
mod biscuits;
mod spa;

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



  let app = Router::new().route("/api", get(sitemap))
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
  Router::new()
    .route("/authenticate", post(authenticate))
}

fn secured_api_router(auth: biscuits::Authentication) -> Router<AppState> {
  Router::new()
    .route("/profile/:userid", get(get_profile))
    .route("/events", get(get_event_list))
    .layer(tower::ServiceBuilder::new()
      .layer(biscuits::AuthenticationSetup::new(auth, "Authorization"))
      .layer(biscuits::AuthenticationCheck::new(authorizer!(r#"
            allow if route("/profile/:userid"), path_param("userid", $user), user($user);
            deny if route("/profile/:userid");
            allow if user($user);
            "#))
      )
    )
}

async fn sitemap() -> String {
  json!({
    "root": "/api",
    "authenticate": "/api/authenticate",
    "profile": "/api/profile/{userid}",
    "events": "/api/events"
  }).to_string()
}

#[debug_handler(state = AppState)]
async fn get_profile(State(db): State<Pool<Postgres>>, Path(userid): Path<String>) -> impl IntoResponse {
  db::User::by_email(&db, userid)
    .map_err(httpapi::db_error_response)
    .and_then(|profile| async { Ok(Json(httpapi::UserResponse::from(profile))) }).await
}

#[debug_handler(state = AppState)]
async fn get_event_list(State(db): State<Pool<Postgres>> ) -> impl IntoResponse {
  db::Event::get_all(&db)
    .map_err(httpapi::db_error_response)
    // XXX Fix h/c URI
    .and_then(|events| async { Ok(Json(httpapi::EventListResponse::from_query("/api/events", events)))})
    .await
}

const ONE_WEEK: u64 = 60 * 60 * 24 * 7; // A week


#[debug_handler(state = AppState)]
async fn authenticate(
  State(db): State<Pool<Postgres>>,
  State(auth): State<Authentication>,
  ConnectInfo(addr): ConnectInfo<SocketAddr>,
  Json(authreq): Json<httpapi::AuthnRequest>
) -> impl IntoResponse {
  db::User::by_email(&db, authreq.email.clone())
    .map_err(httpapi::db_error_response)
    .and_then(|user| async move {
      if bcrypt::verify(authreq.password.clone(), user.encrypted_password.as_ref()).map_err(internal_error)? {
        let token = biscuits::authority(&auth, user.email.clone(), ONE_WEEK, Some(addr))?;
        Ok(([("set-authorization", token)], Json(httpapi::UserResponse::from(user))))
      } else {
        Err((StatusCode::FORBIDDEN, "Authorization rejected".to_string()).into())
      }
    })
  .await
}

fn internal_error<E>(err: E) -> ErrorResponse
where
  E: std::error::Error,
{
  (StatusCode::INTERNAL_SERVER_ERROR, err.to_string()).into()
}
