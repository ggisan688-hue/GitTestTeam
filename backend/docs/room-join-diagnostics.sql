-- Run only through a privileged, approved production read-only session.
-- Do not paste invite codes, JWTs, passwords, or user names into tickets/logs.
-- psql example (values remain in the terminal only):
--   psql "$DATABASE_URL" -v invite_code='<REDACTED>' -v room_id='0' -v user_id='0' -f room-join-diagnostics.sql

-- 1. Invite-code lookup. The application uses upper/trim/hyphen normalization.
SELECT id, name, join_code, owner_id, max_members, is_public, created_at, updated_at
FROM change_book_reading_rooms
WHERE upper(join_code) = upper(:'invite_code');

-- 2. Room profile fields are currently stored on the room and membership rows
-- (there is no separate room_profiles table in this schema).
SELECT id, name, book_id, selected_ai_friend_type, spoiler_lock_enabled,
       owner_id, max_members, join_code
FROM change_book_reading_rooms
WHERE id = :'room_id';

-- 3. Current user membership.
SELECT room_id, user_id, role, room_nickname, room_profile_image_url, joined_at
FROM change_book_reading_room_members
WHERE room_id = :'room_id' AND user_id = :'user_id';

-- 4. A primary key on (room_id, user_id) must make this empty.
SELECT room_id, user_id, COUNT(*) AS duplicate_count
FROM change_book_reading_room_members
GROUP BY room_id, user_id
HAVING COUNT(*) > 1;

-- 5. Active member count versus capacity (deletion cascades remove members).
SELECT r.id AS room_id, r.max_members, COUNT(m.user_id) AS member_count
FROM change_book_reading_rooms r
LEFT JOIN change_book_reading_room_members m ON m.room_id = r.id
GROUP BY r.id, r.max_members
ORDER BY r.id;

-- 6. Constraints and indexes needed by the join transaction.
SELECT tc.table_name, tc.constraint_name, tc.constraint_type,
       string_agg(kcu.column_name, ', ' ORDER BY kcu.ordinal_position) AS columns
FROM information_schema.table_constraints tc
LEFT JOIN information_schema.key_column_usage kcu
  ON kcu.constraint_name = tc.constraint_name
 AND kcu.table_schema = tc.table_schema
WHERE tc.table_schema = current_schema()
  AND tc.table_name IN ('change_book_reading_rooms', 'change_book_reading_room_members')
GROUP BY tc.table_name, tc.constraint_name, tc.constraint_type
ORDER BY tc.table_name, tc.constraint_name;

SELECT tablename, indexname, indexdef
FROM pg_indexes
WHERE schemaname = current_schema()
  AND tablename IN ('change_book_reading_rooms', 'change_book_reading_room_members')
ORDER BY tablename, indexname;

-- 7. Flyway must report V20 as successfully applied before this code is live.
SELECT version, description, success, installed_on
FROM flyway_schema_history
ORDER BY installed_rank;
