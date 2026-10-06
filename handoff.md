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

## 아직 완료해야 할 작업

1. 방 생성 화면에 방 닉네임 아래 갤러리 이미지 선택, 미리보기, 취소, 재시도 UI를 추가한다.
2. 기존 `ProfileImageStorage`를 재사용하는 방 멤버 프로필 업로드/삭제 API를 구현하고 Flutter repository와 연결한다.
3. 방 멤버 목록, 공유 노트, 공유 댓글 UI에서 `roomProfileImageUrl -> global profile -> 기본 이미지` fallback을 표시한다.
4. 내 서재의 `내 책장 / 교환독서`를 완성된 상단 탭 UI로 정리한다. 현재는 교환독서 화면을 같은 영역에 표시하는 전환 기반만 추가되어 있다.
5. 게스트가 인증이 필요한 책장/교환독서/마이 탭을 열 때 로그인 유도로 일관되게 처리한다. 로그아웃·401 시 사용자별 Room/책장 캐시 초기화도 실기기에서 점검한다.
6. `advanced_book_reader.dart`에 남아 있는 과거 공유 선택 코드와 dead-code analyzer 경고를 제거하고 widget/unit test를 추가한다.
7. 초대코드 가입 응답 계약을 `{ room, alreadyJoined }` envelope로 통일할지 결정하고 Flutter/서버를 함께 변경한다. 현재는 방 DTO에 `alreadyJoined` 필드를 포함하는 호환 방식이다.

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

- `backend\\gradlew.bat build --rerun-tasks`: 성공. 테스트 소스는 없어 `test NO-SOURCE`였다.
- `flutter test`: 성공, 4개 테스트 통과.
- 대상 Flutter 파일 `flutter analyze`: 컴파일 error는 없음. 기존 warning/info와 리더의 dead-code warning이 남아 있다.
- PostgreSQL 접속 정보, JWT 환경값, Android Emulator/adb가 이 환경에 없어 아래 실제 검증은 아직 하지 못했다.
  - Flyway V18/V19 적용
  - 계정 A/B 초대코드 가입/재가입 및 member row 중복 여부
  - `/api/reading-rooms/my` 실제 응답
  - 방 삭제 cascade 및 원본 개인 데이터 보존
  - 게스트/로그인/로그아웃/401 화면 흐름
  - 방 전용 프로필 이미지 업로드 및 fallback 표시

## 다음 실행 순서

1. 백엔드 재시작 후 Flyway V18, V19 적용 로그를 확인한다.
2. PostgreSQL에서 생성자 OWNER row와 참여자 MEMBER row를 확인한다.
3. Android Emulator에서 초대코드 가입, 재가입, 목록 즉시 반영, 방 삭제를 확인한다.
4. 방 전용 프로필 업로드 API/UI를 구현한 뒤 Flutter analyze/test, Spring build를 다시 실행한다.
