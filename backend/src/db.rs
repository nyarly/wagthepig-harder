use core::fmt;
use std::{convert::Infallible, future::Future};
use axum::response::IntoResponse;
use chrono::NaiveDateTime;
use futures::TryFutureExt as _;
use sqlx::{Executor, Postgres};
use serde::{Serialize, Deserialize};

use zeroize::{Zeroize, ZeroizeOnDrop};


pub trait PrimaryKey: Copy {
    type Id;

    fn id(self) -> Self::Id;
}

impl<T: Into<i64> + Copy> PrimaryKey for T {
    type Id = i64;

    fn id(self) -> Self::Id {
        self.into()
    }
}

#[derive(PartialEq, Eq, Clone, Copy, Default, Debug)]
pub struct NoId;

impl From<NoId> for Infallible{
    fn from(_val: NoId) -> Self {
        unreachable!("it's not an id")
    }
}

macro_rules! id_type {
    ($name:ident($wraps:ident)) => {
        #[derive(PartialEq, Eq, Hash, Debug, Clone, Copy, sqlx::Type, Deserialize, Serialize)]
        #[sqlx(transparent)]
        #[serde(transparent)]
        pub struct $name($wraps);

        impl From<$wraps> for $name {
            fn from(n: $wraps) -> Self {
                Self(n)
            }
        }

        impl From<$name> for $wraps {
            fn from(val: $name) -> Self {
                val.0
            }
        }

        impl ::std::fmt::Display for $name {
            fn fmt(&self, f: &mut ::std::fmt::Formatter<'_>) -> Result<(), ::std::fmt::Error> {
                write!(f, "{}", self.0)
            }
        }
    };
}

#[derive(thiserror::Error, Debug)]
pub enum Error {
    #[error("sqlx: ${0:?}")]
    Sqlx(#[from] sqlx::Error)
}

impl IntoResponse for Error {
    fn into_response(self) -> axum::response::Response {
        use axum::http::StatusCode;

        (match self {
            Error::Sqlx(err) => match err {
            sqlx::Error::TypeNotFound { .. } |
            sqlx::Error::ColumnNotFound(_) => StatusCode::INTERNAL_SERVER_ERROR,

            sqlx::Error::Configuration(_) |
            sqlx::Error::Migrate(_) |
            sqlx::Error::Database(_) |
            sqlx::Error::Tls(_) |
            sqlx::Error::AnyDriverError(_) => StatusCode::BAD_GATEWAY,

            sqlx::Error::Io(_) |
            sqlx::Error::Protocol(_) |
            sqlx::Error::PoolTimedOut |
            sqlx::Error::PoolClosed |
            sqlx::Error::WorkerCrashed => StatusCode::GATEWAY_TIMEOUT,

            sqlx::Error::RowNotFound => StatusCode::NOT_FOUND,

            sqlx::Error::ColumnIndexOutOfBounds { .. } |
            sqlx::Error::ColumnDecode { .. } |
            sqlx::Error::Encode(_) |
            sqlx::Error::Decode(_) => StatusCode::BAD_REQUEST,

            _ => StatusCode::INTERNAL_SERVER_ERROR,
            }
        }).into_response()
    }
}



#[derive(Zeroize, ZeroizeOnDrop, Default)]
pub(crate) struct Password(String);

impl From<String> for Password {
    fn from(value: String) -> Self {
        Self(value)
    }
}

impl AsRef<String> for Password {
    fn as_ref(&self) -> &String {
        &self.0
    }
}

impl fmt::Debug for Password {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_tuple("Password")
            .field(&"[redacted]")
            .finish()
    }
}




id_type!(UserId(i64));

#[derive(sqlx::FromRow, Default, Debug)]
#[allow(dead_code)] // Have to match DB
pub(crate) struct User<T> {
    pub id: T,
    pub name: Option<String>,
    pub bgg_username: Option<String>,
    pub email: String,
    pub encrypted_password: Password,
    pub updated_at: NaiveDateTime,
    pub created_at: NaiveDateTime,
    pub remember_created_at: Option<NaiveDateTime>,
    pub reset_password_sent_at: Option<NaiveDateTime>,
    pub reset_password_token: Option<String>
}

