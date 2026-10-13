-- Keep a permanent high-water mark for spoiler filtering. The normal
-- last_read_position remains the resume cursor and can legitimately move back.
ALTER TABLE change_book_user_book_progress
    ADD COLUMN IF NOT EXISTS max_read_position INTEGER NOT NULL DEFAULT 0;

UPDATE change_book_user_book_progress
SET max_read_position = GREATEST(max_read_position, last_read_position);

ALTER TABLE change_book_room_member_progress
    ADD COLUMN IF NOT EXISTS max_read_position INTEGER NOT NULL DEFAULT 0;

UPDATE change_book_room_member_progress
SET max_read_position = GREATEST(max_read_position, last_read_position);
