use axum::{response::IntoResponse, Json};
use axum_extra::{headers::ETag, TypedHeader};
use base64ct::{Base64, Encoding};
use chrono::NaiveDateTime;
use serde::{Deserialize, Serialize};
use serde_json::json;
use sha2::{Digest, Sha256};
use zeroize::{Zeroize, ZeroizeOnDrop};

use crate::db::{self, EventId, GameId, NoId, UserId};

use semweb_api_derives::{Context, Listable};
use semweb_api::{
    hypermedia::{op, ActionType, IriTemplate, ResourceFields},
    routing::{self, route_config, RouteTemplate}
};

// XXX remove
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
    pub user_id: String
}

#[derive(Serialize, Copy, Clone, Listable, Context)]
pub(crate) struct EventLocate {
    pub event_id: EventId
}

#[derive(Serialize, Clone, Listable, Context)]
pub(crate) struct EventGamesLocate {
    pub event_id: EventId,
    pub user_id: String
}

#[derive(Serialize, Copy, Clone, Listable, Context)]
pub(crate) struct GameLocate {
    pub game_id: GameId
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
    pub(crate) fn from_query(nested_at: &str, value: db::User<UserId>) -> Result<Self, Error> {
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

#[derive(Serialize,Clone)]
#[serde(rename_all="camelCase")]
pub(crate) struct EventListResponse {
    #[serde(flatten)]
    pub resource_fields: ResourceFields<EmptyLocate>,

    pub event_by_id: IriTemplate,
    pub events: Vec<EventResponse>,
}

impl EventListResponse {
    pub fn from_query(nested_at: &str, list: Vec<db::Event<EventId>>) -> Result<Self, Error> {
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
    pub(crate) fn from_query(idtmpl: &routing::Entry, value: db::Event<EventId>) -> Result<Self, Error> {
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
    pub(crate) fn db_param(&self) -> db::Event<NoId> {
        db::Event {
            name: self.name.clone(),
            date: self.time,
            r#where: self.location.clone(),
            description: self.description.clone(),
            ..db::Event::default()
        }
    }
}

#[derive(Deserialize)]
#[serde(rename_all="camelCase")]
pub(crate) struct GameUpdateRequest {
    pub name: Option<String>,
    pub min_players: Option<i32>,
    pub max_players: Option<i32>,
    pub bgg_link: Option<String>,
    pub duration_secs: Option<i32>,
    pub bgg_id: Option<String>,
    pub pitch: Option<String>,
    pub interested: Option<bool>,
    pub can_teach: Option<bool>,
    pub notes: Option<String>,
}

impl GameUpdateRequest {
    pub(crate) fn for_insert_on_event(&self, event_id: EventId) -> db::Game<NoId, EventId> {
        db::Game {
            id: NoId,
            suggestor_id: 0.into(),
            event_id,
            name: self.name.clone(),
            min_players: self.min_players,
            max_players: self.max_players,
            bgg_link: self.bgg_link.clone(),
            duration_secs: self.duration_secs,
            bgg_id: self.bgg_id.clone(),
            pitch: self.pitch.clone(),
            interested: self.interested,
            can_teach: self.can_teach,
            notes: self.notes.clone(),
            created_at: NaiveDateTime::default(),
            updated_at: NaiveDateTime::default(),
        }
    }

    pub(crate) fn for_update(&self) -> db::Game<NoId, NoId> {
        db::Game {
            id: NoId,
            event_id: NoId,
            suggestor_id: 0.into(),
            name: self.name.clone(),
            min_players: self.min_players,
            max_players: self.max_players,
            bgg_link: self.bgg_link.clone(),
            duration_secs: self.duration_secs,
            bgg_id: self.bgg_id.clone(),
            pitch: self.pitch.clone(),
            interested: self.interested,
            can_teach: self.can_teach,
            notes: self.notes.clone(),
            created_at: NaiveDateTime::default(),
            updated_at: NaiveDateTime::default(),
        }
    }
}


#[derive(Serialize, Clone)]
#[serde(rename_all="camelCase")]
pub(crate) struct EventGameListResponse {
    #[serde(flatten)]
    pub resource_fields: ResourceFields<EventGamesLocate>,

    pub games: Vec<GameResponse>
}

impl EventGameListResponse {
    pub fn from_query(nested_at: &str, event_id: EventId, user_id: String, list: Vec<db::Game<GameId, EventId>>) -> Result<Self, Error> {
        let game_tmpl = route_config(RouteMap::Game).prefixed(nested_at);
        Ok(Self{
            resource_fields: ResourceFields::new(
                &route_config(RouteMap::EventGames).prefixed(nested_at),
                EventGamesLocate{ event_id, user_id },
                "api:gamesListByEventIdTemplate",
                vec![ op(ActionType::View), op(ActionType::Add) ]
            )?,
            games: list.into_iter().map(|game|
                GameResponse::from_query(&game_tmpl,game)
            ).collect::<Result<_,_>>()?
        })
    }
}

#[derive(Serialize, Clone)]
#[serde(rename_all="camelCase")]
pub(crate) struct GameResponse {
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

impl GameResponse {
    pub fn from_query<E>(route: &routing::Entry, value: db::Game<GameId, E>) -> Result<Self, Error> {
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
