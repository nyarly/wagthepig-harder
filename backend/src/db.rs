use core::fmt;
use std::{convert::Infallible, future::Future, time::SystemTime};
use axum::response::IntoResponse;
use chrono::{NaiveDateTime, TimeZone as _, Utc};
use futures::TryFutureExt as _;
use sqlx::{Executor, Postgres};
use serde::{Serialize, Deserialize};
use tracing::debug;

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

/// Use as a generic type to skip fields that might sometimes be included
#[derive(sqlx::FromRow, Debug, Default, Clone, Copy)]
#[allow(dead_code)] // Have to match DB
pub(crate) struct Omit{}

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
        debug!("DB Error: {:?}", self);
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

    // XXX these fields are slated for removal
    pub remember_created_at: Option<NaiveDateTime>,
    pub reset_password_sent_at: Option<NaiveDateTime>,
    pub reset_password_token: Option<String>
}

impl User<UserId> {
    pub fn create<'a>(db: impl Executor<'a, Database = Postgres> + 'a, email: &str, name: &str, bgg: &str)
    -> impl Future<Output = Result<Self, Error>> + 'a {
        sqlx::query_as!(
            Self,
            r#"insert into users
            ("email", "name", "bgg_username", "encrypted_password")
            values ($1, $2, $3, 'empty password cannot log in') returning *"#,
            email, name, bgg)
            .fetch_one(db)
            .map_err(Error::from)
    }

    pub fn by_email<'a>(db: impl Executor<'a, Database = Postgres> + 'a, email: String)
    -> impl Future<Output = Result<Self, Error>> + 'a {
        sqlx::query_as!(
            Self,
            "select * from users where email = $1",
            email)
            .fetch_one(db)
            .map_err(Error::from)
    }

    pub fn get_all_by_event_id<'a>(db: impl Executor<'a, Database = Postgres> + 'a, event_id: EventId)
    -> impl Future<Output = Result<Vec<Self>, Error>> + 'a {
        sqlx::query_as!(
            Self,
            r#"select distinct users.*
            from users
            join interests on interests.user_id = users.id
            join games on interests.game_id = games.id
            where games.event_id = $1"#,
            event_id.id())
            .fetch_all(db)
            .map_err(Error::from)
    }

    pub fn get_all_by_game_id<'a>(db: impl Executor<'a, Database = Postgres> + 'a, game_id: GameId)
    -> impl Future<Output = Result<Vec<Self>, Error>> + 'a {
        sqlx::query_as!(
            Self,
            r#"select users.*
            from users
            join interests on interests.user_id = users.id
            join games on interests.game_id = games.id
            where interests.game_id = $1"#,
            game_id.id())
            .fetch_all(db)
            .map_err(Error::from)
    }

    pub fn update_password<'a>(&self, db: impl Executor<'a, Database = Postgres> + 'a, hashed: String)
    -> impl Future<Output = Result<(), Error>> + 'a {
        sqlx::query!(
        r#"update users set "encrypted_password" = $1 where email = $2"#,
            hashed, self.email)
            .execute(db)
            .map_ok(|_| ())
            .map_err(Error::from)
    }
}

id_type!(RevocationId(i64));

#[derive(sqlx::FromRow, Default, Debug)]
#[allow(dead_code)] // Have to match DB
pub(crate) struct Revocation<T> {
    pub id: T,
    pub data: String,
    pub expires: NaiveDateTime,
    pub revoked: Option<NaiveDateTime>,
    pub username: String,
    pub clienthint: Option<String>
}

// XXX Can we just use chrono?
fn system_to_naive(sys: SystemTime) -> NaiveDateTime {
    let dur = sys.duration_since(std::time::UNIX_EPOCH).expect("1970 to be in the past");
    let (sec, nsec) = (dur.as_secs() as i64, dur.subsec_nanos());
    Utc.timestamp_opt(sec,nsec).unwrap().naive_utc()
}

impl Revocation<NoId> {
    pub fn add_batch<'a>(db: impl Executor<'a, Database = Postgres> + 'a, rids: Vec<String>, username: String, expiry: SystemTime)
    -> impl Future<Output = Result<Vec<RevocationId>, Error>> + 'a {
        let expiry = system_to_naive(expiry);
        sqlx::query!(
            r#"insert into revocations
                ("expires", "username", "data")
            select $1 as expires, $2 as username, unnest($3::text[])
            returning id
            "#, expiry, username, &rids)
            .fetch_all(db)
            .map_ok(|maps| maps.into_iter().map(|rec| rec.id.into()).collect())
            .map_err(Error::from)
    }

