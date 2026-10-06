CREATE TABLE change_book_reading_room_sync_events (
  id BIGSERIAL PRIMARY KEY,
  room_id BIGINT NOT NULL REFERENCES change_book_reading_rooms(id) ON DELETE CASCADE,
  book_id BIGINT NOT NULL REFERENCES change_book_books(id) ON DELETE CASCADE,
  event_type VARCHAR(40) NOT NULL,
  entity_id BIGINT,
  version_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_change_book_room_sync_events_room_id
  ON change_book_reading_room_sync_events(room_id, id);
