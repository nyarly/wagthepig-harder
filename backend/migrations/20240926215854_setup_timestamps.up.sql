alter table public.events alter column created_at set default now();
alter table public.events alter column updated_at set default now();
alter table public.interests alter column created_at set default now();
alter table public.interests alter column updated_at set default now();
alter table public.users alter column created_at set default now();
alter table public.users alter column updated_at set default now();

create or replace function update_timestamp_column()
returns trigger as $$
begin
    new.updated_at = now();
    return new;
end;
$$ language 'plpgsql';

create trigger update_timestamp before update on users for each row execute procedure update_timestamp_column();
create trigger update_timestamp before update on events for each row execute procedure update_timestamp_column();
create trigger update_timestamp before update on interests for each row execute procedure update_timestamp_column();
create trigger update_timestamp before update on games for each row execute procedure update_timestamp_column();
