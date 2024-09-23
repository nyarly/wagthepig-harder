use std::{net::SocketAddr, time::Duration};

use axum::{
    extract::{self, FromRef},
    http::StatusCode,
    response::{IntoResponse, Result},
    routing::{get, post, put},
    Router
};

use biscuit_auth::macros::authorizer;
use sqlx::{postgres::{PgConnectOptions, PgPoolOptions}, Pool, Postgres};
use tower_http::trace::TraceLayer;

use tracing::{debug, Level};

use httpapi::RouteMap;

use semweb_api::{biscuits::{self, Authentication}, routing::route_config, spa};


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

    /*
    address:               ENV['SMTP_HOST'],
    port:                  ENV['SMTP_PORT'],
    user_name:             ENV['SMTP_USERNAME'],
    password:              ENV['SMTP_PASSWORD'],
    * */
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


#[derive(thiserror::Error, Debug)]
pub enum Error {
    #[error("database error: ${0:?}")]
    DB(#[from] db::Error),
    #[error("http error: ${0:?}")]
    HTTP(#[from] semweb_api::Error),
    #[error("status code: ${0:?} - ${1}")]
    StatusCode(StatusCode, String),
}


impl From<(StatusCode, &'static str)> for Error {
    fn from((code, text): (StatusCode, &'static str)) -> Self {
        Self::StatusCode(code, text.to_string())

    }
}

impl From<(StatusCode, String)> for Error {
    fn from((code, text): (StatusCode, String)) -> Self {
        Self::StatusCode(code, text)

    }
}

impl IntoResponse for Error {
    fn into_response(self) -> axum::response::Response {
        match self {
            Error::DB(e) => e.into_response(),
            Error::HTTP(e) => e.into_response(),
            Error::StatusCode(c, t) => (c,t).into_response(),
        }
    }
}

async fn sitemap(nested_at: extract::NestedPath) -> impl IntoResponse {
    httpapi::api_doc(nested_at.as_str())
}

fn open_api_router() -> Router<AppState> {
    let path = |rm| route_config(rm).axum_route();

    use resources::authentication;

    use RouteMap::*;
    Router::new()
        .route(&path(Root), get(sitemap))

        .route(&path(Authenticate), post(authentication::authenticate))
}

fn secured_api_router(auth: biscuits::Authentication) -> Router<AppState> {
    let path = |rm| route_config(rm).axum_route();

    use resources::{event, game, profile, recommendation};

    use RouteMap::*;
    let profile_path = path(Profile);
    Router::new()
        .route(&profile_path,
            get(profile::get_profile))

        .route(&path(Events),
            get(event::get_event_list)
                .post(event::create_new_event)
        )

        .route(&path(Event),
            get(event::get_event)
                .put(event::update_event)
        )

        .route(&path(EventGames),
            get(resources::game::get_event_games)
                .post(game::create_new_game)
        )

        .route(&path(Game), put(game::update_game))

        .route(&path(Recommend), post(recommendation::make_recommendation))

        .layer(tower::ServiceBuilder::new()
            .layer(biscuits::AuthenticationSetup::new(auth, "Authorization"))
            .layer(biscuits::AuthenticationCheck::new(authorizer!(r#"
            allow if route({profile_path}), path_param("useri_id", $user), user($user);
            deny if route({profile_path});
            allow if user($user);
            "#, profile_path = profile_path))
            ))
}

mod resources {
    pub(crate) mod profile {
        use axum::{debug_handler, extract::{self, Path, State}, response::IntoResponse};
        use semweb_api::condreq;
        use sqlx::{Pool, Postgres};

        use crate::{db, httpapi, AppState, Error};

        #[debug_handler(state = AppState)]
        pub(crate) async fn get_profile(
            State(db): State<Pool<Postgres>>,
            if_none_match: condreq::CondRetreiveHeader,
            nested_at: extract::NestedPath,
            Path(user_id): Path<String>
        ) -> Result<impl IntoResponse, Error> {
            let profile = db::User::by_email(&db, user_id).await?;
            if_none_match.respond(httpapi::UserResponse::from_query(nested_at.as_str(), profile)?).map_err(Error::from)
        }

    }

    pub(crate) mod event {
        use axum::{debug_handler, extract::{self, Path, State}, response::IntoResponse, Json};
        use hyper::{header, StatusCode};
        use semweb_api::{condreq, routing::route_config};
        use sqlx::{Pool, Postgres};

        use crate::{db::{self, EventId}, httpapi::{self, EventLocate, RouteMap}, AppState, Error};


        #[debug_handler(state = AppState)]
        pub(crate) async fn get_event_list(
            State(db): State<Pool<Postgres>>,
            if_none_match: condreq::CondRetreiveHeader,
            nested_at: extract::NestedPath
        ) -> Result<impl IntoResponse, Error> {
            let events = db::Event::get_all(&db).await?;
            let resp = httpapi::EventListResponse::from_query(nested_at.as_str(), events)?;
            if_none_match.respond(resp).map_err(Error::from)
        }

        #[debug_handler(state = AppState)]
        pub(crate) async fn get_event(
            State(db): State<Pool<Postgres>>,
            if_none_match: condreq::CondRetreiveHeader,
            nested_at: extract::NestedPath,
            Path(event_id): extract::Path<EventId>,
        ) -> Result<impl IntoResponse, Error> {
            let event_response = retrieve_event(&db, nested_at, event_id).await?;
            if_none_match.respond(event_response).map_err(Error::from)
        }

        #[debug_handler(state = AppState)]
        pub(crate) async fn update_event(
            State(db): State<Pool<Postgres>>,
            if_match: condreq::CondUpdateHeader,
            nested_at: extract::NestedPath,
            Path(event_id): extract::Path<EventId>,
            Json(body): extract::Json<httpapi::EventUpdateRequest>
        ) -> Result<impl IntoResponse, Error> {
            let event = retrieve_event(&db, nested_at.clone(), event_id).await?;

            if_match.guard_update(event)?;

            let event_route = route_config(RouteMap::Event).prefixed(nested_at.as_str());
            let event = body.db_param()
                .with_id(event_id)
                .update(&db).await?;

            Ok(Json(httpapi::EventResponse::from_query(&event_route, event)?))
        }

        async fn retrieve_event(
            db: &Pool<Postgres>,
            nested_at: extract::NestedPath,
            event_id: EventId
        ) -> Result<httpapi::EventResponse, Error> {
            let maybe_event = db::Event::get_by_id(db, event_id).await?;

            match maybe_event {
                Some(event) => {
                    let event_tmpl = route_config(RouteMap::Event).prefixed(nested_at.as_str());
                    httpapi::EventResponse::from_query(&event_tmpl, event)
                        .map_err(|e| e.into())
                }
                None => Err((StatusCode::NOT_FOUND, "not found").into())
            }
        }

        #[debug_handler(state = AppState)]
        pub(crate) async fn create_new_event(
            State(db): State<Pool<Postgres>>,
            nested_at: extract::NestedPath,
            Json(body): extract::Json<httpapi::EventUpdateRequest>
        ) -> Result<impl IntoResponse, Error> {
            let new_id = body.db_param()
                .add_new(&db).await?;

            let location_uri = route_config(RouteMap::Event)
                .prefixed(nested_at.as_str())
                .fill( EventLocate{ event_id: new_id })?;

            Ok((StatusCode::CREATED, [(header::LOCATION, location_uri.to_string())]))
        }
    }

    pub(crate) mod recommendation {
        use axum::{debug_handler, extract::{self, Path, State}, response::IntoResponse, Json};
        use semweb_api::condreq;
        use sqlx::{Pool, Postgres};

        use crate::{db::{self, EventId}, httpapi::{self}, AppState, Error};

        #[debug_handler(state = AppState)]
        pub(crate) async fn make_recommendation(
            State(db): State<Pool<Postgres>>,
            if_none_match: condreq::CondRetreiveHeader,
            nested_at: extract::NestedPath,
            Path(event_id): extract::Path<EventId>,
            Json(body): extract::Json<httpapi::RecommendRequest>
        ) -> Result<impl IntoResponse, Error> {
            let recommend = db::Game::get_recommendation(&db, event_id, body.player_ids(nested_at.as_str())?, body.extra_players).await?;

            let resp = httpapi::RecommendListResponse::from_query(nested_at.as_str(), event_id, recommend)?;
            if_none_match.respond(resp).map_err(Error::from)
        }
    }

    pub(crate) mod authentication {
        use std::net::SocketAddr;

        use axum::{debug_handler, extract::{self, ConnectInfo, State}, response::IntoResponse, Json};
        use hyper::StatusCode;
        use semweb_api::biscuits::{self, Authentication};
        use sqlx::{Pool, Postgres};
        use tracing::debug;

        use crate::{db::{self}, httpapi::{self}, AppState, Error};

        const ONE_WEEK: u64 = 60 * 60 * 24 * 7; // A week

        #[debug_handler(state = AppState)]
        pub(crate) async fn authenticate(
            State(db): State<Pool<Postgres>>,
            State(auth): State<Authentication>,
            ConnectInfo(addr): ConnectInfo<SocketAddr>,
            nested_at: extract::NestedPath,
            Json(authreq): Json<httpapi::AuthnRequest>
        ) -> Result<impl IntoResponse, Error> {
            let user = db::User::by_email(&db, authreq.email.clone()).await?;

            if bcrypt::verify(authreq.password.clone(), user.encrypted_password.as_ref()).map_err(internal_error)? {
                let token = biscuits::authority(&auth, user.email.clone(), ONE_WEEK, Some(addr))?;
                Ok(([("set-authorization", token)], Json(httpapi::UserResponse::from_query(nested_at.as_str(), user)?)))
            } else {
                Err((StatusCode::FORBIDDEN, "Authorization rejected").into())
            }
        }

        fn internal_error<E: std::error::Error>(err: E) -> Error {
            debug!("internal error: {:?}", err);
            (StatusCode::INTERNAL_SERVER_ERROR, err.to_string()).into()
        }
    }

    pub(crate) mod game {
        use axum::{debug_handler, extract::{self, Path, State}, response::IntoResponse, Json};
        use hyper::{header, StatusCode};
        use semweb_api::{condreq, routing::{self, route_config}};
        use sqlx::{Pool, Postgres};

        use crate::{db::{self, EventId, GameId}, httpapi::{self, GameLocate, RouteMap}, AppState, Error};

        #[debug_handler(state = AppState)]
        pub(crate) async fn get_event_games(
            State(db): State<Pool<Postgres>>,
            if_none_match: condreq::CondRetreiveHeader,
            nested_at: extract::NestedPath,
            Path((event_id, user_id)): extract::Path<(EventId, String)>,
        ) -> Result<impl IntoResponse, Error> {
            let games = db::Game::get_all_for_event_and_user(&db, event_id, user_id.clone()).await?;
            let resp = httpapi::EventGameListResponse::from_query(nested_at.as_str(), event_id, user_id, games)?;
            if_none_match.respond(resp).map_err(Error::from)
        }

        #[debug_handler(state = AppState)]
        pub(crate) async fn create_new_game(
            State(db): State<Pool<Postgres>>,
            nested_at: extract::NestedPath,
            Path((event_id, user_id)): extract::Path<(EventId, String)>,
            Json(body): extract::Json<httpapi::GameUpdateRequest>
        ) -> Result<impl IntoResponse, Error> {
            let mut tx = db.begin().await.map_err(db::Error::from)?;

            let game = body.db_param().with_event_id(event_id);
            let new_id = game.add_new(&mut *tx, user_id.clone()).await?;
            let game = game.with_id(new_id).with_interest_data(body.interest_part());
            game.update_interests(&mut *tx, user_id).await?;

            tx.commit().await.map_err(db::Error::from)?;

            let location_uri = route_config(RouteMap::Game)
                .prefixed(nested_at.as_str())
                .fill(GameLocate{ game_id: new_id })
                .map_err(Error::from)?;

            Ok((StatusCode::CREATED, [(header::LOCATION, location_uri.to_string())]))
        }

        #[debug_handler(state = AppState)]
        pub(crate) async fn update_game(
            State(db): State<Pool<Postgres>>,
            if_match: condreq::CondUpdateHeader,
            nested_at: extract::NestedPath,
            Path((game_id, user_id)): extract::Path<(GameId, String)>,
            Json(body): extract::Json<httpapi::GameUpdateRequest>
        ) -> Result<impl IntoResponse, Error> {
            let game_route = route_config(RouteMap::Game).prefixed(nested_at.as_str());
            let game = retrieve_game(&db, &game_route, game_id, user_id.clone()).await?;

            if_match.guard_update(game)?;

            let mut tx = db.begin().await.map_err(db::Error::from)?;
            let game = body.db_param()
                .with_id(game_id)
                .update(&mut *tx).await
                .map_err(Error::from)?;

            let game = game.with_interest_data(body.interest_part());

            game.update_interests(&mut *tx, user_id).await
                .map_err(Error::from)?;

            tx.commit().await.map_err(db::Error::from)?;

            Ok(Json(httpapi::GameResponse::from_query(&game_route, game)?))
        }

        async fn retrieve_game(
            db: &Pool<Postgres>,
            game_route: &routing::Entry,
            game_id: GameId,
            user_id: String,
        ) -> Result<httpapi::GameResponse, Error> {
            let maybe_game = db::Game::get_by_id_and_user(db, game_id, user_id).await?;

            match maybe_game {
                Some(game) => {
                    httpapi::GameResponse::from_query(game_route, game)
                        .map_err(Error::from)
                }
                None => Err((StatusCode::NOT_FOUND, "not found").into())
            }
        }
    }
}
