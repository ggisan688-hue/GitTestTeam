-- V5 had to infer a single chapter for every book.  Those rows are retained
-- for history, but are not presented as real table-of-contents entries.
ALTER TABLE change_book_chapters ADD COLUMN IF NOT EXISTS verified BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE change_book_chapters ADD COLUMN IF NOT EXISTS source_reference VARCHAR(500);
CREATE INDEX IF NOT EXISTS idx_change_book_chapters_verified
    ON change_book_chapters (book_id, verified, chapter_number);
