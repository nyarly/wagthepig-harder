use axum::{debug_handler, extract::{self, Path, State}, response::IntoResponse, Json};
use chrono::NaiveDateTime;
use hyper::{header, StatusCode};
use semweb_api::{condreq, hypermedia::{self, op, ActionType, Link, ResourceFields}};
use serde::{Deserialize, Serialize};
use sqlx::{Pool, Postgres};

use crate::{
    db::{self, EventId, Game, GameId, NoId, Omit, UserId},
    routing::{EventGamesLocate, EventUsersLocate, GameLocate, GameUsersLocate, RecommendLocate, RouteMap},
    AppState, Error
};

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
    pub(crate) fn db_param(&self) -> Game<NoId, NoId, NoId, Omit> {
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
                id: RouteMap::Recommend.prefixed(nested_at).fill(RecommendLocate{ event_id })?,
                operation: vec![
                    hypermedia::Operation{
                        r#type: "PlayAction".to_string(),
                        method: axum::http::Method::POST.into()
                    }
                ]
            },
            users: Link {
                id: RouteMap::EventUsers.prefixed(nested_at).fill(EventUsersLocate{ event_id })?,
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
                id: RouteMap::GameUsers.prefixed(nested_at).fill(GameUsersLocate{ game_id: value.id })?,
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

#[debug_handler(state = AppState)]
pub(crate) async fn create_new(
    State(db): State<Pool<Postgres>>,
    nested_at: extract::NestedPath,
    Path((event_id, user_id)): extract::Path<(EventId, String)>,
    Json(body): extract::Json<GameUpdateRequest>
) -> Result<impl IntoResponse, Error> {
    let mut tx = db.begin().await.map_err(db::Error::from)?;

    let game = body.db_param().with_event_id(event_id);
    let new_id = game.add_new(&mut *tx, user_id.clone()).await?;
    let game = game.with_id(new_id).with_interest_data(body.interest_part());
    game.update_interests(&mut *tx, user_id).await?;

    tx.commit().await.map_err(db::Error::from)?;

    let location_uri = RouteMap::Game.prefixed(nested_at.as_str())
        .fill(GameLocate{ game_id: new_id })
        .map_err(Error::from)?;

    Ok((StatusCode::CREATED, [(header::LOCATION, location_uri.to_string())]))
}

#[debug_handler(state = AppState)]
pub(crate) async fn get_scoped_list(
    State(db): State<Pool<Postgres>>,
    if_none_match: condreq::CondRetreiveHeader,
    nested_at: extract::NestedPath,
    Path((event_id, user_id)): extract::Path<(EventId, String)>,
) -> Result<impl IntoResponse, Error> {
    let games = Game::get_all_for_event_and_user(&db, event_id, user_id.clone()).await?;
    let resp = EventGameListResponse::from_query(nested_at.as_str(), event_id, user_id, games)?;
    if_none_match.respond(resp).map_err(Error::from)
}

#[debug_handler(state = AppState)]
pub(crate) async fn update(
    State(db): State<Pool<Postgres>>,
    if_match: condreq::CondUpdateHeader,
    nested_at: extract::NestedPath,
    Path((game_id, user_id)): extract::Path<(GameId, String)>,
    Json(body): extract::Json<GameUpdateRequest>
) -> Result<impl IntoResponse, Error> {
    let game = retrieve(&db, &nested_at, game_id, user_id.clone()).await?;

    if_match.guard_update(game)?;

    let mut tx = db.begin().await.map_err(db::Error::from)?;
    let game = body.db_param()
        .with_id(game_id)
        .update(&mut *tx).await
        .map_err(Error::from)?;

    let game = game.with_interest_data(body.interest_part());

    game.update_interests(&mut *tx, user_id).await
        .map_err(Error::from)?;

    tx.commit().await.map_err(db::Error::from)?;

    Ok(Json(GameResponse::from_query(nested_at.as_str(), game)?))
}

async fn retrieve(
    db: &Pool<Postgres>,
    nested_at: &extract::NestedPath,
    game_id: GameId,
    user_id: String,
) -> Result<GameResponse, Error> {
    let maybe_game = Game::get_by_id_and_user(db, game_id, user_id).await?;

    match maybe_game {
        Some(game) => {
            GameResponse::from_query(nested_at.as_str(), game)
                .map_err(Error::from)
        },
        None => Err((StatusCode::NOT_FOUND, "not found").into())
    }
}
