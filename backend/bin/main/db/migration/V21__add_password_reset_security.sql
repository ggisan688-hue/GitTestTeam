-- Adds optional email addresses without changing existing users or credentials.
ALTER TABLE change_book_users ADD COLUMN IF NOT EXISTS email VARCHAR(254);
ALTER TABLE change_book_users ADD COLUMN IF NOT EXISTS auth_version INTEGER NOT NULL DEFAULT 0;
CREATE UNIQUE INDEX IF NOT EXISTS uq_change_book_users_email_lower
    ON change_book_users (lower(email)) WHERE email IS NOT NULL;

CREATE TABLE IF NOT EXISTS change_book_password_reset_tokens (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES change_book_users(id) ON DELETE CASCADE,
    token_hash CHAR(64) NOT NULL UNIQUE,
    expires_at TIMESTAMPTZ NOT NULL,
    consumed_at TIMESTAMPTZ,
    requested_ip_hash CHAR(64),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_change_book_password_reset_active
    ON change_book_password_reset_tokens (user_id, created_at DESC)
    WHERE consumed_at IS NULL;

CREATE TABLE IF NOT EXISTS change_book_password_reset_requests (
    id BIGSERIAL PRIMARY KEY,
    email_hash CHAR(64) NOT NULL,
    ip_hash CHAR(64) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_change_book_password_reset_requests_email
    ON change_book_password_reset_requests (email_hash, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_change_book_password_reset_requests_ip
    ON change_book_password_reset_requests (ip_hash, created_at DESC);
