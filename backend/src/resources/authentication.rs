use std::{
    net::SocketAddr,
    time::{Duration, SystemTime}
};

use axum::{
    Extension, Json,
    debug_handler,
    extract::{self, ConnectInfo, Request, State},
    middleware::Next,
    response::IntoResponse,
};
use chrono::Utc;
use hyper::StatusCode;
use semweb_api::biscuits::{AuthContext, Authentication};
use sqlx::{Pool, Postgres};

use crate::{db::{Revocation, User}, httpapi::{AuthnRequest, UserResponse}, mailing, AppState, Error};

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

#[debug_handler(state = AppState)]
pub(crate) async fn reset_password(
    State(db): State<Pool<Postgres>>,
    extract::Host(host): extract::Host,
    Json(authreq): Json<AuthnRequest>
) -> Result<impl IntoResponse, Error> {
    mailing::request_reset.builder()
      .set_json(&mailing::ResetDetails{
            domain: host,
            email: authreq.email.clone(),
        })?
        .spawn(&db).await
        .map_err(crate::db::Error::from)?;

    Ok(StatusCode::NO_CONTENT)
}

#[debug_handler(state = AppState)]
pub(crate) async fn register(
    State(db): State<Pool<Postgres>>,
    extract::Host(host): extract::Host,
    Json(authreq): Json<AuthnRequest>
) -> Result<impl IntoResponse, Error> {
    mailing::request_registration.builder()
      .set_json(&mailing::RegistrationDetails{
            domain: host,
            email: authreq.email.clone(),
        })?
        .spawn(&db).await
        .map_err(crate::db::Error::from)?;

    Ok(StatusCode::NO_CONTENT)
}

#[debug_handler(state = AppState)]
pub(crate) async fn authenticate(
    State(db): State<Pool<Postgres>>,
    State(auth): State<Authentication>,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    nested_at: extract::NestedPath,
    Json(authreq): Json<AuthnRequest>
) -> Result<impl IntoResponse, Error> {
    let user = User::by_email(&db, authreq.email.clone()).await?;

    if bcrypt::verify(authreq.password.clone(), user.encrypted_password.as_ref())? {
        let expires = SystemTime::now() + Duration::from_secs(ONE_WEEK);
        let bundle = auth.authority(&user.email, expires, Some(addr))?;

        let _ = Revocation::add_batch(&db, bundle.revocation_ids, authreq.email.clone(), expires).await?;
        Ok(([("set-authorization", bundle.token)], Json(UserResponse::from_query(nested_at.as_str(), user)?)))
    } else {
        Err((StatusCode::FORBIDDEN, "Authorization rejected").into())
    }
}

#[debug_handler(state = AppState)]
pub(crate) async fn update_credentials(
    State(db): State<Pool<Postgres>>,
    Json(authreq): Json<AuthnRequest>
) -> Result<impl IntoResponse, Error> {
    let user = User::by_email(&db, authreq.email.clone()).await?;
    let hashed = bcrypt::hash(authreq.password.clone(), PASSWORD_COST)?;
    Revocation::revoke_for_username(&db, authreq.email.clone(), Utc::now().naive_utc()).await?;
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
