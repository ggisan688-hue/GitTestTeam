CREATE TABLE change_book_memo_shares (
    id BIGSERIAL PRIMARY KEY,

    -- 원본이 개인 메모라면 사용
    personal_memo_id BIGINT
        REFERENCES change_book_reading_notes(id)
        ON DELETE CASCADE,

    -- 원본이 독서방 메모라면 사용
    room_memo_id BIGINT
        REFERENCES change_book_reading_room_notes(id)
        ON DELETE CASCADE,

    -- 공유 대상 독서방
    target_room_id BIGINT NOT NULL
        REFERENCES change_book_reading_rooms(id)
        ON DELETE CASCADE,

    -- 공유한 사용자
    shared_by BIGINT NOT NULL
        REFERENCES change_book_users(id)
        ON DELETE CASCADE,

    shared_at TIMESTAMPTZ NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    -- 원본 메모는 반드시 둘 중 하나
    CONSTRAINT chk_change_book_memo_share_source
        CHECK (
            (personal_memo_id IS NOT NULL AND room_memo_id IS NULL)
            OR
            (personal_memo_id IS NULL AND room_memo_id IS NOT NULL)
        )
);

-- 같은 개인 메모를 같은 방에 중복 공유 방지
CREATE UNIQUE INDEX uq_change_book_personal_memo_share
    ON change_book_memo_shares (
        personal_memo_id,
        target_room_id
    )
    WHERE personal_memo_id IS NOT NULL;

-- 같은 방 메모를 같은 방에 중복 공유 방지
CREATE UNIQUE INDEX uq_change_book_room_memo_share
    ON change_book_memo_shares (
        room_memo_id,
        target_room_id
    )
    WHERE room_memo_id IS NOT NULL;

-- 독서방별 공유 메모 조회
CREATE INDEX idx_change_book_memo_shares_target_room
    ON change_book_memo_shares (target_room_id);