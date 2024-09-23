-- We use this to create the DB because sqlx database setup can't (?) create an app user?
create user wagthepig;
create database wagthepig with owner wagthepig;
