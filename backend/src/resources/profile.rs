use axum::{debug_handler, extract::{self, Path, State}, response::IntoResponse};
use semweb_api::{condreq, hypermedia::{op, ActionType, ResourceFields}};
use serde::Serialize;
use sqlx::{Pool, Postgres};

use crate::{
    db::{EventId, GameId, User, UserId},
    routing::{EventUsersLocate, GameUsersLocate, ProfileLocate, RouteMap, UserLocate},
    AppState, Error
};

#[derive(Serialize,Clone)]
#[serde(rename_all="camelCase")]
pub(crate) struct EventUserListResponse {
    #[serde(flatten)]
    pub resource_fields: ResourceFields<EventUsersLocate>,

    pub users: Vec<UserResponse>,
}

impl EventUserListResponse {
    pub fn from_query(nested_at: &str, event_id: EventId, list: Vec<User<UserId>>) -> Result<Self, Error> {
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
    pub fn from_query(nested_at: &str, game_id: GameId, list: Vec<User<UserId>>) -> Result<Self, Error> {
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
pub(crate) struct ProfileResponse {
    #[serde(flatten)]
    pub resource_fields: ResourceFields<ProfileLocate>,

    pub name: Option<String>,
    pub bgg_username: Option<String>,
    pub email: String,
}

impl ProfileResponse {
    pub(crate) fn from_query(nested_at: &str, value: User<UserId>) -> Result<Self, Error> {
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

#[derive(Serialize, Clone)]
pub(crate) struct UserResponse {
    #[serde(flatten)]
    pub resource_fields: ResourceFields<UserLocate>,

    pub name: Option<String>,
    pub bgg_username: Option<String>,
    pub email: String,
}

impl UserResponse {
    pub(crate) fn from_query(nested_at: &str, value: User<UserId>) -> Result<Self, Error> {
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


#[debug_handler(state = AppState)]
pub(crate) async fn get(
    State(db): State<Pool<Postgres>>,
    if_none_match: condreq::CondRetreiveHeader,
    nested_at: extract::NestedPath,
    Path(user_id): Path<String>
) -> Result<impl IntoResponse, Error> {
    let profile = User::by_email(&db, user_id).await?;
    if_none_match.respond(ProfileResponse::from_query(nested_at.as_str(), profile)?).map_err(Error::from)
}

#[debug_handler(state = AppState)]
pub(crate) async fn get_event_list(
    State(db): State<Pool<Postgres>>,
    if_none_match: condreq::CondRetreiveHeader,
    nested_at: extract::NestedPath,
    Path(event_id): extract::Path<EventId>,
) -> Result<impl IntoResponse, Error> {
    let users = User::get_all_by_event_id(&db, event_id).await?;
    let resp = EventUserListResponse::from_query(nested_at.as_str(), event_id, users)?;
    if_none_match.respond(resp).map_err(Error::from)
}

#[debug_handler(state = AppState)]
pub(crate) async fn get_game_list(
    State(db): State<Pool<Postgres>>,
    if_none_match: condreq::CondRetreiveHeader,
    nested_at: extract::NestedPath,
    Path(game_id): extract::Path<GameId>,
) -> Result<impl IntoResponse, Error> {
    let users = User::get_all_by_game_id(&db, game_id).await?;
    let resp = GameUserListResponse::from_query(nested_at.as_str(), game_id, users)?;
    if_none_match.respond(resp).map_err(Error::from)
}
