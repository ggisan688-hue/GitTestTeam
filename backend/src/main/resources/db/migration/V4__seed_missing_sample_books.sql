-- V2 may already be recorded in Flyway on a shared database whose catalog was
-- subsequently changed by another development process. Preserve every existing
-- book and restore only the missing application samples.
-- The shared table may also have been populated with explicit IDs; align the
-- PostgreSQL sequence without changing any existing row before inserting.
SELECT setval(
    pg_get_serial_sequence('change_book_books', 'id'),
    GREATEST(COALESCE((SELECT MAX(id) FROM change_book_books), 1), 1),
    true
);

INSERT INTO change_book_books (title, author, description, cover_image_url, category)
SELECT v.title, v.author, v.description, v.cover_image_url, v.category
FROM (VALUES
    ('채식주의자', '한강', '평범했던 한 여성이 채식을 선언하면서 시작되는 낯설고 강렬한 이야기입니다.', NULL, '소설'),
    ('불편한 편의점', '김호연', '서울의 한 편의점을 배경으로 서로의 마음을 돌보는 사람들의 이야기입니다.', NULL, '소설'),
    ('아몬드', '손원평', '감정을 느끼기 어려운 소년이 세상과 관계 맺는 과정을 그린 성장소설입니다.', NULL, '성장소설')
) AS v(title, author, description, cover_image_url, category)
WHERE NOT EXISTS (
    SELECT 1 FROM change_book_books b WHERE b.title = v.title AND b.author = v.author
);
