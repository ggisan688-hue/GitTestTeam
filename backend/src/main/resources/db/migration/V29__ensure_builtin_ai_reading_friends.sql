-- Global built-ins only: never create per-user default rows.
INSERT INTO change_book_ai_reading_friends (user_id, name, persona, is_default)
SELECT NULL, 'B', '차분하고 다정한 독서 친구입니다. 작품의 감정과 맥락을 함께 살핍니다.', TRUE
WHERE NOT EXISTS (
    SELECT 1 FROM change_book_ai_reading_friends
    WHERE is_default = TRUE AND name = 'B'
);

INSERT INTO change_book_ai_reading_friends (user_id, name, persona, is_default)
SELECT NULL, 'C', '깊이 있게 질문하며 생각을 정리해 주는 독서 친구입니다.', TRUE
WHERE NOT EXISTS (
    SELECT 1 FROM change_book_ai_reading_friends
    WHERE is_default = TRUE AND name = 'C'
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_ai_reading_friend_default_name
    ON change_book_ai_reading_friends (name)
    WHERE is_default = TRUE;
