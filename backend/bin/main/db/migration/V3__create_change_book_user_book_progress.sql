CREATE TABLE IF NOT EXISTS change_book_user_book_progress (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL,
    book_id BIGINT NOT NULL,
    progress_percent INTEGER NOT NULL DEFAULT 0,
    last_read_position INTEGER NOT NULL DEFAULT 0,
    last_read_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_change_book_progress_user FOREIGN KEY (user_id) REFERENCES change_book_users(id) ON DELETE CASCADE,
    CONSTRAINT fk_change_book_progress_book FOREIGN KEY (book_id) REFERENCES change_book_books(id) ON DELETE CASCADE,
    CONSTRAINT uq_change_book_progress_user_book UNIQUE (user_id, book_id),
    CONSTRAINT chk_change_book_progress_percent CHECK (progress_percent BETWEEN 0 AND 100),
    CONSTRAINT chk_change_book_progress_position CHECK (last_read_position >= 0)
);

CREATE INDEX IF NOT EXISTS idx_change_book_progress_recent
    ON change_book_user_book_progress (user_id, last_read_at DESC);