    pub fn cleanup<'a>(db: impl Executor<'a, Database = Postgres> + 'a, system_expired: SystemTime)
    -> impl Future<Output = Result<(), Error>> + 'a {
        let expired = system_to_naive(system_expired);
        sqlx::query!(
            r#"delete from revocations where $1 > expires"#,
            expired)
            .execute(db)
            .map_ok(|_| ())
            .map_err(Error::from)
    }
}

impl Revocation<RevocationId> {
    pub fn revoke<'a>(db: impl Executor<'a, Database = Postgres> + 'a, rids: Vec<String>, now: NaiveDateTime)
    -> impl Future<Output = Result<Vec<Self>, Error>> + 'a {
        sqlx::query_as!( Self,
            r#"update revocations set "revoked" =  $2  where data = any($1) returning *"#,
            &rids, now)
            .fetch_all(db)
            .map_err(Error::from)
    }

    pub fn revoke_for_username<'a>(db: impl Executor<'a, Database = Postgres> + 'a, username: String, now: NaiveDateTime)
    -> impl Future<Output = Result<Vec<Self>, Error>> + 'a {
        sqlx::query_as!( Self,
            r#"update revocations set "revoked" = $2  where username = $1 returning *"#,
            username, now)
            .fetch_all(db)
            .map_err(Error::from)
    }

    pub fn get_revoked<'a>(db: impl Executor<'a, Database = Postgres> + 'a, now: NaiveDateTime)
    -> impl Future<Output = Result<Vec<Self>, Error>> + 'a {
        sqlx::query_as!( Self,
            r#" select * from revocations where revoked is not null and $1 < expires"#,
            now)
            .fetch_all(db)
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
pub(crate) struct Game<PK, FE, FU, I> {
    pub id: PK,
    pub event_id: FE,
    pub suggestor_id: FU,

    #[sqlx(flatten)]
    pub data: GameData,

    #[sqlx(flatten)]
    pub extra: I
}


#[derive(sqlx::FromRow, Debug, Default, Clone)]
#[allow(dead_code)] // Have to match DB
pub(crate) struct GameData {
    pub name: Option<String>,
    pub bgg_id: Option<String>,
    pub bgg_link: Option<String>,
    pub min_players: Option<i32>,
    pub max_players: Option<i32>,
    pub duration_secs: Option<i32>,
    pub pitch: Option<String>,

    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
}

#[derive(sqlx::FromRow, Debug, Default, Clone)]
#[allow(dead_code)] // Have to match DB
pub(crate) struct InterestData {
    pub interested: Option<bool>,
    pub can_teach: Option<bool>,
    pub notes: Option<String>,
}

#[derive(sqlx::FromRow, Debug, Default, Clone)]
#[allow(dead_code)] // Have to match DB
pub(crate) struct RecommendData {
    pub interest_level: i64,
    pub teachers: i64
}

#[derive(sqlx::FromRow, Debug, Default, Clone)]
#[allow(dead_code)] // Have to match DB
pub(crate) struct PlayerData {
    #[sqlx(flatten)]
    pub recco: RecommendData,
    #[sqlx(flatten)]
    pub interest: InterestData,
}


impl Default for Game<NoId, NoId, NoId, Omit> {
    fn default() -> Self {
        Self {
            id: Default::default(),
            event_id: Default::default(),
            suggestor_id: Default::default(),
            data: Default::default(),
            extra: Default::default()
        }
    }
}

impl Default for Game<NoId, NoId, NoId, InterestData> {
    fn default() -> Self {
        Self {
            id: Default::default(),
            event_id: Default::default(),
            suggestor_id: Default::default(),
            data: Default::default(),
            extra: Default::default()
        }
    }
}

impl Default for Game<NoId, NoId, NoId, RecommendData> {
    fn default() -> Self {
        Self {
            id: Default::default(),
            event_id: Default::default(),
            suggestor_id: Default::default(),
            data: Default::default(),
            extra: Default::default()
        }
    }
}

impl<From, E: Copy, U: Copy, I: Clone> Game<From, E, U, I> {
    pub fn with_id<To: PrimaryKey>(self, id: To) -> Game<To, E, U, I> {
        Game::<To, E, U, I>{
            id,
            event_id: self.event_id,
            suggestor_id: self.suggestor_id,
            data: self.data,
            extra: self.extra
        }
    }
}

impl<G: Copy, From, U: Copy, I: Clone> Game<G, From, U, I> {
    pub fn with_event_id<To: PrimaryKey>(self, event_id: To) -> Game<G, To, U, I> {
        Game::<G, To, U, I>{
            event_id,
            id: self.id,
            suggestor_id: self.suggestor_id,
            data: self.data,
            extra: self.extra
        }
    }
}

