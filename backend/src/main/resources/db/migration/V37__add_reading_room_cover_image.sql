-- A room cover is separate from member profile images and can only be changed by its owner.
ALTER TABLE change_book_reading_rooms
    ADD COLUMN IF NOT EXISTS cover_image_url VARCHAR(500);
