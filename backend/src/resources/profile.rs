use axum::{debug_handler, extract::{self, Path, State}, response::IntoResponse};
use semweb_api::condreq;
use sqlx::{Pool, Postgres};

use crate::{db, httpapi, AppState, Error};

#[debug_handler(state = AppState)]
pub(crate) async fn get_profile(
    State(db): State<Pool<Postgres>>,
    if_none_match: condreq::CondRetreiveHeader,
    nested_at: extract::NestedPath,
    Path(user_id): Path<String>
) -> Result<impl IntoResponse, Error> {
    let profile = db::User::by_email(&db, user_id).await?;
    if_none_match.respond(httpapi::UserResponse::from_query(nested_at.as_str(), profile)?).map_err(Error::from)
}
