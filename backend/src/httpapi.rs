use axum::response::ErrorResponse;
use hyper::StatusCode;
use serde::{Deserialize, Serialize};
use zeroize::{Zeroize, ZeroizeOnDrop};

use crate::db;

pub(crate) fn db_error_response(err: sqlx::Error) -> ErrorResponse {
    (db_error_code(&err), err.to_string()).into()
}

fn db_error_code(err: &sqlx::Error) -> StatusCode {
    match err {
        sqlx::Error::TypeNotFound { .. } |
        sqlx::Error::ColumnNotFound(_) => StatusCode::INTERNAL_SERVER_ERROR,

        sqlx::Error::Configuration(_) |
        sqlx::Error::Migrate(_) |
        sqlx::Error::Database(_) |
        sqlx::Error::Tls(_) |
        sqlx::Error::AnyDriverError(_) => StatusCode::BAD_GATEWAY,

        sqlx::Error::Io(_) |
        sqlx::Error::Protocol(_) |
        sqlx::Error::PoolTimedOut |
        sqlx::Error::PoolClosed |
        sqlx::Error::WorkerCrashed => StatusCode::GATEWAY_TIMEOUT,

        sqlx::Error::RowNotFound => StatusCode::NOT_FOUND,

        sqlx::Error::ColumnIndexOutOfBounds { .. } |
        sqlx::Error::ColumnDecode { .. } |
        sqlx::Error::Encode(_) |
        sqlx::Error::Decode(_) => StatusCode::BAD_REQUEST,

        _ => StatusCode::INTERNAL_SERVER_ERROR,
    }
}

#[derive(Deserialize, Zeroize, ZeroizeOnDrop)]
pub(crate) struct AuthnRequest {
    pub email: String,
    pub password: String
}

#[derive(Default, Serialize)]
pub(crate) struct UserResponse {
    pub name: Option<String>,
    pub bgg_username: Option<String>,
    pub email: String,
}

impl From<db::User> for UserResponse {
    fn from(value: db::User) -> Self {
        Self{
            name: value.name,
            bgg_username: value.bgg_username,
            email: value.email
        }
    }
}
