CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);

ALTER TABLE public.ar_internal_metadata OWNER TO wagthepig;

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

CREATE SEQUENCE public.events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER TABLE public.events_id_seq OWNER TO wagthepig;

ALTER SEQUENCE public.events_id_seq OWNED BY public.events.id;

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

CREATE SEQUENCE public.games_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER TABLE public.games_id_seq OWNER TO wagthepig;

ALTER SEQUENCE public.games_id_seq OWNED BY public.games.id;

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

CREATE SEQUENCE public.interests_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER TABLE public.interests_id_seq OWNER TO wagthepig;

ALTER SEQUENCE public.interests_id_seq OWNED BY public.interests.id;

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);

ALTER TABLE public.schema_migrations OWNER TO wagthepig;

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

CREATE SEQUENCE public.users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER TABLE public.users_id_seq OWNER TO wagthepig;

ALTER SEQUENCE public.users_id_seq OWNED BY public.users.id;

ALTER TABLE ONLY public.events ALTER COLUMN id SET DEFAULT nextval('public.events_id_seq'::regclass);

ALTER TABLE ONLY public.games ALTER COLUMN id SET DEFAULT nextval('public.games_id_seq'::regclass);

ALTER TABLE ONLY public.interests ALTER COLUMN id SET DEFAULT nextval('public.interests_id_seq'::regclass);

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);

ALTER TABLE ONLY public.events
    ADD CONSTRAINT events_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.games
    ADD CONSTRAINT games_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.interests
    ADD CONSTRAINT interests_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);

CREATE INDEX index_games_on_event_id ON public.games USING btree (event_id);

CREATE INDEX index_games_on_suggestor_id ON public.games USING btree (suggestor_id);

CREATE INDEX index_interests_on_game_id ON public.interests USING btree (game_id);

CREATE INDEX index_interests_on_user_id ON public.interests USING btree (user_id);

CREATE UNIQUE INDEX index_interests_on_user_id_and_game_id ON public.interests USING btree (user_id, game_id);

CREATE UNIQUE INDEX index_users_on_email ON public.users USING btree (email);

CREATE UNIQUE INDEX index_users_on_reset_password_token ON public.users USING btree (reset_password_token);

ALTER TABLE ONLY public.games
    ADD CONSTRAINT fk_rails_d7cbad4d64 FOREIGN KEY (event_id) REFERENCES public.events(id);

ALTER TABLE ONLY public.interests
    ADD CONSTRAINT fk_rails_dcd304003c FOREIGN KEY (game_id) REFERENCES public.games(id);

ALTER TABLE ONLY public.interests
    ADD CONSTRAINT fk_rails_fba4c79abd FOREIGN KEY (user_id) REFERENCES public.users(id);

ALTER TABLE ONLY public.games
    ADD CONSTRAINT fk_rails_fc97a1782f FOREIGN KEY (suggestor_id) REFERENCES public.users(id);
