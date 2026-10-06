-- Room member identity is intentionally separate from the global user profile.
ALTER TABLE change_book_reading_room_members
    ADD COLUMN IF NOT EXISTS room_profile_image_url VARCHAR(500);
