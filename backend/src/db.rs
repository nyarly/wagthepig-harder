use core::fmt;
use chrono::NaiveDateTime;
use futures::TryFuture;
use sqlx::{Executor, Postgres};

use zeroize::{Zeroize, ZeroizeOnDrop};

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

#[derive(sqlx::FromRow, Default, Debug)]
#[allow(dead_code)] // Have to match DB
pub(crate) struct User {
    pub id: i64,
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

impl User {
    pub fn by_email<'a>(db: impl Executor<'a, Database = Postgres> + 'a, email: String) -> impl TryFuture<Ok = Self, Error = sqlx::Error> + 'a {
        sqlx::query_as!( Self, "select * from users where email = $1", email).fetch_one(db)
    }
}

#[derive(sqlx::FromRow, Default, Debug)]
#[allow(dead_code)] // Have to match DB
pub(crate) struct Event {
     pub id: i64,
     pub name: Option<String>,
     pub date: Option<NaiveDateTime>,
     pub r#where: Option<String>,
     pub created_at: NaiveDateTime,
     pub updated_at: NaiveDateTime,
     pub description: Option<String>,
}

impl Event {
    pub fn get_all<'a>(db: impl Executor<'a, Database = Postgres> + 'a) -> impl TryFuture<Ok = Vec<Self
    >, Error = sqlx::Error> + 'a {
        sqlx::query_as!(Self, "select * from events").fetch_all(db)
    }
}
