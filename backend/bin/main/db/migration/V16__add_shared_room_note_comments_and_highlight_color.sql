ALTER TABLE change_book_reading_room_notes
  ADD COLUMN IF NOT EXISTS highlight_color VARCHAR(20);

CREATE UNIQUE INDEX IF NOT EXISTS uq_change_book_room_highlight_range
  ON change_book_reading_room_notes(room_id, user_id, paragraph_order, start_offset, end_offset)
  WHERE type = 'HIGHLIGHT';

CREATE TABLE IF NOT EXISTS change_book_reading_room_note_comments (
  id BIGSERIAL PRIMARY KEY,
  room_note_id BIGINT NOT NULL REFERENCES change_book_reading_room_notes(id) ON DELETE CASCADE,
  user_id BIGINT NOT NULL REFERENCES change_book_users(id) ON DELETE CASCADE,
  content VARCHAR(1000) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT chk_change_book_room_note_comment_content CHECK (length(btrim(content)) > 0)
);

CREATE INDEX IF NOT EXISTS idx_change_book_room_note_comments_note_created
  ON change_book_reading_room_note_comments(room_note_id, created_at);
