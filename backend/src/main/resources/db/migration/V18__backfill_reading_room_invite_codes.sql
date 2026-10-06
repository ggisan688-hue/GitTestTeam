-- Older public rooms were created before public rooms received invite codes.
-- A deterministic 8-hex-digit value is unique for the generated BIGSERIAL
-- identifiers in this application and keeps the existing UNIQUE constraint.
UPDATE change_book_reading_rooms
SET join_code = substring(lpad(upper(to_hex(id)), 8, '0') from 1 for 4)
                || '-'
                || substring(lpad(upper(to_hex(id)), 8, '0') from 5 for 4)
WHERE join_code IS NULL OR btrim(join_code) = '';
