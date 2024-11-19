use axum::{debug_handler, extract::{self, Path, State}, response::IntoResponse, Json};
use chrono::{DateTime, NaiveDateTime, Utc};
use hyper::{header, StatusCode};
use semweb_api::{condreq, hypermedia::{op, ActionType, IriTemplate, ResourceFields}};
use serde::{Deserialize, Serialize};
use sqlx::{Pool, Postgres};

use crate::{
    db::{Event, EventId, NoId},
    routing::{EmptyLocate, EventLocate},
    AppState, Error, RouteMap
};


#[derive(Serialize,Clone)]
#[serde(rename_all="camelCase")]
pub(crate) struct EventListResponse {
    #[serde(flatten)]
    pub resource_fields: ResourceFields<EmptyLocate>,

    pub event_by_id: IriTemplate,
    pub events: Vec<EventResponse>,
}

impl EventListResponse {
    pub fn from_query(nested_at: &str, list: Vec<Event<EventId>>) -> Result<Self, semweb_api::Error> {
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
    pub(crate) fn from_query(nested_at: &str, value: Event<EventId>) -> Result<Self, semweb_api::Error> {
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
pub(crate) struct EventUpdateRequest {
    pub name: Option<String>,
    pub time: Option<DateTime<Utc>>,
    pub location: Option<String>,
    pub description: Option<String>
}

#[test]
fn deserialize_event_update_request() {
    let _eur: EventUpdateRequest = serde_json::from_str(r#"{"name": "Testy", "time": "1970-01-01T00:00:00.000Z", "location": "Somewhere"}"#).expect("to deserialize");
}

impl EventUpdateRequest {
    pub(crate) fn db_param(&self) -> Event<NoId> {
        Event {
            name: self.name.clone(),
            date: self.time.map(|t| t.naive_utc()),
            r#where: self.location.clone(),
            description: self.description.clone(),
            ..Event::default()
        }
    }
}

#[debug_handler(state = AppState)]
pub(crate) async fn create_new(
    State(db): State<Pool<Postgres>>,
    nested_at: extract::NestedPath,
    Json(body): extract::Json<EventUpdateRequest>
) -> Result<impl IntoResponse, Error> {
    let new_id = body.db_param()
        .add_new(&db).await?;

    let location_uri = RouteMap::Event.prefixed(nested_at.as_str())
        .fill( EventLocate{ event_id: new_id })?;

    Ok((StatusCode::CREATED, [(header::LOCATION, location_uri.to_string())]))
}

#[debug_handler(state = AppState)]
pub(crate) async fn get_list(
    State(db): State<Pool<Postgres>>,
    if_none_match: condreq::CondRetreiveHeader,
    nested_at: extract::NestedPath
) -> Result<impl IntoResponse, Error> {
    let events = Event::get_all(&db).await?;
    let resp = EventListResponse::from_query(nested_at.as_str(), events)?;
    if_none_match.respond(resp).map_err(Error::from)
}

#[debug_handler(state = AppState)]
pub(crate) async fn get(
    State(db): State<Pool<Postgres>>,
    if_none_match: condreq::CondRetreiveHeader,
    nested_at: extract::NestedPath,
    Path(event_id): extract::Path<EventId>,
) -> Result<impl IntoResponse, Error> {
    let event_response = retrieve(&db, &nested_at, event_id).await?;
    if_none_match.respond(event_response).map_err(Error::from)
}

#[debug_handler(state = AppState)]
pub(crate) async fn update(
    State(db): State<Pool<Postgres>>,
    if_match: condreq::CondUpdateHeader,
    nested_at: extract::NestedPath,
    Path(event_id): extract::Path<EventId>,
    Json(body): extract::Json<EventUpdateRequest>
) -> Result<impl IntoResponse, Error> {
    let event = retrieve(&db, &nested_at, event_id).await?;

    if_match.guard_update(event)?;

    let event = body.db_param()
        .with_id(event_id)
        .update(&db).await?;

    Ok(Json(EventResponse::from_query(nested_at.as_str(), event)?))
}

async fn retrieve(
    db: &Pool<Postgres>,
    nested_at: &extract::NestedPath,
    event_id: EventId
) -> Result<EventResponse, Error> {
    let maybe_event = Event::get_by_id(db, event_id).await?;

    match maybe_event {
        Some(event) => {
            EventResponse::from_query(nested_at.as_str(), event)
                .map_err(|e| e.into())
        },
        None => Err((StatusCode::NOT_FOUND, "not found").into())
    }
}
