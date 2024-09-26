use axum::{debug_handler, extract::{self, Path, State}, response::IntoResponse};
use semweb_api::condreq;
use sqlx::{Pool, Postgres};

use crate::{db::{EventId, User}, httpapi::{EventUserListResponse, ProfileResponse}, AppState, Error};

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
pub(crate) async fn get_scoped_list(
    State(db): State<Pool<Postgres>>,
    if_none_match: condreq::CondRetreiveHeader,
    nested_at: extract::NestedPath,
    Path(event_id): extract::Path<EventId>,
) -> Result<impl IntoResponse, Error> {
    let users = User::get_all_by_event_id(&db, event_id).await?;
    let resp = EventUserListResponse::from_query(nested_at.as_str(), event_id, users)?;
    if_none_match.respond(resp).map_err(Error::from)
}
