-- Preserve existing shared notes while extending their room/book-scoped type.
ALTER TABLE change_book_reading_room_notes
  DROP CONSTRAINT IF EXISTS chk_change_book_room_note_type;
ALTER TABLE change_book_reading_room_notes
  ADD CONSTRAINT chk_change_book_room_note_type
  CHECK (type IN ('MEMO', 'HIGHLIGHT', 'BOOKMARK'));

CREATE INDEX IF NOT EXISTS idx_change_book_room_notes_scope_type_order
  ON change_book_reading_room_notes(room_id, book_id, type, paragraph_order, created_at);
