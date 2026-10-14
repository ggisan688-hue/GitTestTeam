-- Start page-volume statistics from zero; retain progress, notes and settings.
-- This one-time reset applies to every account when this migration runs.
DELETE FROM change_book_reading_activity_logs;

CREATE TABLE change_book_standard_page_reads (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES change_book_users(id) ON DELETE CASCADE,
    book_id BIGINT NOT NULL REFERENCES change_book_books(id) ON DELETE CASCADE,
    page_number INTEGER NOT NULL CHECK (page_number BETWEEN 1 AND 100000),
    read_date DATE NOT NULL,
    CONSTRAINT uq_standard_page_read UNIQUE (user_id, book_id, page_number)
);
-- Reference pagination v1: bundled NotoSerifKR, 18px, line height 1.85,
-- 1280x800 logical viewport, one column, TextScaler.noScaling.
