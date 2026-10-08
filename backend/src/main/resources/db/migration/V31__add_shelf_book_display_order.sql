-- Keep the caller's selected-book order stable for shelf covers and detail.
-- Existing links are preserved and receive a deterministic legacy order.
ALTER TABLE change_book_shelf_books
    ADD COLUMN IF NOT EXISTS display_order INTEGER;

WITH ordered AS (
    SELECT shelf_id,
           book_id,
           ROW_NUMBER() OVER (
               PARTITION BY shelf_id
               ORDER BY created_at ASC, book_id ASC
           ) - 1 AS sequence
    FROM change_book_shelf_books
    WHERE display_order IS NULL
)
UPDATE change_book_shelf_books link
SET display_order = ordered.sequence
FROM ordered
WHERE link.shelf_id = ordered.shelf_id
  AND link.book_id = ordered.book_id;

ALTER TABLE change_book_shelf_books
    ALTER COLUMN display_order SET NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_change_book_shelf_books_display_order
    ON change_book_shelf_books (shelf_id, display_order);

CREATE INDEX IF NOT EXISTS ix_change_book_shelf_books_shelf_display_order
    ON change_book_shelf_books (shelf_id, display_order);
