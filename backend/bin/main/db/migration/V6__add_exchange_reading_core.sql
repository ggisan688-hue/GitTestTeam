CREATE TABLE change_book_user_profiles (
  user_id BIGINT PRIMARY KEY REFERENCES change_book_users(id) ON DELETE CASCADE,
  bio VARCHAR(300), avatar_url VARCHAR(500), updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE change_book_shelves (
  id BIGSERIAL PRIMARY KEY, user_id BIGINT NOT NULL REFERENCES change_book_users(id) ON DELETE CASCADE,
  name VARCHAR(80) NOT NULL, description VARCHAR(300), is_public BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP, updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT uq_change_book_shelf_name UNIQUE(user_id,name)
);
CREATE TABLE change_book_shelf_books (
  shelf_id BIGINT NOT NULL REFERENCES change_book_shelves(id) ON DELETE CASCADE,
  book_id BIGINT NOT NULL REFERENCES change_book_books(id) ON DELETE RESTRICT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP, PRIMARY KEY(shelf_id,book_id)
);
CREATE TABLE change_book_friendships (
  id BIGSERIAL PRIMARY KEY, requester_id BIGINT NOT NULL REFERENCES change_book_users(id) ON DELETE CASCADE,
  addressee_id BIGINT NOT NULL REFERENCES change_book_users(id) ON DELETE CASCADE,
  status VARCHAR(12) NOT NULL DEFAULT 'PENDING', created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP, updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT chk_change_book_friendship_users CHECK(requester_id <> addressee_id),
  CONSTRAINT chk_change_book_friendship_status CHECK(status IN ('PENDING','ACCEPTED','REJECTED')),
  CONSTRAINT uq_change_book_friendship_pair UNIQUE(requester_id,addressee_id)
);
CREATE TABLE change_book_reading_rooms (
 id BIGSERIAL PRIMARY KEY, owner_id BIGINT NOT NULL REFERENCES change_book_users(id) ON DELETE CASCADE,
 book_id BIGINT REFERENCES change_book_books(id) ON DELETE SET NULL, name VARCHAR(100) NOT NULL, description VARCHAR(500), max_members INTEGER NOT NULL DEFAULT 6,
 is_public BOOLEAN NOT NULL DEFAULT TRUE, join_code VARCHAR(16) UNIQUE, created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP, updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
 CONSTRAINT chk_change_book_room_members CHECK(max_members BETWEEN 2 AND 10)
);
CREATE TABLE change_book_reading_room_members (
 room_id BIGINT NOT NULL REFERENCES change_book_reading_rooms(id) ON DELETE CASCADE, user_id BIGINT NOT NULL REFERENCES change_book_users(id) ON DELETE CASCADE,
 role VARCHAR(12) NOT NULL DEFAULT 'MEMBER', joined_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP, PRIMARY KEY(room_id,user_id), CONSTRAINT chk_change_book_room_role CHECK(role IN ('OWNER','MEMBER'))
);
CREATE TABLE change_book_notifications (
 id BIGSERIAL PRIMARY KEY, user_id BIGINT NOT NULL REFERENCES change_book_users(id) ON DELETE CASCADE, type VARCHAR(40) NOT NULL, title VARCHAR(160) NOT NULL, body VARCHAR(500) NOT NULL,
 related_room_id BIGINT, related_user_id BIGINT, is_read BOOLEAN NOT NULL DEFAULT FALSE, created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE change_book_notification_settings (
 user_id BIGINT PRIMARY KEY REFERENCES change_book_users(id) ON DELETE CASCADE, friend_enabled BOOLEAN NOT NULL DEFAULT TRUE, room_enabled BOOLEAN NOT NULL DEFAULT TRUE, activity_enabled BOOLEAN NOT NULL DEFAULT TRUE, updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX idx_change_book_shelves_user ON change_book_shelves(user_id,updated_at DESC);
CREATE INDEX idx_change_book_notifications_user ON change_book_notifications(user_id,is_read,created_at DESC);
CREATE INDEX idx_change_book_rooms_public ON change_book_reading_rooms(is_public,created_at DESC);
