
ALTER TABLE change_book_ai_reading_friends
    ADD COLUMN IF NOT EXISTS input_age VARCHAR(100),
    ADD COLUMN IF NOT EXISTS input_gender VARCHAR(100),
    ADD COLUMN IF NOT EXISTS input_relationship TEXT,
    ADD COLUMN IF NOT EXISTS input_personality TEXT,
    ADD COLUMN IF NOT EXISTS input_speech_style TEXT,
    ADD COLUMN IF NOT EXISTS input_traits TEXT;
