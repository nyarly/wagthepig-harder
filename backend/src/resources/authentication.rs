use std::{
     net::SocketAddr, time::{Duration, SystemTime}
};

use axum::{
    Extension, Json,
    debug_handler,
    extract::{self, ConnectInfo, Request, State},
    middleware::Next,
    response::IntoResponse,
};
use biscuit_auth::macros::authorizer;
use chrono::Utc;
use hyper::StatusCode;
use mattak::biscuits::{AuthContext, Authentication};
use serde::Deserialize;
use sqlx::{Pool, Postgres};
use tracing::debug;
use zeroize::{Zeroize, ZeroizeOnDrop};

use crate::{db::{Revocation, User}, mailing, AppState, Error};

const ONE_WEEK: u64 = 60 * 60 * 24 * 7; // A week
const PASSWORD_COST: u32 = bcrypt::DEFAULT_COST;

// #[debug_middleware(state = AppState)]
pub(crate) async fn add_rejections(
    State(db): State<Pool<Postgres>>,
    Extension(authctx): Extension<AuthContext>,
    mut request: Request,
    next: Next
) -> Result<impl IntoResponse, Error> {
    let revocations = Revocation::get_revoked(&db, Utc::now().naive_utc()).await?;
    let rids = revocations.into_iter().map(|rev| rev.data).collect();
    let authctx = authctx.with_revoked_ids(rids);
    request.extensions_mut().insert(authctx);
    Ok(next.run(request).await)
}

#[derive(Deserialize, Zeroize, ZeroizeOnDrop)]
pub(crate) struct AuthnRequest {
    pub password: String
}

#[derive(Deserialize, Zeroize, ZeroizeOnDrop)]
pub(crate) struct AuthnUpdateRequest {
    pub old_password: Option<String>,
    pub new_password: String
}
impl AuthnUpdateRequest {
    pub(crate) fn valid(&self) -> Result<(), mattak::Error> {
        debug!("Checking length of password");
        if self.new_password.len() < 12 {
            return Err(mattak::Error::InvalidInput("password less than 12 characters".to_string()))
        }
        Ok(())
    }
}

#[derive(Deserialize)]
#[serde(rename_all="camelCase")]
pub(crate) struct RegisterRequest {
    pub name: String,
    pub bgg_username: String,
}


// has to fetch a user
// has to fetch revocations
#[debug_handler(state = AppState)]
pub(crate) async fn authenticate(
    State(db): State<Pool<Postgres>>,
    State(auth): State<Authentication>,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    extract::Path(email): extract::Path<String>,
    Json(authreq): Json<AuthnRequest>
) -> Result<impl IntoResponse, Error> {
    mailing::cleanup_revocations.builder()
        .spawn(&db).await
        .map_err(crate::db::Error::from)?;
    debug!("Attempting to verify user password");

    let cant_match = bcrypt::hash(format!("busy {} work", authreq.password), PASSWORD_COST)?.into();

    // Always proceed, to reduce the ability of an attacker to use this as an email oracle
    let (email, encrypted_password) = match User::by_email(&db, email.clone()).await {
        Ok(u) => (u.email, u.encrypted_password),
        Err(_) => ("nobody@nowhere.com".to_string(), cant_match)
    };

    // XXX bcrypt ONLY for back-compatibility with Rails
    // change to a real KDF in future
    if bcrypt::verify(authreq.password.clone(), encrypted_password.as_ref())? {
        debug!("Successfully verified password");
        let expires = SystemTime::now() + Duration::from_secs(ONE_WEEK);
        let bundle = auth.authority(&email, expires, Some(addr)).map_err(mattak::Error::from)?;

        let _ = Revocation::add_batch(&db, bundle.revocation_ids, email.clone(), expires).await?;
        Ok(([("set-authorization", bundle.token)], StatusCode::NO_CONTENT))
    } else {
        Err((StatusCode::FORBIDDEN, "Authorization rejected").into())
    }
}

#[debug_handler(state = AppState)]
pub(crate) async fn reset_password(
    State(db): State<Pool<Postgres>>,
    extract::Path(email): extract::Path<String>,
) -> Result<impl IntoResponse, Error> {
    mailing::request_reset.builder()
      .set_json(&mailing::ResetDetails{
            email: email.clone(),
        })?
        .spawn(&db).await
        .map_err(crate::db::Error::from)?;

    Ok(StatusCode::NO_CONTENT)
}

// XXX Need to limit regs/IP
#[debug_handler(state = AppState)]
pub(crate) async fn register(
    State(db): State<Pool<Postgres>>,
    extract::Path(email): extract::Path<String>,
    Json(regreq): Json<RegisterRequest>
) -> Result<impl IntoResponse, Error> {
    User::create(&db, &email, &regreq.name, &regreq.bgg_username).await?;
    mailing::request_registration.builder()
      .set_json(&mailing::RegistrationDetails{
            email: email.clone(),
        })?
        .spawn(&db).await
        .map_err(crate::db::Error::from)?;

    Ok(StatusCode::NO_CONTENT)
}

#[debug_handler(state = AppState)]
pub(crate) async fn update_credentials(
    State(db): State<Pool<Postgres>>,
    extract::Path(email): extract::Path<String>,
    Extension(auth): Extension<AuthContext>,
    Json(authreq): Json<AuthnUpdateRequest>
) -> Result<impl IntoResponse, Error> {
    authreq.valid()?;
    let user = User::by_email(&db, email.clone()).await?;

    let rejected = || -> Error {(StatusCode::FORBIDDEN, "Authorization rejected").into()};
    if !(auth.check(authorizer!(r#"allow if reset_password({user_id});"#, user_id = email.clone())).is_ok() ||
        bcrypt::verify(authreq.old_password.clone().ok_or_else(rejected)?, user.encrypted_password.as_ref())?) {
        return Err(rejected())
    }

    let hashed = bcrypt::hash(authreq.new_password.clone(), PASSWORD_COST)?;
    Revocation::revoke_for_username(&db, email.clone(), Utc::now().naive_utc()).await?;
    user.update_password(&db, hashed).await?;
    Ok(StatusCode::NO_CONTENT)
}

#[debug_handler(state = AppState)]
pub(crate) async fn revoke(
    State(db): State<Pool<Postgres>>,
    Extension(authctx): Extension<AuthContext>,
) -> Result<impl IntoResponse, Error> {
    match authctx.revocation_ids() {
        None => Err((StatusCode::NOT_FOUND, "No authorization to revoke").into()),
        Some(revocation_ids) => {
            Revocation::revoke(&db, revocation_ids, Utc::now().naive_utc()).await?;
            Ok(StatusCode::NO_CONTENT)
        }
    }
}
