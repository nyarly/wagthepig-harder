use axum::{response::IntoResponse, Json};
use semweb_api::{hypermedia::{op, ActionType}, routing::{Entry, RouteTemplate}};
use semweb_api_derives::{Context, Extract, Listable};
use serde::Serialize;
use serde_json::json;

use crate::db::{EventId, GameId, UserId};

#[derive(Copy, Clone)]
pub(crate) enum RouteMap {
    Root,
    Authenticate,
    PasswordReset,
    Profile,
    User,
    Events,
    Event,
    EventUsers,
    EventGames,
    Game,
    GameUsers,
    Recommend
}

impl RouteTemplate for RouteMap {
    fn route_template(&self) -> String {
        use RouteMap::*;
        match self {
            Root          => "/",
            Authenticate  => "/authenticate/{user_id}",                // by login
            PasswordReset => "/reset_password/{user_id}",              // by login
            Profile       => "/profile/{user_id}",                     // by login
            User          => "/profile/{user_id}",                     // by ID
            Events        => "/events",
            Event         => "/event/{event_id}",
            EventUsers    => "/event_users/{event_id}",
            EventGames    => "/event_games/{event_id}/user/{user_id}",
            Game          => "/games/{game_id}/user/{user_id}",
            GameUsers     => "/game_users/{game_id}",
            Recommend     => "/recommend/{event_id}"
        }.to_string()
    }
}

impl RouteMap {
    pub(crate) fn prefixed(self, at: &str) -> Entry {
        <Self as RouteTemplate>::prefixed(self, at)
    }
}

#[derive(Default, Serialize, Copy, Clone, Listable, Context, Extract)]
pub(crate) struct EmptyLocate {}

#[derive(Default, Serialize, Clone, Listable, Context, Extract)]
pub(crate) struct AuthenticateLocate {
    pub user_id: String
}

#[derive(Default, Serialize, Clone, Listable, Context, Extract)]
pub(crate) struct PasswordResetLocate {
    pub user_id: String
}

#[derive(Default, Serialize, Clone, Listable, Context, Extract)]
pub(crate) struct ProfileLocate {
    pub user_id: String
}

#[derive(Serialize, Clone, Listable, Context, Extract)]
pub(crate) struct UserLocate {
    pub user_id: UserId
}

#[derive(Serialize, Copy, Clone, Listable, Context, Extract)]
pub(crate) struct EventLocate {
    pub event_id: EventId
}

#[derive(Serialize, Clone, Listable, Context, Extract)]
pub(crate) struct EventUsersLocate {
    pub event_id: EventId,
}

#[derive(Serialize, Clone, Listable, Context, Extract)]
pub(crate) struct EventGamesLocate {
    pub event_id: EventId,
    pub user_id: String
}

#[derive(Serialize, Copy, Clone, Listable, Context, Extract)]
pub(crate) struct GameLocate {
    pub game_id: GameId
}

#[derive(Serialize, Copy, Clone, Listable, Context, Extract)]
pub(crate) struct GameUsersLocate {
    pub game_id: GameId
}

#[derive(Serialize, Copy, Clone, Listable, Context, Extract)]
pub(crate) struct RecommendLocate {
    pub event_id: EventId
}

pub(crate) fn api_doc(nested_at: &str) -> impl IntoResponse {
    use RouteMap::*;
    use ActionType::*;

    let entry = |rm: RouteMap, ops| {
        let prefixed = rm.prefixed(nested_at);
        let url_attr = if prefixed.hydra_type() == "Link" {
            "id"
        } else {
            "template"
        };
        let url_template = prefixed.template().expect("a legit URITemplate");
        json!({
            "type": prefixed.hydra_type(),
            url_attr: url_template,
            "operation": ops
        })
    };

    Json(json!({
        "root": entry(Root, vec![ op(View) ]),
        "resetPassword": entry(PasswordReset, vec![op(Create)]),
        "authenticate": entry(Authenticate, vec![op(Login), op(Update), op(Logout)]),
        "profile": entry(Profile, vec![op(Create), op(Find)]),
        "events": entry(Events, vec![ op(View), op(Add) ]),
        "event": entry(Event, vec![ op(Find), op(Update) ]),
    }))
}
