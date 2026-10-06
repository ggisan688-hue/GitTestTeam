-- This table name is deliberately application-specific. Do not use or alter
-- a pre-existing public.users table in the shared PostgreSQL database.
CREATE TABLE IF NOT EXISTS change_book_users (
    id BIGSERIAL PRIMARY KEY,
    username VARCHAR(20) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    nickname VARCHAR(50) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_change_book_users_username
    ON change_book_users (username);
