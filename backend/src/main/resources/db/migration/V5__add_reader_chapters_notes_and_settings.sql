-- Reader additions.  Existing book, paragraph, user and progress rows remain untouched.
CREATE TABLE IF NOT EXISTS change_book_chapters (
    id BIGSERIAL PRIMARY KEY,
    book_id BIGINT NOT NULL REFERENCES change_book_books(id) ON DELETE CASCADE,
    chapter_number INTEGER NOT NULL,
    chapter_title VARCHAR(200) NOT NULL,
    start_paragraph_order INTEGER NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_change_book_chapters_book_number UNIQUE (book_id, chapter_number),
    CONSTRAINT chk_change_book_chapter_number CHECK (chapter_number > 0),
    CONSTRAINT chk_change_book_chapter_start CHECK (start_paragraph_order > 0)
);

-- The existing paragraph source has no chapter metadata.  A safe, explicit
-- single chapter gives every existing book a usable table of contents.
INSERT INTO change_book_chapters (book_id, chapter_number, chapter_title, start_paragraph_order)
SELECT id, 1, '전체 본문', 1
FROM change_book_books b
WHERE NOT EXISTS (SELECT 1 FROM change_book_chapters c WHERE c.book_id = b.id);

CREATE TABLE IF NOT EXISTS change_book_reading_notes (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES change_book_users(id) ON DELETE CASCADE,
    book_id BIGINT NOT NULL REFERENCES change_book_books(id) ON DELETE CASCADE,
    paragraph_order INTEGER NOT NULL,
    note_type VARCHAR(20) NOT NULL,
    memo_content TEXT,
    selected_text TEXT,
    start_offset INTEGER,
    end_offset INTEGER,
    highlight_color VARCHAR(20),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_change_book_note_type CHECK (note_type IN ('HIGHLIGHT', 'MEMO', 'BOOKMARK')),
    CONSTRAINT chk_change_book_note_position CHECK (paragraph_order > 0),
    CONSTRAINT chk_change_book_note_offsets CHECK (
        (start_offset IS NULL AND end_offset IS NULL) OR
        (start_offset >= 0 AND end_offset > start_offset)
    )
);
CREATE INDEX IF NOT EXISTS idx_change_book_notes_user_book
    ON change_book_reading_notes (user_id, book_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_change_book_notes_location
    ON change_book_reading_notes (user_id, book_id, paragraph_order);
CREATE UNIQUE INDEX IF NOT EXISTS uq_change_book_bookmark_location
    ON change_book_reading_notes (user_id, book_id, paragraph_order)
    WHERE note_type = 'BOOKMARK';

CREATE TABLE IF NOT EXISTS change_book_reader_settings (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL UNIQUE REFERENCES change_book_users(id) ON DELETE CASCADE,
    font_scale NUMERIC(4,2) NOT NULL DEFAULT 1.00,
    line_height_step INTEGER NOT NULL DEFAULT 1,
    theme VARCHAR(20) NOT NULL DEFAULT 'LIGHT',
    two_column BOOLEAN NOT NULL DEFAULT FALSE,
    keep_screen_on BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_change_book_reader_font CHECK (font_scale BETWEEN 0.80 AND 1.40),
    CONSTRAINT chk_change_book_reader_line_height CHECK (line_height_step BETWEEN 0 AND 2),
    CONSTRAINT chk_change_book_reader_theme CHECK (theme IN ('LIGHT', 'SEPIA', 'DARK'))
);
