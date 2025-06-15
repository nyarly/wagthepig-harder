use std::{net::{IpAddr, SocketAddr}, sync::Arc, time::Duration};

use axum::{
    extract::{self}, http::StatusCode, middleware, response::{IntoResponse, Result}, routing::{get, post, put}, Router
};

use bcrypt::BcryptError;
use biscuit_auth::macros::authorizer;
use semweb_api::cachecontrol::CacheControlLayer;
use clap::Parser;
use governor::{clock::QuantaInstant, middleware::RateLimitingMiddleware};
use lettre::{AsyncSmtpTransport, Tokio1Executor};
use resources::authentication;
use sqlx::{postgres::{PgConnectOptions, PgPoolOptions}, Pool, Postgres};
use tower_governor::{governor::GovernorConfigBuilder, key_extractor::{KeyExtractor, PeerIpKeyExtractor, SmartIpKeyExtractor}, GovernorLayer};
use tower_http::trace::TraceLayer;

use tracing::{debug, info, warn};
use tracing_subscriber::{EnvFilter, prelude::*};

use crate::routing::RouteMap;

use semweb_api::{biscuits::{self, Authentication}, routing::route_config, spa};


// app modules
mod routing;
mod resources;
mod db;
mod mailing;

#[derive(extract::FromRef, Clone)]
struct AppState {
    pool: Pool<Postgres>,
    auth: Authentication,
}


#[derive(Parser)]
struct Config {
    /// The local address
    #[arg(long, env = "LOCAL_ADDR", default_value = "127.0.0.1:3000")]
    local_addr: String,

    /// Canonical domain the site is served from. Will be used in messages sent via email
    #[arg(long, env = "CANON_DOMAIN")]
    canon_domain: String,

    /// Site administrator's email address - used when sending e.g. password reset messages
    #[arg(long, env = "ADMIN_EMAIL")]
    admin_address: String,

    /// The SMTP MTA address
    #[arg(long, env = "SMTP_HOST")]
    smtp_address: String,

    /// The SMTP MTA port
    #[arg(long, env = "SMTP_PORT")]
    smtp_port: String,

    /// The SMTP MTA username for authenticated mailing
    #[arg(long, env = "SMTP_USERNAME")]
    smtp_user_name: String,

    /// The SMTP MTA password
    #[arg(long, env = "SMTP_PASSWORD")]
    smtp_password: String,

    /// TLS cert for communicating with the SMTP MTA
    #[arg(long, env = "SMTP_CERT")]
    smtp_cert: Option<String>,

    /// A DB connection URL c.f. https://www.postgresql.org/docs/16/libpq-connect.html#LIBPQ-CONNSTRING-URIS
    #[arg(long, env = "DATABASE_URL")]
    db_connection_str: String,

    // XXX this doesn't make sense in Prod...
    // unless it would override compiled in files
    /// The path to serve front-end files from
    #[arg(long, env = "FRONTEND_PATH")]
    frontend_path: String,

    /// Path to store token authenication secrets
    #[arg(long, env = "AUTH_KEYPAIR")]
    authentication_path: String,

    /// Can we trust the X-Forwarded-For header?
    /// Otherwise we have to use the peer IP for rate limiting.
    /// In other words, if hosting behind e.g. nginx,
    /// ensure that X-Forwarded-For is set and set this true.
    #[arg(long, env = "TRUST_FORWARDED_HEADER", default_value = "false")]
    trust_forwarded_header: bool,
}

impl Config {
    fn build_mailing_transport(&self) -> Result<AsyncSmtpTransport<Tokio1Executor>, mailing::Error> {
        mailing::build_transport(&self.smtp_address, &self.smtp_port, &self.smtp_user_name, &self.smtp_password, self.smtp_cert.clone())
    }
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    tracing_subscriber::registry()
        .with(tracing_subscriber::fmt::layer())
        .with(EnvFilter::from_default_env())
        .init();

    let config = Config::parse();

    let transport = config.build_mailing_transport()?;
    match transport.test_connection().await {
        Ok(connected) => info!("SMTP transport to {smtp_address} connected? {connected}", smtp_address = config.smtp_address),
        Err(e) => warn!("Error attempting connection on SMTP transport {smtp_address}: {e:?}", smtp_address = config.smtp_address),
    }

    debug!("{:?}", config.db_connection_str);
    let dbopts: PgConnectOptions = config.db_connection_str.parse().expect("couldn't parse DATABASE_URL");

    debug!("{:?}", dbopts);
    let pool = PgPoolOptions::new()
        .max_connections(5)
        .acquire_timeout(Duration::from_secs(3))
        .connect_with(dbopts)
        .await
        .expect("can't connect to database");

    let auth = biscuits::Authentication::new(config.authentication_path)?;

    let _runner = mailing::queue_listener(
        pool.clone(),
        config.admin_address.to_string(),
        config.canon_domain.to_string(),
        transport,
        auth.clone(),
    ).await?;

