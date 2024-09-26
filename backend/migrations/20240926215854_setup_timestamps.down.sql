drop trigger if exists update_timestamp on events;
drop trigger if exists update_timestamp on interests;
drop trigger if exists update_timestamp on games;
drop trigger if exists update_timestamp on users;

drop function update_timestamp_column;

alter table public.events alter column created_at drop default;
alter table public.events alter column updated_at drop default;
alter table public.interests alter column created_at drop default;
alter table public.interests alter column updated_at drop default;
alter table public.users alter column created_at drop default;
alter table public.users alter column updated_at drop default;
