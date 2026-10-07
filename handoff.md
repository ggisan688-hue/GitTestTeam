# ChangeBook 작업 인수인계

작성일: 2026-10-07

## 반영 완료

### 인증·비밀번호 재설정

- 새 migration: `V21__add_password_reset_security.sql`
- 이메일(선택값), `auth_version`, reset token/request-history 테이블을 추가했다. 기존 사용자·인증 데이터는 보존한다.
- `POST /api/auth/password-reset/request`, `POST /api/auth/password-reset/confirm`을 구현했다.
- 32바이트 난수 토큰의 SHA-256 해시만 저장하며, 만료·단일 사용·이전 토큰 폐기·이메일/IP 해시 rate limit을 적용한다.
- BCrypt로 비밀번호를 갱신하고 `auth_version`을 증가시켜 기존 JWT를 무효화한다.
- SMTP/reset URL/from은 환경 변수만 사용하며 토큰·비밀번호·SMTP 비밀을 로그에 남기지 않는다.
- Flutter 회원가입 이메일 전달, reset request 화면, `/reset-password?token=...` 새 비밀번호 화면을 추가했다.

### 도서 검색·목차

- 실제 로그의 PostgreSQL `lower(bytea)` 오류를 수정했다. 검색은 title/author/category PostgreSQL `ILIKE` 부분 일치로 동작한다.
- 기존 `GET /api/books/search`는 유지하고, `GET /api/books/search/page`가 `items/page/size/total/hasNext`를 반환한다.
- 검색 로그에는 검색어 원문이 아닌 hash·길이·결과 수·지연시간만 기록한다.
- 새 migration: `V22__mark_legacy_chapters_unverified.sql`.
- V5의 근거 없는 단일 챕터는 삭제하지 않고 `verified=false`로 보존한다. 챕터 API는 검증된 챕터만 반환한다.

### 독서방

- 새 migration: `V23__add_room_books_password_and_shared_progress.sql`.
- 기존 대표 도서를 `change_book_reading_room_books`에 안전하게 backfill하고, `current_book_id`, BCrypt `password_hash`, 방별 진행률 테이블을 추가했다.
- 방 생성은 서버와 Flutter 모두 정확히 한 권만 받는다.
- owner 전용: 도서 추가/삭제/순서/현재 도서 변경, 비밀번호 설정·해제.
- 마지막 도서 삭제·중복 도서·방 외 도서·소유권 위반은 서버에서 거부한다.
- 초대 코드 가입은 비밀번호를 member row 생성 전에 검증한다. `(room_id,user_id)` PK와 잠금으로 재시도·재가입을 안전하게 처리한다.
- 방별 nickname/profile image와 전역 프로필은 분리된다. 방별 진행률은 `(room_id,user_id,book_id)`로 개인 진행률과 분리된다.

### 공유 메모·실시간·스포일러

- 기존 metadata-only WebSocket(`/ws/reading-room-sync`)과 REST sync fallback을 유지했다. event에는 메모/댓글 원문이 없다.
- commit 뒤에만 event를 publish하며 Flutter `RoomSyncClient`는 event ID dedupe·재연결·REST fallback을 제공한다.
- 새 migration: `V24__add_shared_note_versions.sql`.
- shared note/comment에 version 및 room/book/position index를 추가했다.
- spoiler 판정은 viewer 자신의 `(room,user,book)` progress만 쓴다. 개인 progress·다른 회원 progress는 사용하지 않는다.
- 잠긴 note에서는 selected text/content/highlight color/comment count를 반환하지 않고, 댓글 API도 서버에서 차단한다.
- moderation 정책이 없으므로 방장도 타인의 공유 원본을 삭제할 수 없고 작성자만 삭제할 수 있다.

## 주요 파일

- `backend/src/main/java/com/aicamp/changebook/AuthApplication.java`
- `backend/src/main/java/com/aicamp/changebook/PasswordReset.java`
- `backend/src/main/java/com/aicamp/changebook/BookCatalog.java`
- `backend/src/main/java/com/aicamp/changebook/ReaderFeatures.java`
- `backend/src/main/java/com/aicamp/changebook/ReadingRooms.java`
- `backend/src/main/java/com/aicamp/changebook/ReadingRoomNotes.java`
- `backend/src/main/resources/db/migration/V21__add_password_reset_security.sql`
- `backend/src/main/resources/db/migration/V22__mark_legacy_chapters_unverified.sql`
- `backend/src/main/resources/db/migration/V23__add_room_books_password_and_shared_progress.sql`
- `backend/src/main/resources/db/migration/V24__add_shared_note_versions.sql`
- `backend/src/main/resources/db/migration/V25__complete_password_reset_schema.sql`
- `backend/src/main/resources/db/migration/V26__normalize_password_reset_hash_column_types.sql`
- `lib/repository/book_repository.dart`
- `lib/repository/ridi_auth_repository.dart`
- `lib/repository/reading_room_repository.dart`
- `lib/model/reading_room.dart`
- `lib/view/ridi/ridi_auth.dart`
- `lib/view/ridi/ridi_app.dart`
- `lib/view/ridi/reading_rooms_screen.dart`

## 환경 변수

`PASSWORD_RESET_TOKEN_TTL_MINUTES`, `PASSWORD_RESET_MAX_REQUESTS_PER_EMAIL`, `PASSWORD_RESET_MAX_REQUESTS_PER_IP`, `PASSWORD_RESET_RATE_LIMIT_WINDOW_MINUTES`, `PASSWORD_RESET_URL`, `PASSWORD_RESET_MAIL_ENABLED`, `SPRING_MAIL_HOST`, `SPRING_MAIL_PORT`, `SPRING_MAIL_USERNAME`, `SPRING_MAIL_PASSWORD`, `MAIL_FROM` 및 기존 `API_BASE_URL`, `JWT_SECRET`, DB/profile-upload 설정.

## 검증

- `backend\gradlew.bat test --no-daemon`: 성공.
- 개발 DB에서 Flyway V21 checksum repair 후 V23~V26 migration 적용, Hibernate schema validation 및 `/actuator/health` 응답을 확인했다.
- 변경 Dart 파일은 formatter로 구문 검증했다.
- `flutter analyze`는 이 PC의 Dart analysis server child process가 Windows 권한 거부(`CreateFile failed 5`)로 실패했다. SDK 경로는 `C:\flutter\bin\flutter.bat`이다.

## 외부 환경이 필요한 검증

1. PostgreSQL 백업 후 Flyway V21~V24 upgrade와 기존 row count/샘플 ID 보존 확인.
2. 계정 A/B의 방 비밀번호 실패·성공·재가입, 다중 도서, 방별 nickname/image/progress 확인.
3. A/B의 상이한 room progress에서 shared note/comment raw API redaction 확인.
4. WebSocket disconnect/reconnect, REST snapshot 보충, event dedupe 확인.
5. SMTP, Android emulator/배포 `API_BASE_URL`, profile upload provider 확인.
6. Windows 권한을 해결한 뒤 `flutter analyze`, `flutter test`, APK build 실행.

## 주의

- 기존 Flyway migration은 수정하지 않았다.
- `backend/bin/main`은 Gradle resource 출력물이며 소스 변경 검토 대상은 `backend/src/main/resources`다.
- 챕터 원본 근거 없이 `verified=true`를 만들지 않는다.
- 기존 사용자의 이메일을 임의 backfill하지 않는다.
