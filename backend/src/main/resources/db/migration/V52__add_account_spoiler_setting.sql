CREATE TABLE IF NOT EXISTS change_book_user_spoiler_settings (
    user_id BIGINT PRIMARY KEY REFERENCES change_book_users(id) ON DELETE CASCADE,
    enabled BOOLEAN NOT NULL DEFAULT TRUE
);
-- Existing room-specific switches remain for compatibility but no longer
-- determine notebook visibility. Every account starts protected by default.
