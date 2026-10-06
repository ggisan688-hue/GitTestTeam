CREATE TABLE IF NOT EXISTS change_book_reading_activity_logs (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES change_book_users(id) ON DELETE CASCADE,
    book_id BIGINT NOT NULL REFERENCES change_book_books(id) ON DELETE CASCADE,
    activity_date DATE NOT NULL,
    paragraphs_read INTEGER NOT NULL DEFAULT 0,
    last_position_before INTEGER NOT NULL DEFAULT 0,
    last_position_after INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_change_book_reading_activity_day UNIQUE(user_id, book_id, activity_date),
    CONSTRAINT chk_change_book_reading_activity_units CHECK (paragraphs_read >= 0)
);
CREATE INDEX IF NOT EXISTS idx_change_book_reading_activity_user_date
    ON change_book_reading_activity_logs (user_id, activity_date DESC);
