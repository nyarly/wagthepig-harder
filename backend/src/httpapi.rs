use axum::{http, response::ErrorResponse};
use chrono::NaiveDateTime;
use hyper::StatusCode;
use serde::{Deserialize, Serialize};
use uritemplate::UriTemplate;
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

/*
type alias Model =
  { id: Maybe IRI
  , events: List(Event)
  , operation: List(Operation)
  }

type alias Operation =
  { method: String
  }

type alias Event =
  { id: IRI
  , name: String
  , time: Time.Posix
  , location: String
  }
*/


// this starts to feel a little gross
// using Elm millis-since-epoch Posix time
// (and probably days since year 0 for dates)
#[derive(Default, Serialize)]
pub(crate) struct Posix(i64);

impl From<NaiveDateTime> for Posix {
    fn from(value: NaiveDateTime) -> Self {
        Self(value.signed_duration_since(NaiveDateTime::UNIX_EPOCH).num_milliseconds())
    }
}

#[derive(Default, Serialize)]
pub(crate) struct IRI(String);

impl From<String> for IRI {
    fn from(value: String) -> Self {
        Self(value)
    }
}

#[derive(Default, Serialize)]
pub(crate) struct Operation {
    pub method: Method,
    // type: ActionType e.g. CreateAction
}

#[derive(Default)]
pub(crate) struct Method(http::Method);

impl From<http::Method> for Method {
    fn from(value: http::Method) -> Self {
        Self(value)
    }
}

impl Serialize for Method {
    fn serialize<S: serde::Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error>
    {
        serializer.serialize_str(self.0.as_str())
    }
}

#[derive(Default, Serialize)]
pub(crate) struct Event {
    pub id: IRI,
    pub name: Option<String>,
    pub time: Option<Posix>,
    pub location: Option<String>
}

impl Event {
    fn build(uritmpl: &str, value: db::Event) -> Self {
        let mut idtmpl = UriTemplate::new(uritmpl);
        Self{
            name: value.name,
            location: value.r#where,
            id: idtmpl.set("id", value.id.to_string()).build().into(),
            time: value.date.map(|t| t.into())
        }
    }
}


#[derive(Default, Serialize)]
pub(crate) struct EventListResponse {
    pub id: IRI,
    pub events: Vec<Event>,
    pub operation: Vec<Operation>
}

impl EventListResponse {
    pub fn from_query(id: &str, list: Vec<db::Event>) -> Self {
        Self{
            id: id.to_string().into(),
            operation: vec![Operation{method: axum::http::Method::POST.into()}],
            events: list.into_iter().map(|ev| Event::build("/api/event/{id}",ev)).collect()
        }
    }
}
