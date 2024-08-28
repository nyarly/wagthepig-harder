use axum::{response::IntoResponse, Json};
use axum_extra::{headers::ETag, TypedHeader};
use base64ct::{Base64, Encoding};
use chrono::NaiveDateTime;
use iri_string::{
    spec::IriSpec,
    template::{simple_context::SimpleContext, UriTemplateStr}};
use serde::{Deserialize, Serialize};
use serde_json::json;
use sha2::{Digest, Sha256};
use zeroize::{Zeroize, ZeroizeOnDrop};

use crate::db;

use crate::routing;

mod semweb;
use semweb::*;
pub(crate) use semweb::Error;

pub(crate) enum RouteMap {
    Root,
    Authenticate,
    Profile,
    Events,
    Event
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

pub(crate) fn etag_for<T: Serialize>(v: T) -> Result<ETag, Error> {
    let mut hasher = Sha256::new();
    serde_json::to_writer(&mut hasher, &v)?;
    let bytes = hasher.finalize();
    format!("\"{}\"", Base64::encode_string(&bytes[..])).parse()
        .map_err(|e| Error::BadETagFormat(format!("{:?}", e)))

}

pub(crate) fn route_config(rm: RouteMap) -> routing::Config {
    let cfg = |t, cs| routing::Config::new(t, cs);
    use RouteMap::*;
    match rm {
        Root => cfg( "/", vec![]),
        Authenticate => cfg( "/authenticate", vec![]),
        Profile => cfg( "/profile/{user_id}", vec!["user_id"]),
        Events => cfg( "/events", vec![]),
        Event => cfg( "/event/{event_id}", vec!["event_id"])
    }
}

pub(crate) fn api_doc(nested_at: &str) -> impl IntoResponse {
    use RouteMap::*;
    use ActionType::*;
    let entry = |rm, ops| {
        let prefixed = route_config(rm).prefixed(nested_at);
        let url_attr = if prefixed.hydra_type() == "Link" {
            "id"
        } else {
            "template"
        };
        json!({
            "type": prefixed.hydra_type(),
            url_attr: prefixed.template_str,
            "operation": ops
        })
    };

    Json(json!({
      "root": entry(Root, vec![ op(View) ]),
      "authenticate": entry(Authenticate, vec![op(Login)]),
      "profile": entry(Profile, vec![op(Find)]),
      "events": entry(Events, vec![ op(View), op(Add) ]),
      "event": entry(Event, vec![ op(Find), op(Update) ]),
    }))
}

#[derive(Deserialize, Zeroize, ZeroizeOnDrop)]
pub(crate) struct AuthnRequest {
    pub email: String,
    pub password: String
}

#[derive(Default, Serialize, Clone)]
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

#[derive(Serialize)]
#[serde(rename_all="camelCase")]
pub(crate) struct EventListResponse {
    pub id: IriReferenceString,
    pub r#type: String,
    pub event_by_id: IriTemplate,
    pub events: Vec<EventResponse>,
    pub operation: Vec<Operation>
}

impl EventListResponse {
    pub fn from_query(nested_at: &str, list: Vec<db::Event>) -> Result<Self, Error> {
        let id = route_config(RouteMap::Events).prefixed(nested_at).axum_route();
        let event_tmpl = route_config(RouteMap::Event).prefixed(nested_at).template()?;
        Ok(Self{
            id: id.try_into()?,
            r#type: "Resource".to_string(),
            operation: vec![ op(ActionType::View), op(ActionType::Add) ],
            event_by_id: IriTemplate {
                id: "api:eventByIdTemplate".try_into()?,
                template: event_tmpl.as_str().to_string(),
                operation: vec![ op(ActionType::Find) ]
            },
            events: list.into_iter().map(|ev| EventResponse::from_query(&event_tmpl,ev)).collect::<Result<_,_>>()?
        })
    }
}

#[derive(Serialize, Clone)]
#[serde(rename_all="camelCase")]
pub(crate) struct EventResponse {
    pub id: IriReferenceString,
    pub r#type: String,
    pub event_by_id: IriTemplate,
    pub name: Option<String>,
    pub time: Option<NaiveDateTime>,
    pub location: Option<String>,
    pub description: Option<String>
}

impl EventResponse {
    pub(crate) fn from_query(idtmpl: &UriTemplateStr, value: db::Event) -> Result<Self, Error> {
        let mut context = SimpleContext::new();
        context.insert("id", value.id.to_string());
        Ok(Self{
            name: value.name,
            location: value.r#where,
            id: idtmpl.expand::<IriSpec, _>(&context)?.to_string().try_into()?,
            r#type: "Resource".to_string(),
            event_by_id: IriTemplate {
                id: "api:eventByIdTemplate".try_into()?,
                template: idtmpl.as_str().into(),
                operation: vec![ op(ActionType::Find) ]
            },
            time: value.date,
            description: value.description.clone()
        })
    }
}

#[derive(Deserialize)]
#[serde(rename_all="camelCase")]
pub(crate) struct EventUpdateRequest {
    pub name: Option<String>,
    pub time: Option<NaiveDateTime>,
    pub location: Option<String>,
    pub description: Option<String>
}

impl EventUpdateRequest {
    pub(crate) fn db_param(&self) -> db::Event {
        db::Event {
            name: self.name.clone(),
            date: self.time,
            r#where: self.location.clone(),
            description: self.description.clone(),
            ..db::Event::default()
        }
    }
}
