-- Existing rooms keep a null selection; the reader's default behavior is unchanged.
ALTER TABLE change_book_reading_rooms
    ADD COLUMN IF NOT EXISTS selected_ai_friend_type VARCHAR(20);
