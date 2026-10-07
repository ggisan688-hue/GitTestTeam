-- Additive reader metadata only. Existing notes and settings remain intact.
ALTER TABLE change_book_reader_settings
    ADD COLUMN IF NOT EXISTS show_highlights BOOLEAN NOT NULL DEFAULT TRUE;

ALTER TABLE change_book_reading_notes
    ADD COLUMN IF NOT EXISTS linked_highlight_id BIGINT;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'fk_change_book_note_linked_highlight'
    ) THEN
        ALTER TABLE change_book_reading_notes
            ADD CONSTRAINT fk_change_book_note_linked_highlight
            FOREIGN KEY (linked_highlight_id)
            REFERENCES change_book_reading_notes(id)
            ON DELETE SET NULL;
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_change_book_notes_linked_highlight
    ON change_book_reading_notes (linked_highlight_id)
    WHERE linked_highlight_id IS NOT NULL;
