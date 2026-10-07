-- Non-destructive room extension. Existing representative books are copied once.
ALTER TABLE change_book_reading_rooms ADD COLUMN IF NOT EXISTS password_hash VARCHAR(255);
ALTER TABLE change_book_reading_rooms ADD COLUMN IF NOT EXISTS current_book_id BIGINT REFERENCES change_book_books(id) ON DELETE SET NULL;
ALTER TABLE change_book_reading_rooms DROP CONSTRAINT IF EXISTS chk_change_book_room_members;
ALTER TABLE change_book_reading_rooms ADD CONSTRAINT chk_change_book_room_members CHECK (max_members BETWEEN 1 AND 50) NOT VALID;

CREATE TABLE IF NOT EXISTS change_book_reading_room_books (
  room_id BIGINT NOT NULL REFERENCES change_book_reading_rooms(id) ON DELETE CASCADE,
  book_id BIGINT NOT NULL REFERENCES change_book_books(id) ON DELETE RESTRICT,
  display_order INTEGER NOT NULL,
  added_by BIGINT REFERENCES change_book_users(id) ON DELETE SET NULL,
  added_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (room_id, book_id),
  CONSTRAINT uq_change_book_room_book_order UNIQUE (room_id, display_order),
  CONSTRAINT chk_change_book_room_book_order CHECK (display_order >= 0)
);
INSERT INTO change_book_reading_room_books (room_id, book_id, display_order, added_by)
SELECT r.id, r.book_id, 0, r.owner_id
FROM change_book_reading_rooms r
WHERE r.book_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM change_book_reading_room_books rb WHERE rb.room_id = r.id AND rb.book_id = r.book_id);
-- Do not update legacy room rows here.  Some older rows predate the
-- normalized invite-code constraint, and an unrelated row update would fail
-- that historical constraint.  Existing rooms continue to use book_id as
-- their current-book fallback; newly changed rooms set current_book_id.
CREATE INDEX IF NOT EXISTS idx_change_book_room_books_room_order ON change_book_reading_room_books(room_id, display_order);

CREATE TABLE IF NOT EXISTS change_book_room_member_progress (
  room_id BIGINT NOT NULL REFERENCES change_book_reading_rooms(id) ON DELETE CASCADE,
  user_id BIGINT NOT NULL REFERENCES change_book_users(id) ON DELETE CASCADE,
  book_id BIGINT NOT NULL REFERENCES change_book_books(id) ON DELETE RESTRICT,
  progress_percent INTEGER NOT NULL DEFAULT 0,
  last_read_position INTEGER NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (room_id, user_id, book_id),
  CONSTRAINT chk_change_book_room_progress_percent CHECK (progress_percent BETWEEN 0 AND 100),
  CONSTRAINT chk_change_book_room_progress_position CHECK (last_read_position >= 0)
);
CREATE INDEX IF NOT EXISTS idx_change_book_room_member_progress_room_book ON change_book_room_member_progress(room_id, book_id, updated_at DESC);
