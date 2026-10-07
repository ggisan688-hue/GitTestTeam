-- Hibernate maps String fields as VARCHAR. Convert fixed-width hashes without
-- changing their values so JPA validation is portable across PostgreSQL.
ALTER TABLE change_book_password_reset_tokens
    ALTER COLUMN token_hash TYPE VARCHAR(64),
    ALTER COLUMN requested_ip_hash TYPE VARCHAR(64);
ALTER TABLE change_book_password_reset_requests
    ALTER COLUMN email_hash TYPE VARCHAR(64),
    ALTER COLUMN ip_hash TYPE VARCHAR(64);
