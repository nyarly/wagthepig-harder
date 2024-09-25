-- Add up migration script here
CREATE TABLE public.revocations (
    id bigint generated always as identity,
    data text NOT NULL,
    expires timestamp without time zone NOT NULL,
    revoked timestamp without time zone,
    username text NOT NULL, -- not FK for now; no "service accounts" either
    clienthint text -- client could say "Chrome on Linux" or w/e
);
ALTER TABLE public.revocations OWNER TO wagthepig;
