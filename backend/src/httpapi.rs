use axum::{response::IntoResponse, Json};
use axum_extra::{headers::ETag, TypedHeader};
use base64ct::{Base64, Encoding};
use chrono::NaiveDateTime;
use iri_string::types::IriReferenceString;
use serde::{Deserialize, Serialize};
use serde_json::json;
use sha2::{Digest, Sha256};
use zeroize::{Zeroize, ZeroizeOnDrop};

use crate::db::{self, NoId, Omit, EventId, GameId, UserId};

use semweb_api_derives::{Context, Extract, Listable};
use semweb_api::{
    hypermedia::{self, op, ActionType, IriTemplate, Link, ResourceFields},
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
    User,
    Events,
    Event,
    EventGames,
    Game,
    Recommend
}

impl RouteTemplate for RouteMap {
    fn route_template(&self) -> String {
        use RouteMap::*;
        match self {
            Root => "/",
            Authenticate => "/authenticate",
            Profile => "/profile/{user_id}", // by login
            User => "/profile/{user_id}", // by ID
            Events => "/events",
            Event => "/event/{event_id}",
            EventGames => "/event_games/{event_id}/user/{user_id}",
            Game => "/games/{game_id}/user/{user_id}",
            Recommend => "/recommend/{event_id}/for/{user_id}"
        }.to_string()
    }
}

#[derive(Default, Serialize, Copy, Clone, Listable, Context, Extract)]
pub(crate) struct EmptyLocate {}

#[derive(Default, Serialize, Clone, Listable, Context, Extract)]
pub(crate) struct ProfileLocate {
    pub user_id: String
}

#[derive(Serialize, Clone, Listable, Context, Extract)]
pub(crate) struct UserLocate {
    pub user_id: UserId
}

#[derive(Serialize, Copy, Clone, Listable, Context, Extract)]
pub(crate) struct EventLocate {
    pub event_id: EventId
}

#[derive(Serialize, Clone, Listable, Context, Extract)]
pub(crate) struct EventGamesLocate {
    pub event_id: EventId,
    pub user_id: String
}

#[derive(Serialize, Copy, Clone, Listable, Context, Extract)]
pub(crate) struct GameLocate {
    pub game_id: GameId
}

#[derive(Serialize, Copy, Clone, Listable, Context, Extract)]
pub(crate) struct RecommendLocate {
    pub event_id: EventId
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
    pub(crate) fn db_param(&self) -> db::Game<NoId, NoId, NoId, Omit> {
        db::Game {
            id: NoId,
            event_id: NoId,
            suggestor_id: NoId,
            data: db::GameData{
                name: self.name.clone(),
                min_players: self.min_players,
                max_players: self.max_players,
                bgg_link: self.bgg_link.clone(),
                duration_secs: self.duration_secs,
                bgg_id: self.bgg_id.clone(),
                pitch: self.pitch.clone(),
                created_at: NaiveDateTime::default(),
                updated_at: NaiveDateTime::default(),
            },
            interest: Omit{}
        }
    }

    pub(crate) fn interest_part(&self) -> db::InterestData {
        db::InterestData {
            interested: self.interested,
            can_teach: self.can_teach,
            notes: self.notes.clone()
        }
    }
}


#[derive(Serialize, Clone)]
#[serde(rename_all="camelCase")]
pub(crate) struct EventGameListResponse {
    #[serde(flatten)]
    pub resource_fields: ResourceFields<EventGamesLocate>,

    pub make_recommendation: Link,
    pub games: Vec<GameResponse>
}

