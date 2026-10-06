CREATE TABLE IF NOT EXISTS change_book_user_favorite_books (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES change_book_users(id) ON DELETE CASCADE,
    book_id BIGINT NOT NULL REFERENCES change_book_books(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_change_book_user_favorite_book UNIQUE (user_id, book_id)
);

-- Fetching a user's library uses newest-first order without touching another
-- user's rows.
CREATE INDEX IF NOT EXISTS idx_change_book_user_favorite_books_user_created
    ON change_book_user_favorite_books (user_id, created_at DESC, id DESC);
