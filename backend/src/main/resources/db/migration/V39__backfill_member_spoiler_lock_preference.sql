-- Spoiler visibility is a reader preference, not a room-wide permission.
-- Preserve the legacy room policy as the initial value for existing members.
ALTER TABLE change_book_reading_room_members
    ADD COLUMN IF NOT EXISTS spoiler_lock_enabled BOOLEAN NOT NULL DEFAULT FALSE;

UPDATE change_book_reading_room_members member
SET spoiler_lock_enabled = room.spoiler_lock_enabled
FROM change_book_reading_rooms room
WHERE room.id = member.room_id;
