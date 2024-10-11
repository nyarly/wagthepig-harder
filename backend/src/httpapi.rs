use chrono::NaiveDateTime;
use iri_string::types::IriReferenceString;
use serde::{Deserialize, Serialize};
use tracing::debug;
use zeroize::{Zeroize, ZeroizeOnDrop};

use crate::{
    db::{self, EventId, GameId, NoId, Omit, UserId},
    routing::{
        EmptyLocate, EventGamesLocate, EventLocate, EventUsersLocate, GameLocate, GameUsersLocate, ProfileLocate, RecommendLocate, RouteMap, UserLocate
    }
};

use semweb_api::hypermedia::{self, op, ActionType, IriTemplate, Link, ResourceFields};

pub(crate) use semweb_api::Error;

#[derive(Deserialize, Zeroize, ZeroizeOnDrop)]
pub(crate) struct AuthnRequest {
    pub password: String
}

impl AuthnRequest {
    pub(crate) fn valid(&self) -> Result<(), Error> {
        debug!("Checking length of password");
        if self.password.len() < 12 {
            return Err(Error::InvalidInput("password less than 12 characters".to_string()))
        }
        Ok(())
    }
}

#[derive(Serialize,Clone)]
#[serde(rename_all="camelCase")]
pub(crate) struct EventUserListResponse {
    #[serde(flatten)]
    pub resource_fields: ResourceFields<EventUsersLocate>,

    pub users: Vec<UserResponse>,
}

impl EventUserListResponse {
    pub fn from_query(nested_at: &str, event_id: EventId, list: Vec<db::User<UserId>>) -> Result<Self, Error> {
        Ok(Self{
            resource_fields: ResourceFields::new(
                &RouteMap::EventUsers.prefixed(nested_at),
                EventUsersLocate{event_id},
                "api:eventUsersList",
                vec![ op(ActionType::Find) ]
            )?,
            users: list.into_iter().map(|user|
                UserResponse::from_query(nested_at, user))
                .collect::<Result<_,_>>()?,
        })
    }
}

#[derive(Serialize,Clone)]
#[serde(rename_all="camelCase")]
pub(crate) struct GameUserListResponse {
    #[serde(flatten)]
    pub resource_fields: ResourceFields<GameUsersLocate>,

    pub users: Vec<UserResponse>,
}

impl GameUserListResponse {
    pub fn from_query(nested_at: &str, game_id: GameId, list: Vec<db::User<UserId>>) -> Result<Self, Error> {
        Ok(Self{
            resource_fields: ResourceFields::new(
                &RouteMap::GameUsers.prefixed(nested_at),
                GameUsersLocate{game_id},
                "api:gameUsersList",
                vec![ op(ActionType::Find) ]
            )?,
            users: list.into_iter().map(|user|
                UserResponse::from_query(nested_at, user))
                .collect::<Result<_,_>>()?,
        })
    }
}


#[derive(Serialize, Clone)]
pub(crate) struct UserResponse {
    #[serde(flatten)]
    pub resource_fields: ResourceFields<UserLocate>,

    pub name: Option<String>,
    pub bgg_username: Option<String>,
    pub email: String,
}

impl UserResponse {
    pub(crate) fn from_query(nested_at: &str, value: db::User<UserId>) -> Result<Self, Error> {
        Ok(Self{
            resource_fields: ResourceFields::new(
                &RouteMap::User.prefixed(nested_at),
                UserLocate{ user_id: value.id },
                "api:userById",
                vec![]
            )?,
            name: value.name,
            bgg_username: value.bgg_username,
            email: value.email
        })
    }
}

#[derive(Serialize, Clone)]
pub(crate) struct ProfileResponse {
    #[serde(flatten)]
    pub resource_fields: ResourceFields<ProfileLocate>,

    pub name: Option<String>,
    pub bgg_username: Option<String>,
    pub email: String,
}

impl ProfileResponse {
    pub(crate) fn from_query(nested_at: &str, value: db::User<UserId>) -> Result<Self, Error> {
        Ok(Self{
            resource_fields: ResourceFields::new(
                &RouteMap::Profile.prefixed(nested_at),
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
        let event_route = RouteMap::Event.prefixed(nested_at);
        let event_tmpl = event_route.template()?;

        Ok(Self{
            resource_fields: ResourceFields::new(
                &RouteMap::Events.prefixed(nested_at),
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
                EventResponse::from_query(nested_at,ev))
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
    pub(crate) fn from_query(nested_at: &str, value: db::Event<EventId>) -> Result<Self, Error> {
        Ok(Self{
            resource_fields: ResourceFields::new(
                &RouteMap::Event.prefixed(nested_at),
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
pub(crate) struct RegisterRequest {
    pub name: String,
    pub bgg_username: String,
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
    pub users: Link,
    pub games: Vec<GameResponse>
}

impl EventGameListResponse {
    pub fn from_query(nested_at: &str, event_id: EventId, user_id: String, list: Vec<db::Game<GameId, EventId, UserId, db::InterestData>>) -> Result<Self, Error> {
        Ok(Self{
            resource_fields: ResourceFields::new(
                &RouteMap::EventGames.prefixed(nested_at),
                EventGamesLocate{ event_id, user_id },
                "api:gamesListByEventIdTemplate",
                vec![ op(ActionType::View), op(ActionType::Add) ]
            )?,
            make_recommendation: Link {
                id: RouteMap::Recommend.prefixed(nested_at).fill(RecommendLocate{ event_id })?.into(),
                operation: vec![
                    hypermedia::Operation{
                        r#type: "PlayAction".to_string(),
                        method: axum::http::Method::POST.into()
                    }
                ]
            },
            users: Link {
                id: RouteMap::EventUsers.prefixed(nested_at).fill(EventUsersLocate{ event_id })?.into(),
                operation: vec![ op(ActionType::View) ]
            },
            games: list.into_iter().map(|game|
                GameResponse::from_query(nested_at, game)
            ).collect::<Result<_,_>>()?
        })
    }
}

#[derive(Serialize, Clone)]
#[serde(rename_all="camelCase")]
pub(crate) struct GameResponse {
    #[serde(flatten)]
    pub resource_fields: ResourceFields<GameLocate>,
    pub users: Link,

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
    pub fn from_query<E, U>(nested_at: &str, value: db::Game<GameId, E, U, db::InterestData>) -> Result<Self, Error> {
        Ok(Self{
            resource_fields: ResourceFields::new(
                &RouteMap::Game.prefixed(nested_at),
                GameLocate{ game_id: value.id },
                "api:gameByIdTemplate",
                vec![ op(ActionType::View), op(ActionType::Update) ]
            )?,
            users: Link {
                id: RouteMap::GameUsers.prefixed(nested_at).fill(GameUsersLocate{ game_id: value.id })?.into(),
                operation: vec![ op(ActionType::View) ]
            },

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
        let user_route = RouteMap::User.prefixed(nested_at);
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
        Ok(Self{
            resource_fields: ResourceFields::new(
                &RouteMap::Recommend.prefixed(nested_at),
                RecommendLocate{ event_id },
                "api:recommendByEventId",
                vec![ op(ActionType::Add) ]
            )?,

            games: list.into_iter().map(|game|
              RecommendResponse::from_query(nested_at, game)
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
    pub fn from_query<E, U>(nested_at: &str, value: db::Game<GameId, E, U, Omit>) -> Result<Self, Error> {
        Ok(Self{
            resource_fields: ResourceFields::new(
                &RouteMap::Game.prefixed(nested_at),
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