impl EventGameListResponse {
    pub fn from_query(nested_at: &str, event_id: EventId, user_id: String, list: Vec<db::Game<GameId, EventId, UserId, db::InterestData>>) -> Result<Self, Error> {
        let game_tmpl = route_config(RouteMap::Game).prefixed(nested_at);
        Ok(Self{
            resource_fields: ResourceFields::new(
                &route_config(RouteMap::EventGames).prefixed(nested_at),
                EventGamesLocate{ event_id, user_id },
                "api:gamesListByEventIdTemplate",
                vec![ op(ActionType::View), op(ActionType::Add) ]
            )?,
            make_recommendation: Link {
                id: route_config(RouteMap::Recommend).prefixed(nested_at).fill(RecommendLocate{ event_id })?.into(),
                operation: vec![
                    hypermedia::Operation{
                        r#type: "PlayAction".to_string(),
                        method: axum::http::Method::POST.into()
                    }
                ]
            },
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
    pub notes: Option<String>,
}

impl GameResponse {
    pub fn from_query<E, U>(route: &routing::Entry, value: db::Game<GameId, E, U, db::InterestData>) -> Result<Self, Error> {
        Ok(Self{
            resource_fields: ResourceFields::new(
                route,
                GameLocate{ game_id: value.id },
                "api:gameByIdTemplate",
                vec![ op(ActionType::View), op(ActionType::Update) ]
            )?,

            name: value.data.name,
            min_players: value.data.min_players,
            max_players: value.data.max_players,
            bgg_link: value.data.bgg_link,
            duration_secs: value.data.duration_secs,
            bgg_id: value.data.bgg_id,
            pitch: value.data.pitch,
            interested: value.interest.interested,
            can_teach: value.interest.can_teach,
            notes: value.interest.notes,
        })
    }
}

#[derive(Deserialize)]
#[serde(rename_all="camelCase")]
pub(crate) struct RecommendRequest {
    pub players: Vec<IriReferenceString>,
    pub extra_players: u8,
}

impl RecommendRequest {
    pub(crate) fn player_ids(&self, nested_at: &str) -> Result<Vec<UserId>, Error> {
        let user_route = route_config(RouteMap::User).prefixed(nested_at);
        self.players.clone().into_iter().map(|iri| {
            user_route.extract::<UserLocate>(iri.as_str()).map(|loc| loc.user_id)
        }).collect::<Result<Vec<_>,_>>()
    }
}

#[derive(Serialize, Clone)]
#[serde(rename_all="camelCase")]
pub(crate) struct RecommendListResponse {
    #[serde(flatten)]
    pub resource_fields: ResourceFields<RecommendLocate>,

    pub games: Vec<RecommendResponse>
}

impl RecommendListResponse {
    pub fn from_query(nested_at: &str, event_id: EventId, list: Vec<db::Game<GameId, EventId, UserId, Omit>>) -> Result<Self, Error> {
        let game_route = route_config(RouteMap::Game).prefixed(nested_at);
        Ok(Self{
            resource_fields: ResourceFields::new(
                &route_config(RouteMap::Recommend).prefixed(nested_at),
                RecommendLocate{ event_id },
                "api:recommendByEventId",
                vec![ op(ActionType::Add) ]
            )?,

            games: list.into_iter().map(|game|
              RecommendResponse::from_query(&game_route, game)
            ).collect::<Result<_,_>>()?
        })
    }
}

#[derive(Serialize, Clone)]
#[serde(rename_all="camelCase")]
pub(crate) struct RecommendResponse {
    #[serde(flatten)]
    pub resource_fields: ResourceFields<GameLocate>,

    pub name: Option<String>,
    pub min_players: Option<i32>,
    pub max_players: Option<i32>,
    pub bgg_link: Option<String>,
    pub duration_secs: Option<i32>,
    pub bgg_id: Option<String>,
}

impl RecommendResponse {
    pub fn from_query<E, U>(route: &routing::Entry, value: db::Game<GameId, E, U, Omit>) -> Result<Self, Error> {
        Ok(Self{
            resource_fields: ResourceFields::new(
                route,
                GameLocate{ game_id: value.id },
                "api:gameByIdTemplate",
                vec![ op(ActionType::View), op(ActionType::Update) ]
            )?,
            name: value.data.name,
            min_players: value.data.min_players,
            max_players: value.data.max_players,
            bgg_link: value.data.bgg_link,
            duration_secs: value.data.duration_secs,
            bgg_id: value.data.bgg_id,
        })
    }
}
