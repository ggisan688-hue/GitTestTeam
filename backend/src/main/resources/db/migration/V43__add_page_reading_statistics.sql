ALTER TABLE change_book_user_book_progress
    ADD COLUMN IF NOT EXISTS last_read_page INTEGER NOT NULL DEFAULT 0;

ALTER TABLE change_book_reading_activity_logs
    ADD COLUMN IF NOT EXISTS pages_read INTEGER NOT NULL DEFAULT 0;

ALTER TABLE change_book_reading_activity_logs
    ADD COLUMN IF NOT EXISTS last_page_before INTEGER NOT NULL DEFAULT 0;

ALTER TABLE change_book_reading_activity_logs
    ADD COLUMN IF NOT EXISTS last_page_after INTEGER NOT NULL DEFAULT 0;
