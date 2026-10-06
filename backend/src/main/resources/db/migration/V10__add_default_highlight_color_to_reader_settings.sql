ALTER TABLE change_book_reader_settings
    ADD COLUMN IF NOT EXISTS highlight_color VARCHAR(20) NOT NULL DEFAULT 'YELLOW';

-- Existing rows retain their notes; legacy highlights render as the original
-- yellow default when no individual color was stored.
UPDATE change_book_reading_notes
SET highlight_color = 'YELLOW'
WHERE note_type = 'HIGHLIGHT'
  AND (highlight_color IS NULL OR highlight_color = '');

ALTER TABLE change_book_reader_settings
    ADD CONSTRAINT chk_change_book_reader_highlight_color
    CHECK (highlight_color IN ('YELLOW', 'PEACH', 'PINK', 'GREEN', 'BLUE', 'PURPLE'));
