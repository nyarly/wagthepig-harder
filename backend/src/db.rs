use core::fmt;
use axum::response::{ErrorResponse, IntoResponse};
use chrono::NaiveDateTime;
use futures::{TryFuture, TryFutureExt as _};
use sqlx::{Executor, Postgres};

use zeroize::{Zeroize, ZeroizeOnDrop};

pub enum Error {
    Sqlx(sqlx::Error)
}

impl From<sqlx::Error> for Error {
    fn from(value: sqlx::Error) -> Self {
        Self::Sqlx(value)
    }
}

impl IntoResponse for Error {
    fn into_response(self) -> axum::response::Response {
        use axum::http::StatusCode;

        (match self {
            Error::Sqlx(err) => match err {
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
        }).into_response()
    }
}

fn into_error_response<E>(e: E) -> ErrorResponse
where Error: From<E> {
    Error::from(e).into()
}

#[derive(Zeroize, ZeroizeOnDrop, Default)]
pub(crate) struct Password(String);

impl From<String> for Password {
    fn from(value: String) -> Self {
        Self(value)
    }
}

impl AsRef<String> for Password {
    fn as_ref(&self) -> &String {
        &self.0
    }
}

impl fmt::Debug for Password {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_tuple("Password")
            .field(&"[redacted]")
            .finish()
    }
}

#[derive(sqlx::FromRow, Default, Debug)]
#[allow(dead_code)] // Have to match DB
pub(crate) struct User {
    pub id: i64,
    pub name: Option<String>,
    pub bgg_username: Option<String>,
    pub email: String,
    pub encrypted_password: Password,
    pub updated_at: NaiveDateTime,
    pub created_at: NaiveDateTime,
    pub remember_created_at: Option<NaiveDateTime>,
    pub reset_password_sent_at: Option<NaiveDateTime>,
    pub reset_password_token: Option<String>
}

impl User {
    pub fn by_email<'a>(db: impl Executor<'a, Database = Postgres> + 'a, email: String)
    -> impl TryFuture<Ok = Self, Error = ErrorResponse> + 'a {
        sqlx::query_as!(
            Self,
            "select * from users where email = $1",
            email)
            .fetch_one(db)
            .map_err(into_error_response)
    }
}

#[derive(sqlx::FromRow, Default, Debug)]
#[allow(dead_code)] // Have to match DB
pub(crate) struct Event {
    pub id: i64,
    pub name: Option<String>,
    pub date: Option<NaiveDateTime>,
    pub r#where: Option<String>,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
    pub description: Option<String>,
}

impl Event {
    pub fn with_id(&mut self, id: i64) -> &Self {
        self.id = id; self
    }

    pub fn get_all<'a>(db: impl Executor<'a, Database = Postgres> + 'a)
    -> impl TryFuture<Ok = Vec<Self>, Error = ErrorResponse> + 'a {
        sqlx::query_as!(
            Self,
            "select * from events")
            .fetch_all(db)
            .map_err(into_error_response)
    }

    pub fn get_by_id<'a>(db: impl Executor<'a, Database = Postgres> + 'a, id: i64)
    -> impl TryFuture<Ok = Option<Self>, Error = ErrorResponse> + 'a {
        sqlx::query_as!(
            Self,
            "select * from events where id = $1",
            id)
            .fetch_optional(db)
            .map_err(into_error_response)
    }

    pub fn add_new<'a>(&self, db: impl Executor<'a, Database = Postgres> + 'a)
    -> impl TryFuture<Ok = i64, Error = ErrorResponse> + 'a {
        sqlx::query_scalar!(
            r#"insert into events ("name", "date", "where", "description") values ($1, $2, $3, $4) returning id"#,
            self.name, self.date, self.r#where, self.description)
            .fetch_one(db)
            .map_err(into_error_response)
    }

    pub fn update<'a>(&self, db: impl Executor<'a, Database = Postgres> + 'a)
    -> impl TryFuture<Ok = Self, Error = ErrorResponse> + 'a {
        sqlx::query_as!(
            Self,
            r#"update events set ("name", "date", "where", "description") = ($1, $2, $3, $4) where id = $5 returning *"#,
            self.name, self.date, self.r#where, self.description, self.id)
            .fetch_one(db)
            .map_err(into_error_response)
    }

}

#[derive(sqlx::FromRow, Default, Debug)]
#[allow(dead_code)] // Have to match DB
pub(crate) struct Game {
    id: i64,
    name: Option<String>,
    min_players: Option<i32>,
    max_players: Option<i32>,
    bgg_link: Option<String>,
    duration_secs: Option<i32>,
    created_at: NaiveDateTime,
    updated_at: NaiveDateTime,
    event_id: i64,
    suggestor_id: i64,
    bgg_id: Option<String>,
    pitch: Option<String>
}

impl Game {
    pub fn get_all_for_event<'a>(db: impl Executor<'a, Database = Postgres> + 'a, event_id: i64)
    -> impl TryFuture<Ok = Vec<Self>, Error = ErrorResponse> + 'a {
        sqlx::query_as!(
            Self,
            "select * from games where event_id = $1",
            event_id)
            .fetch_all(db)
            .map_err(into_error_response)
    }
}
