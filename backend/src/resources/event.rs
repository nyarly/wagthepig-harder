use axum::{debug_handler, extract::{self, Path, State}, response::IntoResponse, Json};
use hyper::{header, StatusCode};
use semweb_api::{condreq, routing::route_config};
use sqlx::{Pool, Postgres};

use crate::{AppState, Error};
use crate::httpapi::RouteMap;

use crate::{
    db::{Event, EventId},
    httpapi::{EventListResponse, EventLocate, EventResponse, EventUpdateRequest}
};


#[debug_handler(state = AppState)]
pub(crate) async fn get_event_list(
    State(db): State<Pool<Postgres>>,
    if_none_match: condreq::CondRetreiveHeader,
    nested_at: extract::NestedPath
) -> Result<impl IntoResponse, Error> {
    let events = Event::get_all(&db).await?;
    let resp = EventListResponse::from_query(nested_at.as_str(), events)?;
    if_none_match.respond(resp).map_err(Error::from)
}

#[debug_handler(state = AppState)]
pub(crate) async fn get_event(
    State(db): State<Pool<Postgres>>,
    if_none_match: condreq::CondRetreiveHeader,
    nested_at: extract::NestedPath,
    Path(event_id): extract::Path<EventId>,
) -> Result<impl IntoResponse, Error> {
    let event_response = retrieve_event(&db, nested_at, event_id).await?;
    if_none_match.respond(event_response).map_err(Error::from)
}

#[debug_handler(state = AppState)]
pub(crate) async fn update_event(
    State(db): State<Pool<Postgres>>,
    if_match: condreq::CondUpdateHeader,
    nested_at: extract::NestedPath,
    Path(event_id): extract::Path<EventId>,
    Json(body): extract::Json<EventUpdateRequest>
) -> Result<impl IntoResponse, Error> {
    let event = retrieve_event(&db, nested_at.clone(), event_id).await?;

    if_match.guard_update(event)?;

    let event_route = route_config(RouteMap::Event).prefixed(nested_at.as_str());
    let event = body.db_param()
        .with_id(event_id)
        .update(&db).await?;

    Ok(Json(EventResponse::from_query(&event_route, event)?))
}

async fn retrieve_event(
    db: &Pool<Postgres>,
    nested_at: extract::NestedPath,
    event_id: EventId
) -> Result<EventResponse, Error> {
    let maybe_event = Event::get_by_id(db, event_id).await?;

    match maybe_event {
        Some(event) => {
            let event_tmpl = route_config(RouteMap::Event).prefixed(nested_at.as_str());
            EventResponse::from_query(&event_tmpl, event)
                .map_err(|e| e.into())
        },
        None => Err((StatusCode::NOT_FOUND, "not found").into())
    }
}

#[debug_handler(state = AppState)]
pub(crate) async fn create_new_event(
    State(db): State<Pool<Postgres>>,
    nested_at: extract::NestedPath,
    Json(body): extract::Json<EventUpdateRequest>
) -> Result<impl IntoResponse, Error> {
    let new_id = body.db_param()
        .add_new(&db).await?;

    let location_uri = route_config(RouteMap::Event)
        .prefixed(nested_at.as_str())
        .fill( EventLocate{ event_id: new_id })?;

    Ok((StatusCode::CREATED, [(header::LOCATION, location_uri.to_string())]))
}
