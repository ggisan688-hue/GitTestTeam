ALTER TABLE change_book_reading_rooms
  ADD COLUMN spoiler_lock_enabled BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN selected_ai_friend_type VARCHAR(20);

ALTER TABLE change_book_reading_room_members
  ADD COLUMN room_nickname VARCHAR(40),
  ADD COLUMN updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP;

CREATE TABLE change_book_reading_room_notes (
  id BIGSERIAL PRIMARY KEY,
  room_id BIGINT NOT NULL REFERENCES change_book_reading_rooms(id) ON DELETE CASCADE,
  user_id BIGINT NOT NULL REFERENCES change_book_users(id) ON DELETE CASCADE,
  book_id BIGINT NOT NULL REFERENCES change_book_books(id) ON DELETE RESTRICT,
  paragraph_order INTEGER NOT NULL,
  start_offset INTEGER,
  end_offset INTEGER,
  type VARCHAR(12) NOT NULL,
  selected_text TEXT,
  content TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT chk_change_book_room_note_type CHECK (type IN ('MEMO', 'HIGHLIGHT')),
  CONSTRAINT chk_change_book_room_note_offsets CHECK (
    (start_offset IS NULL AND end_offset IS NULL) OR
    (start_offset >= 0 AND end_offset > start_offset)
  )
);

CREATE INDEX IF NOT EXISTS idx_change_book_room_members_user
ON change_book_reading_room_members(user_id);

CREATE INDEX IF NOT EXISTS idx_change_book_room_notes_room_position
ON change_book_reading_room_notes(room_id, paragraph_order, created_at);