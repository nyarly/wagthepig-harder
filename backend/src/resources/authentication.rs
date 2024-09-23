use std::net::SocketAddr;

use axum::{debug_handler, extract::{self, ConnectInfo, State}, response::IntoResponse, Json};
use hyper::StatusCode;
use semweb_api::biscuits::{self, Authentication};
use sqlx::{Pool, Postgres};
use tracing::debug;

use crate::{db::User, httpapi::{AuthnRequest, UserResponse}, AppState, Error};

const ONE_WEEK: u64 = 60 * 60 * 24 * 7; // A week

#[debug_handler(state = AppState)]
pub(crate) async fn authenticate(
    State(db): State<Pool<Postgres>>,
    State(auth): State<Authentication>,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    nested_at: extract::NestedPath,
    Json(authreq): Json<AuthnRequest>
) -> Result<impl IntoResponse, Error> {
    let user = User::by_email(&db, authreq.email.clone()).await?;

    if bcrypt::verify(authreq.password.clone(), user.encrypted_password.as_ref()).map_err(internal_error)? {
        let token = biscuits::authority(&auth, user.email.clone(), ONE_WEEK, Some(addr))?;
        Ok(([("set-authorization", token)], Json(UserResponse::from_query(nested_at.as_str(), user)?)))
    } else {
        Err((StatusCode::FORBIDDEN, "Authorization rejected").into())
    }
}

fn internal_error<E: std::error::Error>(err: E) -> Error {
    debug!("internal error: {:?}", err);
    (StatusCode::INTERNAL_SERVER_ERROR, err.to_string()).into()
}