impl<G: Copy, E: Copy, U: Copy, From> Game<G, E, U, From> {
    pub fn with_interest_data(self, interest: InterestData) -> Game<G, E, U, InterestData> {
        Game::<G,E,U,InterestData>{
            id: self.id,
            event_id: self.event_id,
            suggestor_id: self.suggestor_id,
            data: self.data,
            extra: interest
        }
    }
}

impl<U, I> Game<NoId, EventId, U, I> {
    pub fn add_new<'a>(&self, db: impl Executor<'a, Database = Postgres> + 'a, user_id: String)
    -> impl Future<Output = Result<GameId, Error>> + 'a {
        let data = &self.data;
        debug!("add_new with data: {:?}", data);

        sqlx::query_scalar!(
            r#"insert into games
                ("name", "min_players", "max_players", "bgg_link",
                "duration_secs", "bgg_id", "pitch", "event_id",  "suggestor_id")
                values ($1, $2, $3, $4,
                $5, $6, $7, $8, (select id from users where email = $9))
                returning id"#,
            data.name, data.min_players, data.max_players, data.bgg_link,
            data.duration_secs, data.bgg_id, data.pitch, self.event_id.id(), user_id)
            .fetch_one(db)
            .map_ok(|n| n.into())
            .map_err(Error::from)
    }
}

impl Game<GameId, NoId, NoId, Omit> {
    pub fn update<'a>(&self, db: impl Executor<'a, Database = Postgres> + 'a)
    -> impl Future<Output = Result<Game<GameId, EventId, UserId, Omit>, Error>> + 'a {
        let data = &self.data;
        sqlx::query_as(
            r#"update games
            set ( "name", "bgg_id", "bgg_link", "min_players", "max_players", "duration_secs", "pitch")
                = ( $1, $2, $3, $4, $5, $6, $7 )
            where id = $8
                returning *"#)
            .bind(data.name.clone())
            .bind(data.bgg_id.clone())
            .bind(data.bgg_link.clone())
            .bind(data.min_players)
            .bind(data.max_players)
            .bind(data.duration_secs)
            .bind(data.pitch.clone())
            .bind(self.id.id())
            .fetch_one(db)
            .map_err(Error::from)
    }
}

impl Game<GameId, EventId, UserId, RecommendData> {
    pub fn get_recommendation<'a>(db: impl Executor<'a, Database = Postgres> + 'a, event_id: EventId, user_ids: Vec<UserId>, extra_players: u8)
    -> impl Future<Output = Result<Vec<Self>, Error>> + 'a {
        let must_play = (user_ids.len() + (extra_players as usize)) as i32;
        let user_slice = user_ids.into_iter().map(|uid| uid.id()).collect::<Vec<_>>();
        debug!("get_recco data: event_id: {}, must_play: {}, users: {:?}", event_id.id(), must_play, user_slice);
        sqlx::query_as(r#"
            select
                games.*,
                count('games.id') as interest_level,
                count('games.id') FILTER (WHERE interests.can_teach is true) as teachers
            from
                games
                left join interests on games.id = interests.game_id
                join users on interests.user_id = users.id
            where
                coalesce(games.max_players, 9999) >= $1
                and event_id = $2
                and users.id = any($3)
            group by (games.id)
            order by interest_level desc, teachers desc
            "#)
            .bind(must_play)
            .bind(event_id.id())
            .bind(user_slice)
            .fetch_all(db)
            .map_err(Error::from)
    }
}

impl Game<GameId, EventId, UserId, InterestData> {
    pub fn get_by_id_and_user<'a>(db: impl Executor<'a, Database = Postgres> + 'a, game_id: GameId, user_id: String)
    -> impl Future<Output = Result<Option<Self>, Error>> + 'a {
        sqlx::query_as(
            r#"select games.*,
                (interests.id is not null) as interested,
                (coalesce (interests.can_teach, false)) as can_teach,
                interests.notes
            from
                games
                left join
                    (interests
                    join users on interests.user_id = users.id and email = $2)
                on games.id = interests.game_id
            where games.id = $1"#)
            .bind( game_id.id() )
            .bind( user_id )
            .fetch_optional(db)
            .map_err(Error::from)
    }
}

