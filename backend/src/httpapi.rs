use axum::{response::IntoResponse, Json};
use axum_extra::{headers::ETag, TypedHeader};
use base64ct::{Base64, Encoding};
use chrono::NaiveDateTime;
use serde::{Deserialize, Serialize};
use serde_json::json;
use sha2::{Digest, Sha256};
use zeroize::{Zeroize, ZeroizeOnDrop};

use crate::db;

use semweb_api_derives::{Context, Listable};
use semweb_api::{
    hypermedia::{op, ActionType, IriTemplate, ResourceFields},
    routing::{self, route_config, RouteTemplate}
};

pub(crate) use semweb_api::Error;
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

#[derive(Default, Serialize, Copy, Clone, Listable, Context)]
pub(crate) struct EmptyLocate {}

#[derive(Default, Serialize, Clone, Listable, Context)]
pub(crate) struct ProfileLocate {
    user_id: String
}

#[derive(Default, Serialize, Copy, Clone, Listable, Context)]
pub(crate) struct EventLocate {
    event_id: i64
}

#[derive(Default, Serialize, Clone, Listable, Context)]
pub(crate) struct EventGamesLocate {
    event_id: i64,
    user_id: String
}

#[derive(Default, Serialize, Copy, Clone, Listable, Context)]
pub(crate) struct GameLocate {
    game_id: i64
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

#[derive(Serialize, Clone)]
pub(crate) struct UserResponse {
    #[serde(flatten)]
    pub resource_fields: ResourceFields<ProfileLocate>,

    pub name: Option<String>,
    pub bgg_username: Option<String>,
    pub email: String,
}

impl UserResponse {
    pub(crate) fn from_query(nested_at: &str, value: db::User) -> Result<Self, Error> {
        Ok(Self{
            resource_fields: ResourceFields::new(
                &route_config(RouteMap::Profile).prefixed(nested_at),
                ProfileLocate{ user_id: value.email.clone() },
                "api:profileByEmailTemplate",
                vec![ op(ActionType::View) ]
            )?,
            name: value.name,
            bgg_username: value.bgg_username,
            email: value.email
        })
    }
}

#[derive(Serialize)]
#[serde(rename_all="camelCase")]
pub(crate) struct EventListResponse {
    #[serde(flatten)]
    pub resource_fields: ResourceFields<EmptyLocate>,

    pub event_by_id: IriTemplate,
    pub events: Vec<EventResponse>,
}

impl EventListResponse {
    pub fn from_query(nested_at: &str, list: Vec<db::Event>) -> Result<Self, Error> {
        let event_route = route_config(RouteMap::Event).prefixed(nested_at);
        let event_tmpl = event_route.template()?;

        Ok(Self{
            resource_fields: ResourceFields::new(
                &route_config(RouteMap::Events).prefixed(nested_at),
                EmptyLocate{},
                "api:eventsList",
                vec![ op(ActionType::View), op(ActionType::Add) ]
            )?,
            event_by_id: IriTemplate {
                id: "api:eventByIdTemplate".try_into()?,
                template: event_tmpl,
                operation: vec![ op(ActionType::Find) ]
            },
            events: list.into_iter().map(|ev|
                EventResponse::from_query(&event_route,ev))
                .collect::<Result<_,_>>()?,
        })
    }
}

#[derive(Serialize, Clone)]
#[serde(rename_all="camelCase")]
pub(crate) struct EventResponse {
    #[serde(flatten)]
    pub resource_fields: ResourceFields<EventLocate>,

    pub name: Option<String>,
    pub time: Option<NaiveDateTime>,
    pub location: Option<String>,
    pub description: Option<String>
}

impl EventResponse {
    pub(crate) fn from_query(idtmpl: &routing::Entry, value: db::Event) -> Result<Self, Error> {
        Ok(Self{
            resource_fields: ResourceFields::new(
                idtmpl,
                EventLocate{ event_id: value.id },
                "api:eventByIdTemplate",
                vec![ op(ActionType::View), op(ActionType::Update) ]
            )?,

            name: value.name,
            location: value.r#where,
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
    pub resource_fields: ResourceFields<EventGamesLocate>,

    pub games: Vec<EventGameResponse>
}

impl EventGameListResponse {
    pub fn from_query(nested_at: &str, event_id: i64, user_id: String, list: Vec<db::Game>) -> Result<Self, Error> {
        let game_tmpl = route_config(RouteMap::Game).prefixed(nested_at);
        Ok(Self{
            resource_fields: ResourceFields::new(
                &route_config(RouteMap::EventGames).prefixed(nested_at),
                EventGamesLocate{ event_id, user_id },
                "api:gamesListByEventIdTemplate",
                vec![ op(ActionType::View), op(ActionType::Add) ]
            )?,
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
    pub resource_fields: ResourceFields<GameLocate>,

    pub name: Option<String>,
    pub min_players: Option<i32>,
    pub max_players: Option<i32>,
    pub bgg_link: Option<String>,
    pub duration_secs: Option<i32>,
    pub bgg_id: Option<String>,
    pub pitch: Option<String>,
    pub interested: Option<bool>,
    pub can_teach: Option<bool>,

/*
    // it might be nice to include name/email of suggestor
    //   debatable though: are we trying to play games,
    //   or play with specific people?
    //
    pub suggestor_id: i64,
*/
}

impl EventGameResponse {
    pub fn from_query(route: &routing::Entry, value: db::Game) -> Result<Self, Error> {
        Ok(Self{
            resource_fields: ResourceFields::new(
                route,
                GameLocate{ game_id: value.id },
                "api:gameByIdTemplate",
                vec![ op(ActionType::View), op(ActionType::Update) ]
            )?,

            name: value.name,
            min_players: value.min_players,
            max_players: value.max_players,
            bgg_link: value.bgg_link,
            duration_secs: value.duration_secs,
            bgg_id: value.bgg_id,
            pitch: value.pitch,
            interested: value.interested,
            can_teach: value.can_teach,
        })
    }
}
