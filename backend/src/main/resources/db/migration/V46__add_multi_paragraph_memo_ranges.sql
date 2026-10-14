-- Additive migration; existing single-paragraph notes remain valid.
ALTER TABLE change_book_reading_notes ADD COLUMN IF NOT EXISTS selection_ranges TEXT;
ALTER TABLE change_book_reading_room_notes ADD COLUMN IF NOT EXISTS selection_ranges TEXT;
