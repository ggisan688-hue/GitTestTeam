CREATE INDEX idx_change_book_friendships_requester_status
    ON change_book_friendships(requester_id, status, updated_at DESC);
CREATE INDEX idx_change_book_friendships_addressee_status
    ON change_book_friendships(addressee_id, status, updated_at DESC);
CREATE INDEX idx_change_book_room_members_user
    ON change_book_reading_room_members(user_id, room_id);
CREATE INDEX idx_change_book_room_members_room_joined
    ON change_book_reading_room_members(room_id, joined_at);