impl Game<GameId, EventId, UserId, PlayerData> {
    pub fn get_all_for_event_and_user<'a>(db: impl Executor<'a, Database = Postgres> + 'a, event_id: EventId, email: String)
    -> impl Future<Output = Result<Vec<Self>, Error>> + 'a {
        sqlx::query_as(
            r#"
            select games.*,
                count(games.id) as interest_level,
                count(games.id) FILTER (WHERE interests.can_teach is true) as teachers,
                (my_interest.id is not null) as interested,
                (coalesce (my_interest.can_teach, false)) as can_teach,
                my_interest.notes
            from
                games
                left join
                (interests as my_interest
                join users on my_interest.user_id = users.id and email = $2)
                on games.id = my_interest.game_id
                join interests on games.id = interests.game_id
            where event_id = $1
            group by (games.id, my_interest.id)
            "#)
            .bind(event_id.id())
            .bind(email)
            .fetch_all(db)
            .map_err(Error::from)
    }
}

impl<E, U> Game<GameId, E, U, InterestData> {
    pub fn update_interests<'a>(&self, db: impl Executor<'a, Database = Postgres> + 'a, user_id: String)
    -> impl Future<Output = Result<(), Error>> + 'a {
        let interest = &self.extra;
        (if Some(true) == interest.interested {
            sqlx::query!(
            r#"insert into interests
                    ("game_id", "notes", "can_teach", "user_id")
                    values ($1, $2, $3, (select id from users where email = $4))
                on conflict (game_id, user_id) do update set
                    ("notes", "can_teach") =
                    ($2, $3)"#,
                self.id.id(), interest.notes, interest.can_teach, user_id)
        } else {
            sqlx::query!(
                r#"delete from interests where game_id = $1"#,
                self.id.id())
            }).execute(db)
            .map_ok(|_| ())
            .map_err(Error::from)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    use sqlx::Pool;

    #[sqlx_pg_test_template::test(template = "wtp_empty_template")]
    async fn test_add_user(pool: Pool<Postgres>) {
        let testy = User::create(&pool, "test@mctesterson.net", "Testy McTesterson", "testy").await.unwrap();
        let also_testy = User::by_email(&pool, testy.email).await.unwrap();
        assert_eq!(testy.id, also_testy.id);
    }

    #[sqlx_pg_test_template::test(template = "wtp_empty_template")]
    async fn test_join_in_on_a_game(pool: Pool<Postgres>) {
        let one = User::create(&pool, "one@example.com", "User One", "one").await.unwrap();
        let two = User::create(&pool, "two@example.com", "User Two", "two").await.unwrap();
        let event_id = Event{
            id: NoId,
            name: Some("event".into()),
            date: None,
            r#where: Some("location".into()),
            description: Some("its great".into()),
            ..Event::default()
        }.add_new(&pool).await.unwrap();

        let default_game = Game::<NoId, NoId, NoId, Omit>::default();

        let game_one = Game {
            data: GameData{ name: Some("game_one".into()), ..GameData::default() },
            ..default_game
        }.with_event_id(event_id);
        let id_one = game_one.add_new(&pool, one.email.clone()).await.unwrap();
        let game_one = game_one.with_id(id_one).with_interest_data(InterestData {
            interested: Some(true),
            can_teach: Some(false),
            notes: None
        });
        game_one.update_interests(&pool, one.email.clone()).await.unwrap();

        let game_two = Game {
            data: GameData{ name: Some("game_two".into()), ..GameData::default() },
            ..default_game
        }.with_event_id(event_id);
        let id_two = game_two.add_new(&pool, two.email.clone()).await.unwrap();
        let mut game_two = game_two.with_id(id_two).with_interest_data(InterestData {
            interested: Some(true),
            can_teach: Some(false),
            notes: None
        });
        game_two.update_interests(&pool, two.email.clone()).await.unwrap();

        let games = Game::get_all_for_event_and_user(&pool, event_id, one.email.clone()).await.unwrap();
        assert_eq!(games.len(), 2, "User one should see 2 games, but saw {}", games.len());

        game_one.update_interests(&pool, two.email.clone()).await.unwrap();

        let games = Game::get_all_for_event_and_user(&pool, event_id, one.email.clone()).await.unwrap();
        assert_eq!(games.len(), 2, "User one should still see 2 games after two marks interest, saw {}", games.len());

        let found_one = games.iter().find(|g| g.id == id_one).unwrap();
        assert_eq!(found_one.extra.recco.interest_level, 2,
            "Game one should have an interest level of 2: was {}", found_one.extra.recco.interest_level);

        game_two.extra.interested = Some(false);
        game_two.update_interests(&pool, two.email.clone()).await.unwrap();

        let games = Game::get_all_for_event_and_user(&pool, event_id, two.email.clone()).await.unwrap();
        assert_eq!(dbg!(games).len(), 1, "With no interest, game two should have been removed");
    }
}