impl User<UserId> {
    pub fn by_email<'a>(db: impl Executor<'a, Database = Postgres> + 'a, email: String)
    -> impl Future<Output = Result<Self, Error>> + 'a {
        sqlx::query_as!(
            Self,
            "select * from users where email = $1",
            email)
            .fetch_one(db)
            .map_err(Error::from)
    }
}

id_type!(EventId(i64));

#[derive(sqlx::FromRow, Default, Debug)]
#[allow(dead_code)] // Have to match DB
pub(crate) struct Event<T> {
    pub id: T,
    pub name: Option<String>,
    pub date: Option<NaiveDateTime>,
    pub r#where: Option<String>,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
    pub description: Option<String>,
}

impl<F> Event<F> {
    pub fn with_id<T: PrimaryKey>(&self, id: T) -> Event<T> {
        Event::<T>{
            id,
            name: self.name.clone(),
            date: self.date,
            r#where: self.r#where.clone(),
            created_at: self.created_at,
            updated_at: self.updated_at,
            description: self.description.clone(),
        }
    }
}

impl Event<NoId> {
    pub fn add_new<'a>(&self, db: impl Executor<'a, Database = Postgres> + 'a)
    -> impl Future<Output = Result<EventId, Error>> + 'a {
        sqlx::query_scalar!(
            r#"insert into events ("name", "date", "where", "description") values ($1, $2, $3, $4) returning id"#,
            self.name, self.date, self.r#where, self.description)
            .fetch_one(db)
            .map_ok(|n| n.into())
            .map_err(Error::from)
    }

}

impl Event<EventId> {
    pub fn get_all<'a>(db: impl Executor<'a, Database = Postgres> + 'a)
    -> impl Future<Output = Result<Vec<Self>, Error>> + 'a {
        sqlx::query_as!(
            Self,
            "select * from events")
            .fetch_all(db)
            .map_err(Error::from)
    }

    pub fn get_by_id<'a>(db: impl Executor<'a, Database = Postgres> + 'a, id: EventId)
    -> impl Future<Output = Result<Option<Self>, Error>> + 'a {
        sqlx::query_as!(
            Self,
            "select * from events where id = $1",
            id.id())
            .fetch_optional(db)
            .map_err(Error::from)
    }

    pub fn update<'a>(&self, db: impl Executor<'a, Database = Postgres> + 'a)
    -> impl Future<Output = Result<Self, Error>> + 'a {
        sqlx::query_as!(
            Self,
            r#"update events set ("name", "date", "where", "description") = ($1, $2, $3, $4) where id = $5 returning *"#,
            self.name, self.date, self.r#where, self.description, self.id.id())
            .fetch_one(db)
            .map_err(Error::from)
    }

}

id_type!(GameId(i64));

#[derive(sqlx::FromRow, Debug)]
#[allow(dead_code)] // Have to match DB
pub(crate) struct Game<T, U> {
    pub id: T,
    pub event_id: U,
    pub suggestor_id: UserId,

    pub name: Option<String>,
    pub bgg_id: Option<String>,
    pub bgg_link: Option<String>,
    pub min_players: Option<i32>,
    pub max_players: Option<i32>,
    pub duration_secs: Option<i32>,

    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
    pub pitch: Option<String>,
    pub interested: Option<bool>,
    pub can_teach: Option<bool>,
    pub notes: Option<String>,
}

impl<F, E: Copy> Game<F, E> {
    pub fn with_id<T: PrimaryKey>(&self, id: T) -> Game<T, E> {
        Game::<T, E>{
            id,
            event_id: self.event_id,
            suggestor_id: self.suggestor_id,
            name: self.name.clone(),
            min_players: self.min_players,
            max_players: self.max_players,
            bgg_link: self.bgg_link.clone(),
            duration_secs: self.duration_secs,
            created_at: self.created_at,
            updated_at: self.updated_at,
            bgg_id: self.bgg_id.clone(),
            pitch: self.pitch.clone(),
            interested: self.interested,
            can_teach: self.can_teach,
            notes: self.notes.clone(),
        }
    }
}

