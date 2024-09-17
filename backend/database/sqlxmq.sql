--
-- PostgreSQL database dump
--

-- Dumped from database version 15.7
-- Dumped by pg_dump version 15.7

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

--
-- Name: uuid-ossp; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA public;


--
-- Name: EXTENSION "uuid-ossp"; Type: COMMENT; Schema: -; Owner:
--

COMMENT ON EXTENSION "uuid-ossp" IS 'generate universally unique identifiers (UUIDs)';


--
-- Name: mq_new_t; Type: TYPE; Schema: public; Owner: judson
--

CREATE TYPE public.mq_new_t AS (
	id uuid,
	delay interval,
	retries integer,
	retry_backoff interval,
	channel_name text,
	channel_args text,
	commit_interval interval,
	ordered boolean,
	name text,
	payload_json text,
	payload_bytes bytea
);


ALTER TYPE public.mq_new_t OWNER TO judson;

--
-- Name: mq_active_channels(text[], integer); Type: FUNCTION; Schema: public; Owner: judson
--

CREATE FUNCTION public.mq_active_channels(channel_names text[], batch_size integer) RETURNS TABLE(name text, args text)
    LANGUAGE sql STABLE
    AS $$
    SELECT channel_name, channel_args
    FROM mq_msgs
    WHERE id != uuid_nil()
    AND attempt_at <= NOW()
    AND (channel_names IS NULL OR channel_name = ANY(channel_names))
    AND NOT mq_uuid_exists(after_message_id)
    GROUP BY channel_name, channel_args
    ORDER BY RANDOM()
    LIMIT batch_size
$$;


ALTER FUNCTION public.mq_active_channels(channel_names text[], batch_size integer) OWNER TO judson;

--
-- Name: mq_checkpoint(uuid, interval, text, bytea, integer); Type: FUNCTION; Schema: public; Owner: judson
--

CREATE FUNCTION public.mq_checkpoint(msg_id uuid, duration interval, new_payload_json text, new_payload_bytes bytea, extra_retries integer) RETURNS void
    LANGUAGE sql
    AS $$
    UPDATE mq_msgs
    SET
        attempt_at = GREATEST(attempt_at, NOW() + duration),
        attempts = attempts + COALESCE(extra_retries, 0)
    WHERE id = msg_id;

    UPDATE mq_payloads
    SET
        payload_json = COALESCE(new_payload_json::JSONB, payload_json),
        payload_bytes = COALESCE(new_payload_bytes, payload_bytes)
    WHERE
        id = msg_id;
$$;


ALTER FUNCTION public.mq_checkpoint(msg_id uuid, duration interval, new_payload_json text, new_payload_bytes bytea, extra_retries integer) OWNER TO judson;

--
-- Name: mq_clear(text[]); Type: FUNCTION; Schema: public; Owner: judson
--

CREATE FUNCTION public.mq_clear(channel_names text[]) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    WITH deleted_ids AS (
        DELETE FROM mq_msgs
        WHERE channel_name = ANY(channel_names)
          AND id != uuid_nil()
        RETURNING id
    )
    DELETE FROM mq_payloads WHERE id IN (SELECT id FROM deleted_ids);
END;
$$;


ALTER FUNCTION public.mq_clear(channel_names text[]) OWNER TO judson;

--
-- Name: FUNCTION mq_clear(channel_names text[]); Type: COMMENT; Schema: public; Owner: judson
--

COMMENT ON FUNCTION public.mq_clear(channel_names text[]) IS 'Deletes all messages with corresponding payloads from a list of channel names';


--
-- Name: mq_clear_all(); Type: FUNCTION; Schema: public; Owner: judson
--

CREATE FUNCTION public.mq_clear_all() RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    WITH deleted_ids AS (
        DELETE FROM mq_msgs
        WHERE id != uuid_nil()
        RETURNING id
    )
    DELETE FROM mq_payloads WHERE id IN (SELECT id FROM deleted_ids);
END;
$$;


ALTER FUNCTION public.mq_clear_all() OWNER TO judson;

--
-- Name: FUNCTION mq_clear_all(); Type: COMMENT; Schema: public; Owner: judson
--

COMMENT ON FUNCTION public.mq_clear_all() IS 'Deletes all messages with corresponding payloads';


--
-- Name: mq_commit(uuid[]); Type: FUNCTION; Schema: public; Owner: judson
--

CREATE FUNCTION public.mq_commit(msg_ids uuid[]) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE mq_msgs
    SET
        attempt_at = attempt_at - commit_interval,
        commit_interval = NULL
    WHERE id = ANY(msg_ids)
    AND commit_interval IS NOT NULL;
END;
$$;


ALTER FUNCTION public.mq_commit(msg_ids uuid[]) OWNER TO judson;

--
-- Name: mq_delete(uuid[]); Type: FUNCTION; Schema: public; Owner: judson
--

