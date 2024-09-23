use axum::{debug_handler, extract::{self, Path, State}, response::IntoResponse, Json};
use semweb_api::condreq;
use sqlx::{Pool, Postgres};

use crate::{db::{self, EventId}, httpapi::{self}, AppState, Error};

#[debug_handler(state = AppState)]
pub(crate) async fn make_recommendation(
    State(db): State<Pool<Postgres>>,
    if_none_match: condreq::CondRetreiveHeader,
    nested_at: extract::NestedPath,
    Path(event_id): extract::Path<EventId>,
    Json(body): extract::Json<httpapi::RecommendRequest>
) -> Result<impl IntoResponse, Error> {
    let recommend = db::Game::get_recommendation(&db, event_id, body.player_ids(nested_at.as_str())?, body.extra_players).await?;

    let resp = httpapi::RecommendListResponse::from_query(nested_at.as_str(), event_id, recommend)?;
    if_none_match.respond(resp).map_err(Error::from)
}
