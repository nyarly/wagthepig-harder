use std::{net::SocketAddr, time::Duration};

use axum::{
    extract::{self, FromRef}, http::StatusCode, middleware, response::{IntoResponse, Result}, routing::{get, post, put}, Router
};

use bcrypt::BcryptError;
use biscuit_auth::macros::authorizer;
use resources::authentication;
use sqlx::{postgres::{PgConnectOptions, PgPoolOptions}, Pool, Postgres};
use sqlxmq::{JobRegistry, JobRunnerHandle};
use tower_http::trace::TraceLayer;

use tracing::{debug, info, warn, Level};

use crate::routing::RouteMap;

use semweb_api::{biscuits::{self, Authentication}, routing::route_config, spa};


// app modules
mod routing;
mod resources;
mod db;
mod httpapi;
mod mailing;

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

    let admin_address = std::env::var("ADMIN_EMAIL").expect("ADMIN_EMAIL must be provided");
    let smtp_address = std::env::var("SMTP_HOST").expect("SMTP_HOST must be provided");
    let smtp_port = std::env::var("SMTP_PORT").expect("SMTP_PORT must be provided");
    let smtp_user_name = std::env::var("SMTP_USERNAME").expect("SMTP_USERNAME must be provided");
    let smtp_password = std::env::var("SMTP_PASSWORD").expect("SMTP_PASSWORD must be provided");
    let smtp_cert = std::env::var("SMTP_CERT").ok();

    let transport = mailing::build_transport(&smtp_address, &smtp_port, &smtp_user_name, &smtp_password, smtp_cert)?;
    match transport.test_connection().await {
        Ok(connected) => info!("SMTP transport to {smtp_address} connected? {connected}"),
        Err(e) => warn!("Error attempting connection on SMTP transport {smtp_address}: {e:?}"),
    }

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
    let _runner = queue_listener(pool.clone(), mailing::AdminEmail(admin_address.to_string()), transport, auth.clone()).await?;
    let state = AppState{pool, auth: auth.clone()};

    let app = Router::new()
        .nest("/api",
            open_api_router()
                .merge(secured_api_router(state.clone(), auth))
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

async fn queue_listener(
    pool: Pool<Postgres>,
    admin: mailing::AdminEmail,
    transport: mailing::Transport,
    auth: biscuits::Authentication
) -> Result<JobRunnerHandle, sqlx::Error> {
    use mailing::{request_reset, request_registration};
    let mut registry = JobRegistry::new(&[request_reset, request_registration]);
    // Here is where you can configure the registry
    // registry.set_error_handler(...)

    registry.set_context(admin);
    registry.set_context(transport);
    registry.set_context(auth);

    let runner = registry
        .runner(&pool)
        .set_concurrency(1, 20)
        .run()
        .await?;

    // The job runner will continue listening and running
    // jobs until `runner` is dropped.
    Ok(runner)
}


async fn sitemap(nested_at: extract::NestedPath) -> impl IntoResponse {
    routing::api_doc(nested_at.as_str())
}

fn open_api_router() -> Router<AppState> {
    let path = |rm| route_config(rm).axum_route();

    use resources::authentication;

    use RouteMap::*;
    Router::new()
        .route(&path(Root), get(sitemap))

        .route(&path(Authenticate), post(authentication::authenticate))

        .route(&path(Profile), post(authentication::register))

        .route(&path(PasswordReset), post(authentication::reset_password))
}

fn secured_api_router(state: AppState, auth: biscuits::Authentication) -> Router<AppState> {
    use resources::{event, game, profile, recommendation};
    use RouteMap::*;

    let path = |rm| route_config(rm).axum_route();

    let profile_path = path(Profile);

    Router::new()
        .route(&profile_path, get(profile::get))

        .route(&path(Authenticate),
            put(authentication::update_credentials)
                .delete(authentication::revoke)

        )

        .route(&path(Events),
            get(event::get_list)
                .post(event::create_new)
        )

        .route(&path(Event),
            get(event::get)
                .put(event::update)
        )

        .route(&path(EventUsers), get(profile::get_event_list))

        .route(&path(EventGames),
            get(game::get_scoped_list)
                .post(game::create_new)
        )

        .route(&path(Game), put(game::update))

        .route(&path(GameUsers), get(profile::get_game_list))

        .route(&path(Recommend), post(recommendation::make))

        .layer(tower::ServiceBuilder::new()
            .layer(biscuits::AuthenticationSetup::new(auth, "Authorization"))
            .layer(middleware::from_fn_with_state(state, authentication::add_rejections))
            .layer(biscuits::AuthenticationCheck::new(authorizer!(r#"
            allow if route({profile_path}), path_param("user_id", $user), user($user);
            deny if route({profile_path});

            allow if route({auth_path}), path_param("user_id", $user), user($user);
            allow if route({auth_path}), path_param("user_id", $user), method("PUT"), reset_password($user);
            deny if route({auth_path});

            allow if user($user);
            "#,
                auth_path = path(Authenticate)
            )))
        )
}

#[derive(thiserror::Error, Debug)]
pub enum Error {
    #[error("database error: ${0:?}")]
    DB(#[from] db::Error),
    #[error("http error: ${0:?}")]
    HTTP(#[from] semweb_api::Error),
    #[error("status code: ${0:?} - ${1}")]
    StatusCode(StatusCode, String),
    #[error("cryptographic issue: ${0:?}")]
    Crypto(#[from] bcrypt::BcryptError),
    #[error("Problem with job queue: ${0:?}")]
    Job(String),
    #[error("Problem setting up email: ${0:?}")]
    Email(#[from] mailing::Error),
    #[error("Couldn't serialize data: ${0:?}")]
    Serialization(#[from] serde_json::Error),
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
            Error::Job(m) => (StatusCode::INTERNAL_SERVER_ERROR, m).into_response(),
            Error::Email(e) => (StatusCode::INTERNAL_SERVER_ERROR, format!("{:?}", e)).into_response(),
            Error::Crypto(e) => match e {
                BcryptError::Rand(_) |
                BcryptError::InvalidSaltLen(_) |
                BcryptError::InvalidPrefix(_) |
                BcryptError::InvalidCost(_) |
                BcryptError::CostNotAllowed(_) |
                BcryptError::Io(_) => (StatusCode::INTERNAL_SERVER_ERROR).into_response(),
                BcryptError::InvalidHash(_) |
                BcryptError::InvalidBase64(_) => (StatusCode::BAD_REQUEST).into_response(),
            },
            Error::Serialization(e) => (StatusCode::INTERNAL_SERVER_ERROR, format!("{:?}", e)).into_response()
        }
    }
}