CREATE FUNCTION public.mq_delete(msg_ids uuid[]) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    PERFORM pg_notify(CONCAT('mq_', channel_name), '')
    FROM mq_msgs
    WHERE id = ANY(msg_ids)
    AND after_message_id = uuid_nil()
    GROUP BY channel_name;

    IF FOUND THEN
        PERFORM pg_notify('mq', '');
    END IF;

    DELETE FROM mq_msgs WHERE id = ANY(msg_ids);
    DELETE FROM mq_payloads WHERE id = ANY(msg_ids);
END;
$$;


ALTER FUNCTION public.mq_delete(msg_ids uuid[]) OWNER TO judson;

--
-- Name: mq_insert(public.mq_new_t[]); Type: FUNCTION; Schema: public; Owner: judson
--

CREATE FUNCTION public.mq_insert(new_messages public.mq_new_t[]) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    PERFORM pg_notify(CONCAT('mq_', channel_name), '')
    FROM unnest(new_messages) AS new_msgs
    GROUP BY channel_name;

    IF FOUND THEN
        PERFORM pg_notify('mq', '');
    END IF;

    INSERT INTO mq_payloads (
        id,
        name,
        payload_json,
        payload_bytes
    ) SELECT
        id,
        name,
        payload_json::JSONB,
        payload_bytes
    FROM UNNEST(new_messages);

    INSERT INTO mq_msgs (
        id,
        attempt_at,
        attempts,
        retry_backoff,
        channel_name,
        channel_args,
        commit_interval,
        after_message_id
    )
    SELECT
        id,
        NOW() + delay + COALESCE(commit_interval, INTERVAL '0'),
        retries + 1,
        retry_backoff,
        channel_name,
        channel_args,
        commit_interval,
        CASE WHEN ordered
            THEN
                LAG(id, 1, mq_latest_message(channel_name, channel_args))
                OVER (PARTITION BY channel_name, channel_args, ordered ORDER BY id)
            ELSE
                NULL
            END
    FROM UNNEST(new_messages);
END;
$$;


ALTER FUNCTION public.mq_insert(new_messages public.mq_new_t[]) OWNER TO judson;

--
-- Name: mq_keep_alive(uuid[], interval); Type: FUNCTION; Schema: public; Owner: judson
--

CREATE FUNCTION public.mq_keep_alive(msg_ids uuid[], duration interval) RETURNS void
    LANGUAGE sql
    AS $$
    UPDATE mq_msgs
    SET
        attempt_at = NOW() + duration,
        commit_interval = commit_interval + ((NOW() + duration) - attempt_at)
    WHERE id = ANY(msg_ids)
    AND attempt_at < NOW() + duration;
$$;


ALTER FUNCTION public.mq_keep_alive(msg_ids uuid[], duration interval) OWNER TO judson;

--
-- Name: mq_latest_message(text, text); Type: FUNCTION; Schema: public; Owner: judson
--

CREATE FUNCTION public.mq_latest_message(from_channel_name text, from_channel_args text) RETURNS uuid
    LANGUAGE sql STABLE
    AS $$
    SELECT COALESCE(
        (
            SELECT id FROM mq_msgs
            WHERE channel_name = from_channel_name
            AND channel_args = from_channel_args
            AND after_message_id IS NOT NULL
            AND id != uuid_nil()
            AND NOT EXISTS(
                SELECT * FROM mq_msgs AS mq_msgs2
                WHERE mq_msgs2.after_message_id = mq_msgs.id
            )
            ORDER BY created_at DESC
            LIMIT 1
        ),
        uuid_nil()
    )
$$;


ALTER FUNCTION public.mq_latest_message(from_channel_name text, from_channel_args text) OWNER TO judson;

--
-- Name: mq_poll(text[], integer); Type: FUNCTION; Schema: public; Owner: judson
--

CREATE FUNCTION public.mq_poll(channel_names text[], batch_size integer DEFAULT 1) RETURNS TABLE(id uuid, is_committed boolean, name text, payload_json text, payload_bytes bytea, retry_backoff interval, wait_time interval)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY UPDATE mq_msgs
    SET
        attempt_at = CASE WHEN mq_msgs.attempts = 1 THEN NULL ELSE NOW() + mq_msgs.retry_backoff END,
        attempts = mq_msgs.attempts - 1,
        retry_backoff = mq_msgs.retry_backoff * 2
    FROM (
        SELECT
            msgs.id
        FROM mq_active_channels(channel_names, batch_size) AS active_channels
        INNER JOIN LATERAL (
            SELECT mq_msgs.id FROM mq_msgs
            WHERE mq_msgs.id != uuid_nil()
            AND mq_msgs.attempt_at <= NOW()
            AND mq_msgs.channel_name = active_channels.name
            AND mq_msgs.channel_args = active_channels.args
            AND NOT mq_uuid_exists(mq_msgs.after_message_id)
            ORDER BY mq_msgs.attempt_at ASC
            LIMIT batch_size
        ) AS msgs ON TRUE
        LIMIT batch_size
    ) AS messages_to_update
    LEFT JOIN mq_payloads ON mq_payloads.id = messages_to_update.id
    WHERE mq_msgs.id = messages_to_update.id
    AND mq_msgs.attempt_at <= NOW()
    RETURNING
        mq_msgs.id,
        mq_msgs.commit_interval IS NULL,
        mq_payloads.name,
        mq_payloads.payload_json::TEXT,
        mq_payloads.payload_bytes,
        mq_msgs.retry_backoff / 2,
        interval '0' AS wait_time;

    IF NOT FOUND THEN
        RETURN QUERY SELECT
            NULL::UUID,
            NULL::BOOLEAN,
            NULL::TEXT,
            NULL::TEXT,
            NULL::BYTEA,
            NULL::INTERVAL,
            MIN(mq_msgs.attempt_at) - NOW()
        FROM mq_msgs
        WHERE mq_msgs.id != uuid_nil()
        AND NOT mq_uuid_exists(mq_msgs.after_message_id)
        AND (channel_names IS NULL OR mq_msgs.channel_name = ANY(channel_names));
    END IF;
