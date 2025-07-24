CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE OR REPLACE FUNCTION mq_poll(channel_names TEXT[], batch_size INT DEFAULT 1)
RETURNS TABLE(
    id UUID,
    is_committed BOOLEAN,
    name TEXT,
    payload_json TEXT,
    payload_bytes BYTEA,
    retry_backoff INTERVAL,
    wait_time INTERVAL
) AS $$
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
            WHERE mq_msgs.id != public.uuid_nil()
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
        WHERE mq_msgs.id != public.uuid_nil()
        AND NOT mq_uuid_exists(mq_msgs.after_message_id)
        AND (channel_names IS NULL OR mq_msgs.channel_name = ANY(channel_names));
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Small, frequently updated table of messages
CREATE TABLE IF NOT EXISTS mq_msgs (
    id UUID PRIMARY KEY,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    attempt_at TIMESTAMPTZ DEFAULT NOW(),
    attempts INT NOT NULL DEFAULT 5,
    retry_backoff INTERVAL NOT NULL DEFAULT INTERVAL '1 second',
    channel_name TEXT NOT NULL,
    channel_args TEXT NOT NULL,
    commit_interval INTERVAL,
    after_message_id UUID DEFAULT public.uuid_nil() REFERENCES mq_msgs(id) ON DELETE SET DEFAULT
);

ALTER TABLE mq_msgs ALTER after_message_id SET DEFAULT public.uuid_nil();

-- Internal helper function to check that a UUID is neither NULL nor NIL
CREATE OR REPLACE FUNCTION mq_uuid_exists(
    id UUID
) RETURNS BOOLEAN AS $$
	SELECT id IS NOT NULL AND id != public.uuid_nil()
$$ LANGUAGE SQL IMMUTABLE;


-- Index for ensuring strict message order
CREATE UNIQUE INDEX IF NOT EXISTS mq_msgs_channel_name_channel_args_after_message_id_idx ON mq_msgs(channel_name, channel_args, after_message_id);

-- Internal helper function to randomly select a set of channels with "ready" messages.
CREATE OR REPLACE FUNCTION mq_active_channels(channel_names TEXT[], batch_size INT)
RETURNS TABLE(name TEXT, args TEXT) AS $$
    SELECT channel_name, channel_args
    FROM mq_msgs
    WHERE id != public.uuid_nil()
    AND attempt_at <= NOW()
    AND (channel_names IS NULL OR channel_name = ANY(channel_names))
    AND NOT mq_uuid_exists(after_message_id)
    GROUP BY channel_name, channel_args
    ORDER BY RANDOM()
    LIMIT batch_size
$$ LANGUAGE SQL STABLE;

-- Deletes messages from the queue. This occurs when a message has been
-- processed, or when it expires without being processed.
CREATE OR REPLACE FUNCTION mq_delete(msg_ids UUID[])
RETURNS VOID AS $$
BEGIN
    PERFORM pg_notify(CONCAT('mq_', channel_name), '')
    FROM mq_msgs
    WHERE id = ANY(msg_ids)
    AND after_message_id = public.uuid_nil()
    GROUP BY channel_name;

    IF FOUND THEN
        PERFORM pg_notify('mq', '');
    END IF;

    DELETE FROM mq_msgs WHERE id = ANY(msg_ids);
    DELETE FROM mq_payloads WHERE id = ANY(msg_ids);
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION mq_latest_message(from_channel_name TEXT, from_channel_args TEXT)
RETURNS UUID AS $$
    SELECT COALESCE(
        (
            SELECT id FROM mq_msgs
            WHERE channel_name = from_channel_name
            AND channel_args = from_channel_args
            AND after_message_id IS NOT NULL
            AND id != public.uuid_nil()
            AND NOT EXISTS(
                SELECT * FROM mq_msgs AS mq_msgs2
                WHERE mq_msgs2.after_message_id = mq_msgs.id
            )
            ORDER BY created_at DESC
            LIMIT 1
        ),
        public.uuid_nil()
    )
$$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION mq_clear(channel_names TEXT[])
RETURNS VOID AS $$
BEGIN
    WITH deleted_ids AS (
        DELETE FROM mq_msgs
        WHERE channel_name = ANY(channel_names)
          AND id != public.uuid_nil()
        RETURNING id
    )
    DELETE FROM mq_payloads WHERE id IN (SELECT id FROM deleted_ids);
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION mq_clear IS
    'Deletes all messages with corresponding payloads from a list of channel names';


CREATE OR REPLACE FUNCTION mq_clear_all()
RETURNS VOID AS $$
BEGIN
    WITH deleted_ids AS (
        DELETE FROM mq_msgs
        WHERE id != public.uuid_nil()
        RETURNING id
    )
    DELETE FROM mq_payloads WHERE id IN (SELECT id FROM deleted_ids);
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION mq_clear_all IS
    'Deletes all messages with corresponding payloads';