    let state = AppState{pool, auth: auth.clone()};

    let rate_key = ConfigurableKeyExtractor::trust(config.trust_forwarded_header);

    let app = Router::new()
        .nest("/api",
            root_api_router(rate_key)
                .merge(open_api_router(rate_key))
                .merge(secured_api_router(state.clone(), auth, rate_key))
        );

    // XXX conditionally, include assets directly
    let (app, _watcher) = spa::livereload(app, config.frontend_path)?;

    let app = app
        .layer(TraceLayer::new_for_http())
        .with_state(state);

    let listener = tokio::net::TcpListener::bind(config.local_addr.to_string()).await.expect("couldn't bind on local addr");
    tracing::debug!("listening on {}", listener.local_addr().unwrap());

    axum::serve(listener, app.into_make_service_with_connect_info::<SocketAddr>()).await?; Ok(())
}

async fn sitemap(nested_at: extract::NestedPath) -> impl IntoResponse {
    routing::api_doc(nested_at.as_str())
}

#[derive(Clone,Copy,Debug)]
pub enum ConfigurableKeyExtractor {
    PeerIp(PeerIpKeyExtractor),
    RevProxy(SmartIpKeyExtractor),
}

impl ConfigurableKeyExtractor {
    fn trust(yes: bool) -> Self {
        if yes {
            ConfigurableKeyExtractor::RevProxy(SmartIpKeyExtractor{})
        } else {
            ConfigurableKeyExtractor::PeerIp(PeerIpKeyExtractor{})
        }
    }
}

impl KeyExtractor for ConfigurableKeyExtractor {
    type Key = IpAddr;

    fn name(&self) -> &'static str {
        match self {
            ConfigurableKeyExtractor::PeerIp(ex) => ex.name(),
            ConfigurableKeyExtractor::RevProxy(ex) => ex.name(),
        }
    }

    fn extract<T>(
        &self,
        req: &axum::http::Request<T>,
    ) -> Result<Self::Key, tower_governor::GovernorError> {
        match self {
            ConfigurableKeyExtractor::PeerIp(ex) => ex.extract(req),
            ConfigurableKeyExtractor::RevProxy(ex) => ex.extract(req),
        }
    }
}
fn governor_setup<K,M>(name: &str, extractor: ConfigurableKeyExtractor, cfg_builder: &mut GovernorConfigBuilder<K,M>) -> GovernorLayer<ConfigurableKeyExtractor,M>
where K: KeyExtractor + Sync + std::fmt::Debug,
    M: RateLimitingMiddleware<QuantaInstant> + Send + Sync + 'static,
    <K as KeyExtractor>::Key: Send + Sync + 'static
{
    let governor_conf = Arc::new(
            cfg_builder
            .key_extractor(extractor)
            .finish()
            .unwrap(),
    );

    tracing::debug!("{name} governor created: {governor_conf:?}");

    let governor_limiter = governor_conf.limiter().clone();
    let interval = Duration::from_secs(60);
    // a separate background task to clean up
    std::thread::spawn(move || {
        loop {
            std::thread::sleep(interval);
            tracing::debug!("rate limiting storage size: {}", governor_limiter.len());
            governor_limiter.retain_recent();
        }
    });

    GovernorLayer { config: governor_conf }
}


fn root_api_router(extractor: ConfigurableKeyExtractor) -> Router<AppState> {
    let path = |rm| route_config(rm).axum_route();
    Router::new()
        .route(&path(RouteMap::Root), get(sitemap))
        .layer(governor_setup("api-root", extractor, GovernorConfigBuilder::default()
            .per_millisecond(20)
            .burst_size(60)
        ))
        .layer(CacheControlLayer::new(30))
        // XXX key extractor that is either Authentication or SmartIp
}

fn open_api_router(extractor: ConfigurableKeyExtractor) -> Router<AppState> {
    let path = |rm| route_config(rm).axum_route();

    use resources::authentication;

    use RouteMap::*;
    Router::new()

        .route(&path(Authenticate), post(authentication::authenticate))

        .route(&path(Profile), put(authentication::register))

        .route(&path(PasswordReset), post(authentication::reset_password))
        .layer(governor_setup("anonymous", extractor, GovernorConfigBuilder::default()
            .per_second(1)
            .burst_size(10)
        ))
}

fn secured_api_router(state: AppState, auth: biscuits::Authentication, extractor: ConfigurableKeyExtractor) -> Router<AppState> {
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

        .route(&path(Game), get(game::get).put(game::update))

        .route(&path(GameUsers), get(profile::get_game_list))

        .route(&path(Recommend), post(recommendation::make))

        .layer(tower::ServiceBuilder::new()
            .layer(governor_setup("authenticated", extractor, GovernorConfigBuilder::default()
                .per_millisecond(20)
                .burst_size(60)
            ))
            .layer(CacheControlLayer::new(1))
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
