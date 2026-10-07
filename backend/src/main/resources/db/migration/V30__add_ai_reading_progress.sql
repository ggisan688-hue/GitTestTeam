CREATE TABLE change_book_ai_reading_progress (
    id BIGSERIAL PRIMARY KEY,

    friend_id BIGINT NOT NULL,
    book_id BIGINT NOT NULL,

    last_paragraph_order INTEGER NOT NULL DEFAULT 0,

    book_memory TEXT NOT NULL DEFAULT '',
    persona_memory TEXT NOT NULL DEFAULT '',

    completed BOOLEAN NOT NULL DEFAULT FALSE,

    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT uq_ai_reading_progress_friend_book
        UNIQUE (friend_id, book_id)
);