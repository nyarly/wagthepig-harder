use axum::{http, response::IntoResponse};
use serde::{Deserialize, Serialize};
pub use iri_string::types::IriReferenceString;

use crate::routing;

#[derive(Serialize, Clone)]
#[serde(tag="type")]
pub(crate) struct IriTemplate {
    pub id: IriReferenceString,
    // pub r#type: String,
    pub template: String,
    pub operation: Vec<Operation>
}


#[derive(Default, Serialize, Clone)]
pub(crate) struct Operation {
    pub method: Method,
    pub r#type: ActionType,
}

#[derive(Default, Clone)]
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


#[derive(Default, Serialize, Deserialize, Clone)]
pub(crate) enum ActionType {
    #[default]
    #[serde(rename = "ViewAction")]
    View,
    #[serde(rename = "CreateAction")]
    Create,
    #[serde(rename = "UpdateAction")]
    Update,
    #[serde(rename = "FindAction")]
    Find,
    #[serde(rename = "AddAction")]
    Add,
    #[serde(rename = "LoginAction")]
    // this is not a schema.org Action type
    Login
}

/// op is used to create a most-common operation for each action type
pub(super) fn op(action: ActionType) -> Operation {
    use ActionType::*;
    use axum::http::Method;
    match action {
        View => Operation {
            method: Method::GET.into(),
            r#type: action
        },
        Create => Operation{
            method: Method::PUT.into(),
            r#type: action
        },
        Update => Operation{
            method: Method::PUT.into(),
            r#type: action
        },
        Find => Operation{
            method: Method::GET.into(),
            r#type: action
        },
        Add => Operation{
            method: Method::POST.into(),
            r#type: action
        },
        Login => Operation{
            method: Method::POST.into(),
            r#type: action
        }
    }
}

#[derive(thiserror::Error, Debug)]
pub enum Error {
    #[error("couldn't serialize JSON: {0:?}")]
    JSONSerialization(#[from] serde_json::Error),
    #[error("badly formatted ETag: {0:?}")]
    BadETagFormat(String),
    #[error("route config: {0:?}")]
    Routing(#[from] routing::Error),
    #[error("couldn't validate IRI: {0:?}")]
    IriValidate(#[from] iri_string::validate::Error),
    #[error("error processing IRI template: {0:?}")]
    IriTempate(#[from] iri_string::template::Error),
    #[error("creating a string for an IRI: {0:?}")]
    CreateString(#[from] iri_string::types::CreationError<std::string::String>),
    #[error("cannot parse string as a header value: {0:?}")]
    InvalidHeaderValue(#[from] http::header::InvalidHeaderValue),
}

impl IntoResponse for Error {
    fn into_response(self) -> axum::response::Response {
        use http::status::StatusCode;
        match self {
            // might specialize these errors more going forward
            // need to consider server vs client
            Error::IriValidate(_) |
            Error::IriTempate(_) |
            Error::CreateString(_) |
            Error::InvalidHeaderValue(_) |
            Error::Routing(_) |
            Error::BadETagFormat(_) |
            Error::JSONSerialization(_) => (StatusCode::INTERNAL_SERVER_ERROR, format!("{:?}", self)).into_response(),
        }
    }
}
