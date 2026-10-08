CREATE TABLE change_book_ai_reading_friend_selections (
    user_id BIGINT NOT NULL,
    book_id BIGINT NOT NULL,
    friend_id BIGINT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_ai_reading_friend_selections
        PRIMARY KEY (user_id, book_id, friend_id),

    CONSTRAINT fk_ai_selection_user
        FOREIGN KEY (user_id)
        REFERENCES change_book_users(id)
        ON DELETE CASCADE,

    CONSTRAINT fk_ai_selection_book
        FOREIGN KEY (book_id)
        REFERENCES change_book_books(id)
        ON DELETE CASCADE,

    CONSTRAINT fk_ai_selection_friend
        FOREIGN KEY (friend_id)
        REFERENCES change_book_ai_reading_friends(id)
        ON DELETE CASCADE
);