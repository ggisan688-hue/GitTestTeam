-- Retain only the oldest exact duplicate highlight. Other users, note types,
-- paragraph locations, and ranges are deliberately not affected.
DELETE FROM change_book_reading_notes n
USING (
    SELECT id, row_number() OVER (
        PARTITION BY user_id, book_id, paragraph_order, start_offset, end_offset
        ORDER BY created_at ASC, id ASC
    ) AS duplicate_number
    FROM change_book_reading_notes
    WHERE note_type = 'HIGHLIGHT'
      AND start_offset IS NOT NULL
      AND end_offset IS NOT NULL
) duplicates
WHERE n.id = duplicates.id
  AND duplicates.duplicate_number > 1;

CREATE UNIQUE INDEX IF NOT EXISTS uq_change_book_highlight_range
    ON change_book_reading_notes (user_id, book_id, paragraph_order, start_offset, end_offset)
    WHERE note_type = 'HIGHLIGHT'
      AND start_offset IS NOT NULL
      AND end_offset IS NOT NULL;
