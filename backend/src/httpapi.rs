use core::fmt::Debug;

use axum::{response::IntoResponse, Json};
use axum_extra::{headers::ETag, TypedHeader};
use base64ct::{Base64, Encoding};
use chrono::NaiveDateTime;
use serde::{Deserialize, Serialize};
use serde_json::json;
use sha2::{Digest, Sha256};
use zeroize::{Zeroize, ZeroizeOnDrop};

use crate::{db, routing::{self, route_config, RouteTemplate}};

use semweb_api_derives::{Context, Listable};

mod semweb;
use semweb::*;
pub(crate) use semweb::Error;

const RESOURCE: &str = "Resource";

#[derive(Serialize, Clone)]
struct ResourceType(&'static str);

impl Default for ResourceType {
    fn default() -> Self {
        Self(RESOURCE)
    }
}

#[derive(Serialize, Clone)]
struct ResourceFields {
    pub id: IriReferenceString,
    pub r#type: ResourceType,
    pub operation: Vec<Operation>,
}

impl ResourceFields {
    fn new(id: impl TryInto<IriReferenceString> + Debug + Clone, ops: Vec<Operation>) -> Result<Self, Error> {
        Ok(Self{
            id: id.clone().try_into().map_err(|_| Error::IriConversion(format!("{:?}", id)))?,
            r#type: Default::default(),
            operation: ops
        })
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

pub(crate) fn etag_for<T: Serialize>(v: T) -> Result<ETag, Error> {
    let mut hasher = Sha256::new();
    serde_json::to_writer(&mut hasher, &v)?;
    let bytes = hasher.finalize();
    format!("\"{}\"", Base64::encode_string(&bytes[..])).parse()
        .map_err(|e| Error::BadETagFormat(format!("{:?}", e)))

}

#[derive(Copy, Clone)]
pub(crate) enum RouteMap {
    Root,
    Authenticate,
    Profile,
    Events,
    Event,
    EventGames,
    Game
}

impl RouteTemplate for RouteMap {
    fn route_template(&self) -> String {
        use RouteMap::*;
        match self {
            Root => "/",
            Authenticate => "/authenticate",
            Profile => "/profile/{user_id}",
            Events => "/events",
            Event => "/event/{event_id}",
            EventGames => "/event_games/{event_id}/user/{user_id}",
            Game => "/games/{game_id}",
        }.to_string()
    }
}

#[derive(Serialize, Clone)]
struct EmptyLocate {}

#[derive(Serialize, Clone)]
struct ProfileLocate {
    user_id: u16
}

#[derive(Serialize, Clone)]
struct EventLocate {
    event_id: u16
}


#[derive(Serialize, Clone, Listable, Context)]
struct EventGamesLocate {
    event_id: u16,
    user_id: String
}

#[derive(Serialize, Clone)]
struct GameLocate {
    game_id: u16
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
        let url_template = prefixed.template().expect("a legit URITemplate");
        json!({
            "type": prefixed.hydra_type(),
            url_attr: url_template,
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
    #[serde(flatten)]
    pub resource_fields: ResourceFields,

    pub event_by_id: IriTemplate,
    pub events: Vec<EventResponse>,
}

impl EventListResponse {
    pub fn from_query(nested_at: &str, list: Vec<db::Event>) -> Result<Self, Error> {
        let event_route = route_config(RouteMap::Event).prefixed(nested_at);
        let id = event_route.fill(vec![])?;
        let event_tmpl = event_route.template()?;
        Ok(Self{
            resource_fields: ResourceFields::new(id, vec![ op(ActionType::View), op(ActionType::Add) ])?,
            event_by_id: IriTemplate {
                id: "api:eventByIdTemplate".try_into()?,
                template: event_tmpl,
                operation: vec![ op(ActionType::Find) ]
            },
            events: list.into_iter().map(|ev| EventResponse::from_query(&event_route,ev)).collect::<Result<_,_>>()?,
        })
    }
}

#[derive(Serialize, Clone)]
#[serde(rename_all="camelCase")]
pub(crate) struct EventResponse {
    #[serde(flatten)]
    pub resource_fields: ResourceFields,
    pub event_by_id: IriTemplate,

    pub name: Option<String>,
    pub time: Option<NaiveDateTime>,
    pub location: Option<String>,
    pub description: Option<String>
}

impl EventResponse {
    pub(crate) fn from_query(idtmpl: &routing::Single, value: db::Event) -> Result<Self, Error> {
        let id = idtmpl.fill(vec![("event_id".to_string(), value.id.to_string())])?;
        Ok(Self{
            resource_fields: ResourceFields::new(id, vec![ op(ActionType::View), op(ActionType::Update) ])?,
            name: value.name,
            location: value.r#where,
            event_by_id: IriTemplate {
                id: "api:eventByIdTemplate".try_into()?,
                template: idtmpl.template()?,
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

#[derive(Serialize, Clone)]
#[serde(rename_all="camelCase")]
pub(crate) struct EventGameListResponse {
    #[serde(flatten)]
    pub resource_fields: ResourceFields,
    pub event_games_by_id: IriTemplate,
    // location: Type

    pub games: Vec<EventGameResponse>
}

/*
#[derive(Locator)]
struct EventGameListLocator {
  event_id: u16,
  user_id: String,
}

impl IntoIterator for EventGameListLocator {
  Item = (String, String)

  fn into_iter() -> LocatorIter
}

struct LocatorIter {
  over: EventGameListLocator
  index: 0
}

impl Iterator for LocatorIter {
  fn next() -> Option<(String, String)> {
  }
}
*/

impl EventGameListResponse {
    pub fn from_query(nested_at: &str, event_id: u16, user_id: String, list: Vec<db::Game>) -> Result<Self, Error> {
        let route = &route_config(RouteMap::EventGames).prefixed(nested_at);
        let id = route.fill([
            ("event_id".to_string(), event_id.to_string()),
            ("user_id".to_string(), user_id)
        ])?;
        let game_tmpl = route_config(RouteMap::Game).prefixed(nested_at);
        Ok(Self{
            resource_fields: ResourceFields::new(id, vec![ op(ActionType::View), op(ActionType::Add) ])?,
            event_games_by_id: IriTemplate {
                id: "api:eventGamesByIdTemplate".try_into()?,
                template: route.template()?,
                operation: vec![ op(ActionType::Find) ]
            },
            games: list.into_iter().map(|game|
                EventGameResponse::from_query(&game_tmpl,game)
            ).collect::<Result<_,_>>()?
        })
    }
}

#[derive(Serialize, Clone)]
#[serde(rename_all="camelCase")]
pub(crate) struct EventGameResponse {
    #[serde(flatten)]
    pub resource_fields: ResourceFields,
/*
    pub id: i64,
    pub name: Option<String>,
    pub min_players: Option<i32>,
    pub max_players: Option<i32>,
    pub bgg_link: Option<String>,
    pub duration_secs: Option<i32>,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
    pub event_id: i64,
    pub suggestor_id: i64,
    pub bgg_id: Option<String>,
    pub pitch: Option<String>,
    pub interested: Option<bool>,
    pub can_teach: Option<bool>,
*/
}

impl EventGameResponse {
    pub fn from_query(tmpl: &routing::Single, value: db::Game) -> Result<Self, Error> {
        let id = tmpl.fill([("game_id".to_string(), value.id.to_string())])?;
        Ok(Self{
            resource_fields: ResourceFields::new(id, vec![ op(ActionType::View), op(ActionType::Update) ])?,
        })
    }
}
