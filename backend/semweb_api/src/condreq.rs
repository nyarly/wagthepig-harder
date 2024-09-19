use axum::{async_trait, extract::FromRequestParts, http::request, response::IntoResponse, Json};
use axum_extra::{headers::{self, ETag, IfMatch}, typed_header::TypedHeaderRejection, TypedHeader};
use hyper::StatusCode;
use serde::Serialize;
use base64ct::{Base64, Encoding};
use sha2::{Digest, Sha256};

use crate::error::Error;

fn etag_for<T: Serialize>(v: T) -> Result<ETag, Error> {
    let mut hasher = Sha256::new();
    serde_json::to_writer(&mut hasher, &v)?;
    let bytes = hasher.finalize();
    format!("\"{}\"", Base64::encode_string(&bytes[..])).parse()
        .map_err(|e| Error::BadETagFormat(format!("{:?}", e)))

}


pub type IfMatchResult = Result<TypedHeader<IfMatch>, TypedHeaderRejection>;

pub enum CondUpdateHeader {
    IfMatch(headers::IfMatch),
    None
}

#[async_trait]
impl<S: Send + Sync> FromRequestParts<S> for CondUpdateHeader {
    type Rejection = TypedHeaderRejection;

    #[doc = "Extract CondUpdateHeader from Request"]
    #[must_use]
    // #[allow(elided_named_lifetimes,clippy::type_complexity,clippy::type_repetition_in_bounds)]
    #[allow(clippy::type_complexity,clippy::type_repetition_in_bounds)]
    async fn from_request_parts(parts: & mut request::Parts, state: & S) ->  Result<Self,Self::Rejection> {
        match TypedHeader::from_request_parts(parts, state).await {
            Ok(TypedHeader(h)) => Ok(CondUpdateHeader::IfMatch(h)),
            Err(err) if err.is_missing() => Ok(CondUpdateHeader::None),
            Err(err) => Err(err)
        }
    }
}

impl CondUpdateHeader {
    pub fn allow_update(&self, body: impl Serialize) -> Result<(), Error> {
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
    type Rejection = TypedHeaderRejection;

    #[doc = "Extract CondRetreiveHeader from Request"]
    #[must_use]
    // #[allow(elided_named_lifetimes,clippy::type_complexity,clippy::type_repetition_in_bounds)]
    #[allow(clippy::type_complexity,clippy::type_repetition_in_bounds)]
    async fn from_request_parts(parts: & mut request::Parts, state: & S) ->  Result<Self,Self::Rejection> {
        match TypedHeader::from_request_parts(parts, state).await {
            Ok(TypedHeader(h)) => Ok(CondRetreiveHeader::IfNoneMatch(h)),
            Err(err) if err.is_missing() => Ok(CondRetreiveHeader::None),
            Err(err) => Err(err)
        }
    }
}

impl CondRetreiveHeader {
    pub fn respond(&self, body: impl Serialize + Clone) -> Result<impl IntoResponse, Error> {
        match self {
            CondRetreiveHeader::IfNoneMatch(none_match) => if none_match.precondition_passes(&etag_for(body.clone())?) {
                Ok(EtaggedJson(body).into_response())
            } else {
                Ok(StatusCode::NOT_MODIFIED.into_response())
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
