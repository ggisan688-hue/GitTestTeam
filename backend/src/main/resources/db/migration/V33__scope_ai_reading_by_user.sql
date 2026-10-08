-- AI 독서 메모를 로그인 사용자별로 분리한다.
-- 기존 데이터는 소유 사용자를 확정할 수 없으므로 NULL 상태로 보존한다.
ALTER TABLE change_book_ai_reading_notes
    ADD COLUMN user_id BIGINT;

ALTER TABLE change_book_ai_reading_notes
    ADD CONSTRAINT fk_ai_reading_note_user
        FOREIGN KEY (user_id)
        REFERENCES change_book_users(id)
        ON DELETE CASCADE;


-- AI 이어읽기 진행상황도 로그인 사용자별로 분리한다.
ALTER TABLE change_book_ai_reading_progress
    ADD COLUMN user_id BIGINT;

ALTER TABLE change_book_ai_reading_progress
    ADD CONSTRAINT fk_ai_reading_progress_user
        FOREIGN KEY (user_id)
        REFERENCES change_book_users(id)
        ON DELETE CASCADE;

-- 기존 친구+책 단위 중복 제한 제거
ALTER TABLE change_book_ai_reading_progress
    DROP CONSTRAINT IF EXISTS uq_ai_reading_progress_friend_book;

-- 사용자+친구+책 단위 중복 제한 설정
ALTER TABLE change_book_ai_reading_progress
    ADD CONSTRAINT uq_ai_reading_progress_user_friend_book
        UNIQUE (user_id, friend_id, book_id);

-- 사용자별 AI 메모 조회용 인덱스
CREATE INDEX IF NOT EXISTS ix_ai_reading_notes_user_friend_book
    ON change_book_ai_reading_notes (user_id, friend_id, book_id);
