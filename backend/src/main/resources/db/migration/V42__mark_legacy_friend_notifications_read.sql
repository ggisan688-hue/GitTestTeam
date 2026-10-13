-- Friend relationships remain available, but friend-request notifications are
-- no longer part of the notification product. Preserve legacy rows for audit
-- history while ensuring they cannot leave a stale unread badge.
UPDATE change_book_notifications
SET is_read = TRUE
WHERE type LIKE 'FRIEND%'
  AND is_read = FALSE;
