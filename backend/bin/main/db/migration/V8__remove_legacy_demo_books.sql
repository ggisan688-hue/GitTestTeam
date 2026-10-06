-- V2/V4 historically inserted these three demonstration rows.  Those
-- migrations are immutable, so a later migration removes only their exact
-- fingerprints after all earlier migrations have run.
--
-- Do not delete a row that has acquired user content or links.  In that case
-- it is no longer safe to treat it as disposable seed data.
DELETE FROM change_book_books b
WHERE (
    (b.title = '채식주의자' AND b.author = '한강'
      AND b.description = '평범했던 한 여성이 채식을 선언하면서 시작되는 낯설고 강렬한 이야기입니다.'
      AND b.category = '소설' AND b.cover_image_url IS NULL)
    OR (b.title = '불편한 편의점' AND b.author = '김호연'
      AND b.description = '서울의 한 편의점을 배경으로 서로의 마음을 돌보는 사람들의 이야기입니다.'
      AND b.category = '소설' AND b.cover_image_url IS NULL)
    OR (b.title = '아몬드' AND b.author = '손원평'
      AND b.description = '감정을 느끼기 어려운 소년이 세상과 관계 맺는 과정을 그린 성장소설입니다.'
      AND b.category = '성장소설' AND b.cover_image_url IS NULL)
  )
  AND NOT EXISTS (SELECT 1 FROM change_book_paragraphs p WHERE p.book_id = b.id)
  AND NOT EXISTS (SELECT 1 FROM change_book_user_book_progress p WHERE p.book_id = b.id)
  AND NOT EXISTS (SELECT 1 FROM change_book_reading_notes n WHERE n.book_id = b.id)
  AND NOT EXISTS (SELECT 1 FROM change_book_shelf_books s WHERE s.book_id = b.id)
  AND NOT EXISTS (SELECT 1 FROM change_book_reading_rooms r WHERE r.book_id = b.id);
