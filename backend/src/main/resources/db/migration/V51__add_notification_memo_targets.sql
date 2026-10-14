ALTER TABLE change_book_notifications ADD COLUMN IF NOT EXISTS related_book_id BIGINT;
ALTER TABLE change_book_notifications ADD COLUMN IF NOT EXISTS related_note_id BIGINT;
