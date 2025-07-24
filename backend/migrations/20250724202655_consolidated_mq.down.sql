ALTER TABLE public.mq_msgs OWNER TO current_user;
ALTER TABLE public.mq_payloads OWNER TO current_user;
DROP FUNCTION mq_checkpoint;
DROP FUNCTION mq_keep_alive;
DROP FUNCTION mq_delete;
DROP FUNCTION mq_commit;
DROP FUNCTION mq_insert;
DROP FUNCTION mq_poll;
DROP FUNCTION mq_active_channels;
DROP FUNCTION mq_latest_message;
DROP TABLE mq_payloads;
DROP TABLE mq_msgs;
DROP FUNCTION mq_uuid_exists;
DROP FUNCTION mq_clear;
DROP FUNCTION mq_clear_all;
CREATE OR REPLACE FUNCTION mq_latest_message(from_channel_name TEXT, from_channel_args TEXT)
RETURNS UUID AS $$
    SELECT COALESCE(
        (
            SELECT id FROM mq_msgs
            WHERE channel_name = from_channel_name
            AND channel_args = from_channel_args
            AND after_message_id IS NOT NULL
            AND id != uuid_nil()
            ORDER BY created_at DESC, id DESC
            LIMIT 1
        ),
        uuid_nil()
    )
$$ LANGUAGE SQL STABLE;
-- Main entry-point for job runner: pulls a batch of messages from the queue.
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
            SELECT * FROM mq_msgs
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
$$ LANGUAGE plpgsql;
