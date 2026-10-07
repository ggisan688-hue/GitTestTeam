ALTER TABLE change_book_reading_room_notes ADD COLUMN IF NOT EXISTS version BIGINT NOT NULL DEFAULT 0;
ALTER TABLE change_book_reading_room_note_comments ADD COLUMN IF NOT EXISTS version BIGINT NOT NULL DEFAULT 0;
CREATE INDEX IF NOT EXISTS idx_change_book_room_notes_room_book_position
  ON change_book_reading_room_notes(room_id, book_id, paragraph_order, created_at);
