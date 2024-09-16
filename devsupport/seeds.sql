--
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
-- Name: users id; Type: DEFAULT; Schema: public; Owner: wagthepig
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);


--
-- Data for Name: users; Type: TABLE DATA; Schema: public; Owner: wagthepig
--

COPY public.users (id, email, encrypted_password, reset_password_token, reset_password_sent_at, remember_created_at, created_at, updated_at, name, bgg_username) FROM stdin;
1	nyarly@gmail.com	$2a$11$gT3FKUyQjPzOBbTbkSfLnuZ1JZ.mj0Pd7thksRqQxB7YU2bqs6t/G	ed81358039a333d337d92e3a0d39a0c992f854b095cc3664e87955f2bf98df7a	2019-10-11 06:12:12.928602	\N	2018-09-27 22:20:41.490675	2024-07-20 00:52:59.984963	Judson	nyarly
\.


--
-- Name: users_id_seq; Type: SEQUENCE SET; Schema: public; Owner: wagthepig
--

SELECT pg_catalog.setval('public.users_id_seq', 3215, true);

--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: wagthepig
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: index_users_on_email; Type: INDEX; Schema: public; Owner: wagthepig
--

CREATE UNIQUE INDEX index_users_on_email ON public.users USING btree (email);


--
-- Name: index_users_on_reset_password_token; Type: INDEX; Schema: public; Owner: wagthepig
--

CREATE UNIQUE INDEX index_users_on_reset_password_token ON public.users USING btree (reset_password_token);


--
-- PostgreSQL database dump complete
--
