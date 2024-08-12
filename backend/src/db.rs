use core::fmt;
use chrono::NaiveDateTime;
use futures::TryFuture;
use sqlx::{Executor, Postgres};

#[derive(sqlx::FromRow, Default)]
#[allow(dead_code)] // Have to match DB
pub(crate) struct User {
    pub id: i64,
    pub name: Option<String>,
    pub bgg_username: Option<String>,
    pub email: String,
    pub encrypted_password: String,
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

impl fmt::Debug for User {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("User")
            .field("email", &self.email)
            .field("password", &"[redacted]")
            .finish()
    }
}
