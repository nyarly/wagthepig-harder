use axum::{debug_handler, extract::{self, Path, State}, response::IntoResponse, Json};
use mattak::{condreq, hypermedia::{op, ActionType, Link, ResourceFields}};
use serde::{Deserialize, Serialize};
use sqlx::{Pool, Postgres};
use iri_string::types::IriReferenceString;

use crate::{db::{self, EventId, GameId, RecommendData, UserId}, routing::{GameUsersLocate, RecommendLocate, RouteMap, UserLocate}, AppState, Error};

#[derive(Deserialize)]
#[serde(rename_all="camelCase")]
pub(crate) struct RecommendRequest {
    pub players: Vec<IriReferenceString>,
    pub extra_players: u8,
}

impl RecommendRequest {
    pub(crate) fn player_ids(&self, nested_at: &str) -> Result<Vec<UserId>, mattak::Error> {
        let user_route = RouteMap::User.prefixed(nested_at);
        self.players.clone().into_iter().map(|iri| {
            user_route.from_uri::<UserLocate>(iri.as_str().try_into()?).map(|loc| loc.user_id)
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
    pub fn from_query(nested_at: &str, event_id: EventId, list: Vec<db::Game<GameId, EventId, UserId, RecommendData>>) -> Result<Self, Error> {
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
    pub resource_fields: ResourceFields<RecommendLocate>,
    pub users: Link,

    pub name: Option<String>,
    pub min_players: Option<i32>,
    pub max_players: Option<i32>,
    pub bgg_link: Option<String>,
    pub duration_secs: Option<i32>,
    pub bgg_id: Option<String>,
    pub interest_level: i64,
    pub teachers: i64
}

impl RecommendResponse {
    pub fn from_query<U>(nested_at: &str, value: db::Game<GameId, EventId, U, RecommendData>) -> Result<Self, Error> {
        Ok(Self{
            // XXX This is weird; not sure the recommend items need to have a link...
            resource_fields: ResourceFields::new(
                &RouteMap::Recommend.prefixed(nested_at),
                RecommendLocate{ event_id: value.event_id },
                "api:gameByIdTemplate",
                vec![ op(ActionType::View), op(ActionType::Update) ]
            )?,
            users: Link {
                id: RouteMap::GameUsers.prefixed(nested_at).fill(GameUsersLocate{ game_id: value.id })?,
                operation: vec![ op(ActionType::View) ]
            },

            name: value.data.name,
            min_players: value.data.min_players,
            max_players: value.data.max_players,
            bgg_link: value.data.bgg_link,
            duration_secs: value.data.duration_secs,
            bgg_id: value.data.bgg_id,
            interest_level: value.extra.interest_level,
            teachers: value.extra.teachers
        })
    }
}
#[debug_handler(state = AppState)]
pub(crate) async fn make(
    State(db): State<Pool<Postgres>>,
    if_none_match: condreq::CondRetreiveHeader,
    nested_at: extract::NestedPath,
    Path(event_id): extract::Path<EventId>,
    Json(body): extract::Json<RecommendRequest>
) -> Result<impl IntoResponse, Error> {
    let recommend = db::Game::get_recommendation(&db, event_id, body.player_ids(nested_at.as_str())?, body.extra_players).await?;

    let resp = RecommendListResponse::from_query(nested_at.as_str(), event_id, recommend)?;
    if_none_match.respond(resp).map_err(Error::from)
}
