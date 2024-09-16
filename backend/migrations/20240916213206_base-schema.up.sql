-- PostgreSQL database dump
--

-- Dumped from database version 13.11
-- Dumped by pg_dump version 13.11

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: wagthepig
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


ALTER TABLE public.ar_internal_metadata OWNER TO wagthepig;

--
-- Name: events; Type: TABLE; Schema: public; Owner: wagthepig
--

CREATE TABLE public.events (
    id bigint NOT NULL,
    name text,
    date timestamp without time zone,
    "where" text,
    created_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    description text
);


ALTER TABLE public.events OWNER TO wagthepig;

--
-- Name: events_id_seq; Type: SEQUENCE; Schema: public; Owner: wagthepig
--

CREATE SEQUENCE public.events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.events_id_seq OWNER TO wagthepig;

--
-- Name: events_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: wagthepig
--

ALTER SEQUENCE public.events_id_seq OWNED BY public.events.id;


--
-- Name: games; Type: TABLE; Schema: public; Owner: wagthepig
--

CREATE TABLE public.games (
    id bigint NOT NULL,
    name text,
    min_players integer,
    max_players integer,
    bgg_link text,
    duration_secs integer,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    event_id bigint NOT NULL,
    suggestor_id bigint NOT NULL,
    bgg_id character varying,
    pitch text
);


ALTER TABLE public.games OWNER TO wagthepig;

--
-- Name: games_id_seq; Type: SEQUENCE; Schema: public; Owner: wagthepig
--

CREATE SEQUENCE public.games_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.games_id_seq OWNER TO wagthepig;

--
-- Name: games_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: wagthepig
--

ALTER SEQUENCE public.games_id_seq OWNED BY public.games.id;


--
-- Name: interests; Type: TABLE; Schema: public; Owner: wagthepig
--

CREATE TABLE public.interests (
    id bigint NOT NULL,
    notes text,
    created_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    game_id bigint NOT NULL,
    user_id bigint NOT NULL,
    can_teach boolean DEFAULT false
);


ALTER TABLE public.interests OWNER TO wagthepig;

--
-- Name: interests_id_seq; Type: SEQUENCE; Schema: public; Owner: wagthepig
--

CREATE SEQUENCE public.interests_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.interests_id_seq OWNER TO wagthepig;

--
-- Name: interests_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: wagthepig
--

ALTER SEQUENCE public.interests_id_seq OWNED BY public.interests.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: wagthepig
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


ALTER TABLE public.schema_migrations OWNER TO wagthepig;

--
-- Name: users; Type: TABLE; Schema: public; Owner: wagthepig
--

CREATE TABLE public.users (
    id bigint NOT NULL,
    email character varying DEFAULT ''::character varying NOT NULL,
    encrypted_password character varying DEFAULT ''::character varying NOT NULL,
    reset_password_token character varying,
    reset_password_sent_at timestamp without time zone,
    remember_created_at timestamp without time zone,
    created_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    name character varying,
    bgg_username character varying
);


ALTER TABLE public.users OWNER TO wagthepig;

--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: wagthepig
--

CREATE SEQUENCE public.users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.users_id_seq OWNER TO wagthepig;

--
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: wagthepig
--

ALTER SEQUENCE public.users_id_seq OWNED BY public.users.id;


--
-- Name: events id; Type: DEFAULT; Schema: public; Owner: wagthepig
--

ALTER TABLE ONLY public.events ALTER COLUMN id SET DEFAULT nextval('public.events_id_seq'::regclass);


--
-- Name: games id; Type: DEFAULT; Schema: public; Owner: wagthepig
--

ALTER TABLE ONLY public.games ALTER COLUMN id SET DEFAULT nextval('public.games_id_seq'::regclass);


--
-- Name: interests id; Type: DEFAULT; Schema: public; Owner: wagthepig
--

ALTER TABLE ONLY public.interests ALTER COLUMN id SET DEFAULT nextval('public.interests_id_seq'::regclass);


--
-- Name: users id; Type: DEFAULT; Schema: public; Owner: wagthepig
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: wagthepig
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: events events_pkey; Type: CONSTRAINT; Schema: public; Owner: wagthepig
--

ALTER TABLE ONLY public.events
    ADD CONSTRAINT events_pkey PRIMARY KEY (id);


--
-- Name: games games_pkey; Type: CONSTRAINT; Schema: public; Owner: wagthepig
--

ALTER TABLE ONLY public.games
    ADD CONSTRAINT games_pkey PRIMARY KEY (id);


--
-- Name: interests interests_pkey; Type: CONSTRAINT; Schema: public; Owner: wagthepig
--

ALTER TABLE ONLY public.interests
    ADD CONSTRAINT interests_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: wagthepig
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: wagthepig
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: index_games_on_event_id; Type: INDEX; Schema: public; Owner: wagthepig
--

CREATE INDEX index_games_on_event_id ON public.games USING btree (event_id);


--
-- Name: index_games_on_suggestor_id; Type: INDEX; Schema: public; Owner: wagthepig
--

CREATE INDEX index_games_on_suggestor_id ON public.games USING btree (suggestor_id);


--
-- Name: index_interests_on_game_id; Type: INDEX; Schema: public; Owner: wagthepig
--

CREATE INDEX index_interests_on_game_id ON public.interests USING btree (game_id);


--
-- Name: index_interests_on_user_id; Type: INDEX; Schema: public; Owner: wagthepig
--

CREATE INDEX index_interests_on_user_id ON public.interests USING btree (user_id);


--
-- Name: index_interests_on_user_id_and_game_id; Type: INDEX; Schema: public; Owner: wagthepig
--

CREATE UNIQUE INDEX index_interests_on_user_id_and_game_id ON public.interests USING btree (user_id, game_id);


--
-- Name: index_users_on_email; Type: INDEX; Schema: public; Owner: wagthepig
--

CREATE UNIQUE INDEX index_users_on_email ON public.users USING btree (email);


--
-- Name: index_users_on_reset_password_token; Type: INDEX; Schema: public; Owner: wagthepig
--

CREATE UNIQUE INDEX index_users_on_reset_password_token ON public.users USING btree (reset_password_token);


--
-- Name: games fk_rails_d7cbad4d64; Type: FK CONSTRAINT; Schema: public; Owner: wagthepig
--

ALTER TABLE ONLY public.games
    ADD CONSTRAINT fk_rails_d7cbad4d64 FOREIGN KEY (event_id) REFERENCES public.events(id);


--
-- Name: interests fk_rails_dcd304003c; Type: FK CONSTRAINT; Schema: public; Owner: wagthepig
--

ALTER TABLE ONLY public.interests
    ADD CONSTRAINT fk_rails_dcd304003c FOREIGN KEY (game_id) REFERENCES public.games(id);


--
-- Name: interests fk_rails_fba4c79abd; Type: FK CONSTRAINT; Schema: public; Owner: wagthepig
--

ALTER TABLE ONLY public.interests
    ADD CONSTRAINT fk_rails_fba4c79abd FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: games fk_rails_fc97a1782f; Type: FK CONSTRAINT; Schema: public; Owner: wagthepig
--

ALTER TABLE ONLY public.games
    ADD CONSTRAINT fk_rails_fc97a1782f FOREIGN KEY (suggestor_id) REFERENCES public.users(id);


--
-- PostgreSQL database dump complete
--
