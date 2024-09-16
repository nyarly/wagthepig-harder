sqlx migrations seem pretty immature;
notably, there can only be one _sql_migrations table,
which precludes multi-tenancy in the DB.

Will want to find a different solution in the meantime.
