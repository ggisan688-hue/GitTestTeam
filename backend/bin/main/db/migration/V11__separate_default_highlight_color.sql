ALTER TABLE change_book_reader_settings
    ADD COLUMN IF NOT EXISTS default_highlight_color VARCHAR(16) NOT NULL DEFAULT '#FFF59D';

-- Carry forward an already-selected legacy setting without touching any note.
UPDATE change_book_reader_settings
SET default_highlight_color = CASE highlight_color
    WHEN 'GREEN' THEN '#A5D6A7'
    WHEN 'BLUE' THEN '#90CAF9'
    WHEN 'PEACH' THEN '#FFCCBC'
    WHEN 'PURPLE' THEN '#CE93D8'
    ELSE '#FFF59D'
END
WHERE default_highlight_color = '#FFF59D';
