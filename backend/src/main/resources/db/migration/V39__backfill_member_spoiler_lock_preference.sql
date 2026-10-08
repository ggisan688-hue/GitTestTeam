-- V38 already exists in the shared database.  Make the member-level policy
-- safe for all historical V38 variants without altering any applied schema.
ALTER TABLE change_book_reading_room_members
    ADD COLUMN IF NOT EXISTS spoiler_lock_enabled BOOLEAN NOT NULL DEFAULT FALSE;

UPDATE change_book_reading_room_members member
SET spoiler_lock_enabled = room.spoiler_lock_enabled
FROM change_book_reading_rooms room
WHERE room.id = member.room_id
  AND member.spoiler_lock_enabled = FALSE
  AND room.spoiler_lock_enabled = TRUE;
