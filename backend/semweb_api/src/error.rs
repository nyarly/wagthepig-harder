use axum::{http, response::IntoResponse};
use axum_extra::extract as extra_extract;
use axum::extract;
use tracing::debug;

use crate::routing;

#[derive(thiserror::Error, Debug)]
pub enum Error {
    #[error("unknown error: {0}")]
    Unknown(String),
    #[error("trouble parsing: {0:?}")]
    Parsing(String),
    #[error("couldn't validate IRI: {0:?}")]
    IriValidate(#[from] iri_string::validate::Error),
    #[error("error processing IRI template: {0:?}")]
    IriTempate(#[from] iri_string::template::Error),
    #[error("creating a string for an IRI: {0:?}")]
    CreateString(#[from] iri_string::types::CreationError<std::string::String>),
    #[error("missing captures: {0:?}")]
    MissingCaptures(Vec<String>),
    #[error("extra captures: {0:?}")]
    ExtraCaptures(Vec<String>),
    #[error("cannot parse string as a header value: {0:?}")]
    InvalidHeaderValue(#[from] http::header::InvalidHeaderValue),
    #[error("regex parse: {0:?}")]
    RegexParse(#[from] regex::Error),
    #[error("no match: {0:?} vs {1:?}")]
    NoMatch(String, String),
    #[error("capture deserialization: {0:?}")]
    Deserialization(#[from] routing::CaptureDeserializationError),
    #[error("couldn't serialize JSON: {0:?}")]
    JSONSerialization(#[from] serde_json::Error),
    #[error("badly formatted ETag: {0:?}")]
    BadETagFormat(String),
    #[error("couldn't convert value to IRI: {0:?}")]
    IriConversion(String),
    #[error("issue building token: {0:?}")]
    Token(#[from] biscuit_auth::error::Token),
    #[error("routing match error")]
    MatchedPath(#[from] extract::rejection::MatchedPathRejection),
    #[error("nested path error")]
    NestedPath(#[from] extract::rejection::NestedPathRejection),
    #[error("extension error")]
    Extension(#[from] extract::rejection::ExtensionRejection),
    #[error("extracting path params")]
    PathParams(#[from] extract::rejection::RawPathParamsRejection),
    #[error("extracting host")]
    Host(#[from] extract::rejection::HostRejection),
    #[error("extracting query params")]
    Query(#[from] extra_extract::QueryRejection),
    #[error("no authentication context found")]
    MissingContext,
    #[error("no authentication credential token found")]
    NoToken,
    #[error("provided token has been revoked")]
    RevokedToken,
    #[error("authorization failed")]
    AuthorizationFailed,
    #[error("precondition failed: {0}")]
    PreconditionFailed(String),
    #[error("malformed header: {0}")]
    Header(#[from] axum_extra::typed_header::TypedHeaderRejection),
    #[error("input invalid: {0}")]
    InvalidInput(String),
}

impl IntoResponse for Error {
    fn into_response(self) -> axum::response::Response {
        use http::status::StatusCode;
        debug!("Returning error: {:?}", &self);
        match self {
            // best errors: we know how they match up to status codes
            Error::NoToken => (StatusCode::UNAUTHORIZED, "/api/authentication").into_response(),
            Error::RevokedToken => (StatusCode::UNAUTHORIZED, "/api/authentication").into_response(),
            Error::AuthorizationFailed => (StatusCode::FORBIDDEN, "insufficient access").into_response(),
            Error::PreconditionFailed(s) => (StatusCode::PRECONDITION_FAILED, s).into_response(),

            // upstream knows better
            Error::Token(err) => {
                match err {
                    biscuit_auth::error::Token::ConversionError(_) => (StatusCode::BAD_REQUEST, "couldn't convert token").into_response(),
                    biscuit_auth::error::Token::Base64(_) => (StatusCode::BAD_REQUEST, "invalid token encoding").into_response(),
                    biscuit_auth::error::Token::Format(_) => (StatusCode::BAD_REQUEST, "invalid token format").into_response(),
                    _ => (StatusCode::INTERNAL_SERVER_ERROR, "internal authentication error").into_response()
                }
            }
            Error::MatchedPath(mpe) => mpe.into_response(),
            Error::NestedPath(e) => e.into_response(),
            Error::Extension(ee) => ee.into_response(),
            Error::PathParams(e) => e.into_response(),
            Error::Host(e) => e.into_response(),
            Error::Query(e) => e.into_response(),

            // presumed client errors
            Error::InvalidInput(_) |
            Error::BadETagFormat(_) |
            Error::InvalidHeaderValue(_) |
            Error::Header(_) => (StatusCode::BAD_REQUEST, self.to_string()).into_response(),

            // presumed server errors
            Error::MissingContext |
            Error::Unknown(_) |
            Error::CreateString(_) |
            Error::Deserialization(_) |
            Error::ExtraCaptures(_) |
            Error::IriConversion(_) |
            Error::IriTempate(_) |
            Error::IriValidate(_) |
            Error::JSONSerialization(_) |
            Error::MissingCaptures(_) |
            Error::NoMatch(_,_) |
            Error::Parsing(_) |
            Error::RegexParse(_) => (StatusCode::INTERNAL_SERVER_ERROR, self.to_string()).into_response(),
        }
    }
}
