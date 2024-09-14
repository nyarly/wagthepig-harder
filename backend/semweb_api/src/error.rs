use axum::{http, response::IntoResponse};

use crate::routing;


#[derive(thiserror::Error, Debug)]
pub enum Error {
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
}


impl IntoResponse for Error {
    fn into_response(self) -> axum::response::Response {
        use http::status::StatusCode;
        match self {
            // might specialize these errors more going forward
            // need to consider server vs client
            Error::BadETagFormat(_) |
            Error::CreateString(_) |
            Error::Deserialization(_) |
            Error::ExtraCaptures(_) |
            Error::InvalidHeaderValue(_) |
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
