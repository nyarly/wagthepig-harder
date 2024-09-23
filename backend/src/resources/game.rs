use axum::{debug_handler, extract::{self, Path, State}, response::IntoResponse, Json};
use hyper::{header, StatusCode};
use semweb_api::{condreq, routing::{self}};
use sqlx::{Pool, Postgres};

use crate::{routing::{GameLocate, RouteMap}, AppState, Error};

use crate::{
    db::{self, EventId, Game, GameId},
    httpapi::{EventGameListResponse, GameResponse, GameUpdateRequest}
};

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
    let game_route = RouteMap::Game.prefixed(nested_at.as_str());
    let game = retrieve(&db, &game_route, game_id, user_id.clone()).await?;

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

    Ok(Json(GameResponse::from_query(&game_route, game)?))
}

async fn retrieve(
    db: &Pool<Postgres>,
    game_route: &routing::Entry,
    game_id: GameId,
    user_id: String,
) -> Result<GameResponse, Error> {
    let maybe_game = Game::get_by_id_and_user(db, game_id, user_id).await?;

    match maybe_game {
        Some(game) => {
            GameResponse::from_query(game_route, game)
                .map_err(Error::from)
        },
        None => Err((StatusCode::NOT_FOUND, "not found").into())
    }
}
