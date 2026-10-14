-- Fold legacy room cursors into the single account/book progress row.
-- Keep the latest resume cursor independently of the highest achievement.
WITH sources AS (
    SELECT user_id, book_id, progress_percent, last_read_position,
           GREATEST(max_read_position, last_read_position) AS max_position,
           last_read_at AS read_at, 1 AS source_priority, id AS source_id
    FROM change_book_user_book_progress
    UNION ALL
    SELECT user_id, book_id, progress_percent, last_read_position,
           GREATEST(max_read_position, last_read_position),
           updated_at, 0, room_id
    FROM change_book_room_member_progress
), achievements AS (
    SELECT user_id, book_id, MAX(progress_percent) AS percent,
           MAX(max_position) AS max_position
    FROM sources GROUP BY user_id, book_id
), latest AS (
    SELECT DISTINCT ON (user_id, book_id)
           user_id, book_id, last_read_position, read_at
    FROM sources
    ORDER BY user_id, book_id, read_at DESC, source_priority DESC, source_id DESC
)
INSERT INTO change_book_user_book_progress
    (user_id, book_id, progress_percent, last_read_position, max_read_position,
     last_read_at, created_at, updated_at)
SELECT a.user_id, a.book_id, a.percent, l.last_read_position, a.max_position,
       l.read_at, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
FROM achievements a JOIN latest l USING (user_id, book_id)
ON CONFLICT (user_id, book_id) DO UPDATE SET
    progress_percent = EXCLUDED.progress_percent,
    last_read_position = EXCLUDED.last_read_position,
    max_read_position = EXCLUDED.max_read_position,
    last_read_at = EXCLUDED.last_read_at,
    updated_at = CURRENT_TIMESTAMP;
