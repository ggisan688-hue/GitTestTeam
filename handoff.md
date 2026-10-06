# 작업 인수인계

작성일: 2026-10-02

## 현재 반영된 작업

### 교환독서

- 방 만들기 대표 도서 목록은 서버 `GET /api/books`를 사용한다. 더미 도서 fallback은 사용하지 않는다.
- 방 만들기는 별도 `CreateReadingRoomScreen` route가 입력 controller를 소유한다. 성공 시 생성 방 DTO만 `pop`으로 반환하고, 부모가 목록 갱신 뒤 상세로 이동한다.
- `GET /api/reading-rooms/my`는 현재 JWT 사용자 기준으로 member 테이블을 조회한다. `OWNER`, 기존 `HOST`, `MEMBER`를 참여자로 처리한다.
- 초대코드 가입은 멱등 처리한다. 이미 가입한 사용자는 member row를 추가하지 않고 `200 OK`와 `alreadyJoined: true`가 포함된 방 DTO를 받는다.
- 방 생성 시 생성자는 같은 트랜잭션에서 `OWNER` member row로 저장된다.
- 방장에게만 상세의 초대코드와 재발급/방 삭제 UI가 보인다. 내 독서방 카드에서도 방장은 삭제를 실행할 수 있다.
- 초대코드는 서버에서 혼동하기 쉬운 문자를 제외한 `XXXX-XXXX` 형식으로 생성한다.
- `V18__backfill_reading_room_invite_codes.sql`은 기존 null/blank 초대코드를 보완한다. 서버 재시작 시 Flyway가 적용되어야 한다.

### 리더 데이터 분리

- `AdvancedBookReaderScreen`에 `ReaderContext`를 추가했다.
  - 일반 진입은 `ReaderContext.personal()`이며 개인 노트 API만 사용한다.
  - 독서방 진입은 `ReaderContext.readingRoom(roomId)`이며 해당 방의 공유 노트 API에 직접 저장한다.
  - 방 리더에서 개인 저장 후 공유 여부를 묻는 신규 흐름은 사용하지 않는다.
- 독서방 상세의 리더 진입은 `ReaderContext.readingRoom(room.id)`를 전달한다.
- 서버의 공유 노트 API는 멤버 여부 및 spoiler lock을 서버에서 검증한다.

### 게스트 시작

- `RidiGate`는 인증 준비 후 로그인 화면을 강제하지 않고 `RidiShell`로 진입한다.
- 홈에서 비로그인 상태에는 `로그인하세요` 진입 버튼과 게스트 안내를 표시한다.
- 비로그인 홈에서는 최근 읽은 책 및 통계 섹션을 숨긴다.

### 방 전용 프로필 기반

- 신규 migration: `backend/src/main/resources/db/migration/V19__add_reading_room_member_profile_image.sql`
  - `change_book_reading_room_members.room_profile_image_url` nullable 컬럼 추가.
- `RoomMember` 및 참여자 DTO에 `roomProfileImageUrl`을 추가했다.
- 공유 노트 응답은 방 멤버 이미지가 있으면 전역 프로필 이미지보다 우선 사용한다.

### 후속 정리 (2026-10-06)

- 방 생성 화면의 갤러리 이미지 선택/미리보기/취소·재시도와 서버 도서 선택 UI를 완료했다.
- 내 서재는 `내 책장 / 교환독서` 상단 탭으로 전환한다.
- 게스트가 내 서재(교환독서 포함) 또는 마이 탭을 열면 로그인 유도 대화상자를 표시한다. 홈의 도서 탐색은 게스트로 유지한다. 로그아웃 또는 임의 API의 401은 동일한 로그아웃 처리로 책/즐겨찾기 캐시를 비운다.
- 리더는 `ReaderContext`만 사용한다. 도달 불가능했던 개인 노트 후 독서방 선택 코드와 `_ShareRoomPicker`를 제거했다.
- 초대코드 가입 API(`POST /api/reading-rooms/join`, `join-by-code`)는 `{ room, alreadyJoined }` envelope를 반환한다. `alreadyJoined`는 더 이상 일반 방 DTO의 필드가 아니다.

## 아직 완료해야 할 작업

1. 실제 PostgreSQL/Flyway와 Android Emulator에서 로그인·로그아웃/401 후 사용자별 Room·책장 캐시 초기화를 검증한다.
2. 계정 A/B로 초대코드 가입·재가입을 수행해 `{ room, alreadyJoined }` 응답, member row 중복 방지, 목록 즉시 반영을 검증한다.
3. 방 삭제 cascade/개인 데이터 보존 및 방 전용 프로필 이미지 업로드·fallback을 실기기에서 검증한다.

## 수정 파일

- `lib/view/ridi/advanced_book_reader.dart`
- `lib/view/ridi/reading_rooms_screen.dart`
- `lib/view/ridi/ridi_app.dart`
- `lib/view/ridi/ridi_home.dart`
- `lib/view/ridi/shelves_screen.dart`
- `backend/src/main/java/com/aicamp/changebook/ReadingRooms.java`
- `backend/src/main/java/com/aicamp/changebook/ReadingRoomNotes.java`
- `backend/src/main/resources/db/migration/V18__backfill_reading_room_invite_codes.sql`
- `backend/src/main/resources/db/migration/V19__add_reading_room_member_profile_image.sql`

## 검증 결과 및 제한

- `backend\\gradlew.bat test`: 성공. 테스트 소스는 없어 `test NO-SOURCE`였다.
- `flutter test`: 성공, 5개 테스트 통과(초대 가입 envelope 파싱 테스트 포함).
- 대상 Flutter 파일 `flutter analyze`: error 없음. 기존 style/deprecation info와 `shelves_screen.dart`의 기존 unused warning은 남아 있고, 리더의 과거 공유 선택 dead code는 제거했다.
- PostgreSQL 접속 정보, JWT 환경값, Android Emulator/adb가 이 환경에 없어 아래 실제 검증은 아직 하지 못했다.
  - Flyway V18/V19 적용 및 새 초대 가입 envelope 실서버 응답
  - 계정 A/B 초대코드 가입/재가입 및 member row 중복 여부
  - `/api/reading-rooms/my` 실제 응답
  - 방 삭제 cascade 및 원본 개인 데이터 보존
  - 게스트/로그인/로그아웃/401 화면 흐름
  - 방 전용 프로필 이미지 업로드 및 fallback 표시

## 다음 실행 순서

1. 백엔드 재시작 후 Flyway V18, V19 적용 로그를 확인한다.
2. PostgreSQL에서 생성자 OWNER row와 참여자 MEMBER row를 확인한다.
3. Android Emulator에서 초대코드 가입, 재가입, 목록 즉시 반영, 방 삭제를 확인한다.
4. 계정 A/B 초대코드 재가입과 로그인 상태 전환을 실행하고 API/DB 결과를 기록한다.