END;
$$;


ALTER FUNCTION public.mq_poll(channel_names text[], batch_size integer) OWNER TO judson;

--
-- Name: mq_uuid_exists(uuid); Type: FUNCTION; Schema: public; Owner: judson
--

CREATE FUNCTION public.mq_uuid_exists(id uuid) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    AS $$
	SELECT id IS NOT NULL AND id != uuid_nil()
$$;


ALTER FUNCTION public.mq_uuid_exists(id uuid) OWNER TO judson;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: _sqlx_migrations; Type: TABLE; Schema: public; Owner: judson
--

CREATE TABLE public._sqlx_migrations (
    version bigint NOT NULL,
    description text NOT NULL,
    installed_on timestamp with time zone DEFAULT now() NOT NULL,
    success boolean NOT NULL,
    checksum bytea NOT NULL,
    execution_time bigint NOT NULL
);


ALTER TABLE public._sqlx_migrations OWNER TO judson;

--
-- Name: mq_msgs; Type: TABLE; Schema: public; Owner: judson
--

CREATE TABLE public.mq_msgs (
    id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    attempt_at timestamp with time zone DEFAULT now(),
    attempts integer DEFAULT 5 NOT NULL,
    retry_backoff interval DEFAULT '00:00:01'::interval NOT NULL,
    channel_name text NOT NULL,
    channel_args text NOT NULL,
    commit_interval interval,
    after_message_id uuid DEFAULT public.uuid_nil()
);


ALTER TABLE public.mq_msgs OWNER TO judson;

--
-- Name: mq_payloads; Type: TABLE; Schema: public; Owner: judson
--

CREATE TABLE public.mq_payloads (
    id uuid NOT NULL,
    name text NOT NULL,
    payload_json jsonb,
    payload_bytes bytea
);


ALTER TABLE public.mq_payloads OWNER TO judson;

--
-- Name: _sqlx_migrations _sqlx_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: judson
--

ALTER TABLE ONLY public._sqlx_migrations
    ADD CONSTRAINT _sqlx_migrations_pkey PRIMARY KEY (version);


--
-- Name: mq_msgs mq_msgs_pkey; Type: CONSTRAINT; Schema: public; Owner: judson
--

ALTER TABLE ONLY public.mq_msgs
    ADD CONSTRAINT mq_msgs_pkey PRIMARY KEY (id);


--
-- Name: mq_payloads mq_payloads_pkey; Type: CONSTRAINT; Schema: public; Owner: judson
--

ALTER TABLE ONLY public.mq_payloads
    ADD CONSTRAINT mq_payloads_pkey PRIMARY KEY (id);


--
-- Name: mq_msgs_channel_name_channel_args_after_message_id_idx; Type: INDEX; Schema: public; Owner: judson
--

CREATE UNIQUE INDEX mq_msgs_channel_name_channel_args_after_message_id_idx ON public.mq_msgs USING btree (channel_name, channel_args, after_message_id);


--
-- Name: mq_msgs_channel_name_channel_args_attempt_at_idx; Type: INDEX; Schema: public; Owner: judson
--

CREATE INDEX mq_msgs_channel_name_channel_args_attempt_at_idx ON public.mq_msgs USING btree (channel_name, channel_args, attempt_at) WHERE ((id <> public.uuid_nil()) AND (NOT public.mq_uuid_exists(after_message_id)));


--
-- Name: mq_msgs_channel_name_channel_args_created_at_id_idx; Type: INDEX; Schema: public; Owner: judson
--

CREATE INDEX mq_msgs_channel_name_channel_args_created_at_id_idx ON public.mq_msgs USING btree (channel_name, channel_args, created_at, id) WHERE ((id <> public.uuid_nil()) AND (after_message_id IS NOT NULL));


--
-- Name: mq_msgs mq_msgs_after_message_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: judson
--

ALTER TABLE ONLY public.mq_msgs
    ADD CONSTRAINT mq_msgs_after_message_id_fkey FOREIGN KEY (after_message_id) REFERENCES public.mq_msgs(id) ON DELETE SET DEFAULT;


--
-- PostgreSQL database dump complete
--
