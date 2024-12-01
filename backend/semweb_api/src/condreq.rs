use axum::{async_trait, extract::FromRequestParts, http::request, response::{IntoResponse, Response}, Json};
use axum_extra::{headers::{self, ETag, Header as _, IfMatch, IfNoneMatch}, typed_header::TypedHeaderRejection, TypedHeader};
use hyper::StatusCode;
use serde::Serialize;
use base64ct::{Base64, Encoding};
use sha2::{Digest, Sha256};
use tracing::debug;

use crate::error::Error;

fn etag_for<T: Serialize>(v: T) -> Result<ETag, Error> {
    let mut hasher = Sha256::new();
    serde_json::to_writer(&mut hasher, &v)?;
    let bytes = hasher.finalize();
    let res = format!("\"{}\"", Base64::encode_string(&bytes[..])).parse()
        .map_err(|e| Error::BadETagFormat(format!("{:?}", e)));
    debug!("result: {:?}", res);
    res

}

#[derive(Debug)]
pub enum CondUpdateHeader {
    IfMatch(headers::IfMatch),
    None
}

#[derive(Debug)]
pub struct CondHeaderRejection(headers::Error);

impl IntoResponse for CondHeaderRejection {
    fn into_response(self) -> Response {
        let status = StatusCode::BAD_REQUEST;
        let body = "conditional header improperly formatted";
        (status, body).into_response()
    }
}

#[async_trait]
impl<S: Send + Sync> FromRequestParts<S> for CondUpdateHeader {
    type Rejection = CondHeaderRejection;

    #[doc = "Extract CondUpdateHeader from Request"]
    #[must_use]
    #[allow(clippy::type_complexity,clippy::type_repetition_in_bounds)]
    async fn from_request_parts(parts: &mut request::Parts, _state: &S) ->  Result<Self,Self::Rejection> {
        let mut values = parts.headers.get_all(IfMatch::name()).iter();
        if values.size_hint() == (0, Some(0)) {
            Ok(Self::None)
        } else {
            IfMatch::decode(&mut values)
                .map(Self::IfMatch)
                .map_err(CondHeaderRejection)
        }
    }
}

impl CondUpdateHeader {
    pub fn guard_update(&self, body: impl Serialize) -> Result<(), Error> {
        match self {
            CondUpdateHeader::IfMatch(if_match) => if if_match.precondition_passes( &etag_for(body)?) {
                Ok(())
            } else {
                Err(Error::PreconditionFailed("etag didn't match for update".to_string()))
            },
            CondUpdateHeader::None =>  Ok(())
        }
    }
}

pub enum CondRetreiveHeader {
    IfNoneMatch(headers::IfNoneMatch),
    None
}

#[async_trait]
impl<S: Send + Sync> FromRequestParts<S> for CondRetreiveHeader {
    type Rejection = CondHeaderRejection;

    #[doc = "Extract CondRetreiveHeader from Request"]
    #[must_use]
    // #[allow(elided_named_lifetimes,clippy::type_complexity,clippy::type_repetition_in_bounds)]
    #[allow(clippy::type_complexity,clippy::type_repetition_in_bounds)]
    async fn from_request_parts(parts: &mut request::Parts, _state: &S) ->  Result<Self,Self::Rejection> {
        let mut values = parts.headers.get_all(IfNoneMatch::name()).iter();
        if values.size_hint() == (0, Some(0)) {
            Ok(Self::None)
        } else {
            IfNoneMatch::decode(&mut values)
                .map(Self::IfNoneMatch)
                .map_err(CondHeaderRejection)
        }
    }
}

impl CondRetreiveHeader {
    pub fn respond(&self, body: impl Serialize + Clone) -> Result<impl IntoResponse, Error> {
        match self {
            CondRetreiveHeader::IfNoneMatch(none_match) => {
                let etag = etag_for(body.clone())?;
                if none_match.precondition_passes(&etag) {
                    Ok(EtaggedJson(body).into_response())
                } else {
                    Ok((StatusCode::NOT_MODIFIED, TypedHeader(etag)).into_response())
                }
            }
            CondRetreiveHeader::None => Ok(EtaggedJson(body).into_response())
        }
    }
}

pub struct EtaggedJson<T: Serialize + Clone>(pub T);

impl<T: Serialize + Clone> EtaggedJson<T> {
    fn inner_response(self) -> Result<impl IntoResponse, Error> {
        Ok((TypedHeader(etag_for(self.0.clone())?), Json(self.0)))
    }
}

impl<T: Serialize + Clone> IntoResponse for EtaggedJson<T> {
    fn into_response(self) -> axum::response::Response {
        self.inner_response().into_response()
    }
}
