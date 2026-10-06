-- All application-created codes use the canonical, case-insensitive
-- XXXX-XXXX form. Normalize legacy values before enforcing it at the DB
-- boundary too, so lookups and the unique invariant agree.
UPDATE change_book_reading_rooms
SET join_code = upper(btrim(join_code))
WHERE join_code IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_change_book_room_join_code_ci
    ON change_book_reading_rooms (upper(join_code));

ALTER TABLE change_book_reading_rooms
    ADD CONSTRAINT chk_change_book_room_join_code_format
    CHECK (join_code IS NULL OR join_code ~ '^[A-Z0-9]{4}-[A-Z0-9]{4}$') NOT VALID;