impl<G: Copy, F> Game<G, F> {
    pub fn with_event_id<T: PrimaryKey>(&self, event_id: T) -> Game<G, T> {
        Game::<G, T>{
            event_id,
            id: self.id,
            suggestor_id: self.suggestor_id,
            name: self.name.clone(),
            min_players: self.min_players,
            max_players: self.max_players,
            bgg_link: self.bgg_link.clone(),
            duration_secs: self.duration_secs,
            created_at: self.created_at,
            updated_at: self.updated_at,
            bgg_id: self.bgg_id.clone(),
            pitch: self.pitch.clone(),
            interested: self.interested,
            can_teach: self.can_teach,
            notes: self.notes.clone(),
        }
    }
}

impl Game<NoId, EventId> {
    pub fn add_new<'a>(&self, db: impl Executor<'a, Database = Postgres> + 'a, user_id: String)
    -> impl Future<Output = Result<GameId, Error>> + 'a {
        // insert a game that reference the event and the user (means a subselect)
        // insert an interest for the game, event and user
        sqlx::query_scalar!(
            r#"insert into games
                ("name", "min_players", "max_players", "bgg_link",
                "duration_secs", "event_id",  "bgg_id", "pitch", "suggestor_id")
                values ($1, $2, $3, $4,
                $5, $6, $7, $8, (select id from users where email = $9))
                returning id"#,
            self.name, self.min_players, self.max_players, self.bgg_link,
            self.duration_secs, self.event_id.id(), self.bgg_id, self.pitch, user_id)
            .fetch_one(db)
            .map_ok(|n| n.into())
            .map_err(Error::from)
    }
}

/*
impl Game<GameId, NoId> {
    pub fn update<'a>(&self, db: impl Executor<'a, Database = Postgres> + 'a, game_id: GameId)
    -> impl Future<Output = Result<Game<GameId, EventId>, Error>> + 'a {
        sqlx::query_as!(
            Self,
            r#"update games
            set ( "name", "bgg_id", "bgg_link", "min_players", "max_players", "duration_secs")
                = ( $1, $2, $3, $4, $5, $6 )
            where id = $7
                returning *,
                $8 as pitch, $9 as interested, $10 as can_teach, $11 as notes"#,
            self.name, self.bgg_id, self.bgg_link, self.min_players, self.max_players, self.duration_secs,
                self.id.id(),
            self.pitch, self.interested, self.can_teach, self.notes)
            .fetch_one(db)
            .map_err(Error::from)
    }
}
*/

impl Game<GameId, EventId> {
    pub fn get_by_id_and_user<'a>(db: impl Executor<'a, Database = Postgres> + 'a, game_id: GameId, user_id: String)
    -> impl Future<Output = Result<Option<Self>, Error>> + 'a {
        sqlx::query_as!(
            Self,
            r#"select games.*,
                (interests.id is not null) as interested,
                (coalesce (interests.can_teach, false)) as can_teach,
                interests.notes
            from games
                left join interests on games.id = interests.game_id
                join users on interests.user_id = users.id and email = $2
            where games.id = $1"#,
            game_id.id(), user_id)
            .fetch_optional(db)
            .map_err(Error::from)
    }

    pub fn get_all_for_event_and_user<'a>(db: impl Executor<'a, Database = Postgres> + 'a, event_id: EventId, email: String)
    -> impl Future<Output = Result<Vec<Self>, Error>> + 'a {
        sqlx::query_as!(
            Self,
            r#"select games.*,
                (interests.id is not null) as interested,
                (coalesce (interests.can_teach, false)) as can_teach,
                interests.notes
            from games
                left join interests on games.id = interests.game_id
                join users on interests.user_id = users.id and email = $2
            where event_id = $1"#,
            event_id.id(), email)
            .fetch_all(db)
            .map_err(Error::from)
    }

    pub fn update_interests<'a>(&self, db: impl Executor<'a, Database = Postgres> + 'a, user_id: String)
    -> impl Future<Output = Result<(), Error>> + 'a {
        (if Some(true) == self.interested {
            sqlx::query!(
            r#"insert into interests
                    ("game_id", "notes", "can_teach", "user_id")
                    values ($1, $2, $3, (select id from users where email = $4))
                on conflict (game_id, user_id) do update set
                    ("notes", "can_teach") =
                    ($2, $3)"#,
                self.id.id(), self.notes, self.can_teach, user_id)
        } else {
            sqlx::query!(
                r#"delete from interests where game_id = $1"#,
                self.id.id())
        })
            .execute(db)
            .map_ok(|_| ())
            .map_err(Error::from)
    }

}
