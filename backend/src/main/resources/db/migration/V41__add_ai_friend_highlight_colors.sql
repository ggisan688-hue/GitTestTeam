
CREATE TABLE change_book_ai_friend_highlight_colors (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL,
    friend_id BIGINT NOT NULL,
    highlight_color VARCHAR(20) NOT NULL DEFAULT 'YELLOW',

    CONSTRAINT fk_friend_highlight_user
        FOREIGN KEY (user_id)
        REFERENCES change_book_users(id)
        ON DELETE CASCADE,

    CONSTRAINT fk_friend_highlight_friend
        FOREIGN KEY (friend_id)
        REFERENCES change_book_ai_reading_friends(id)
        ON DELETE CASCADE,

    CONSTRAINT uq_friend_highlight_user_friend
        UNIQUE (user_id, friend_id)
);
