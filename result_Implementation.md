# Change Book 구현 결과

작성일: 2026-09-30

## 구현 범위

Flutter, Spring Boot, PostgreSQL 기반 Change Book 앱에서 기존 로그인/JWT, 도서 목록과 상세, 본문 리더, 진행도, 최근 읽은 도서, 독서노트, 보기 설정 기능을 보존하면서 다음 기능을 추가·연결했다.

- 내 서재와 책장 CRUD, 책장 도서 추가·제거
- 도서 검색
- 친구 검색, 요청, 수락·거절, 삭제
- 교환독서 방 목록, 생성, 상세, 공개 참여, 비공개 코드 입장, 방장 관리
- 앱 내 알림과 알림 설정
- MY 페이지, 프로필 편집, 로그아웃, 회원 탈퇴
- 독서노트 메모 저장 lifecycle 안정화
- 더미 도서 재등장 차단

## 주요 백엔드 변경

### 교환독서와 사용자 기능

- `UserFeatures.java`: 프로필, 앱 내 알림, 알림 설정, 계정 탈퇴 API를 추가했다.
- `Friends.java`: 현재 JWT 사용자 기준의 친구 검색·요청·수락·거절·삭제와 알림 생성을 구현했다.
- `ReadingRooms.java`: 방 생성·수정·삭제, 공개/코드 입장, 멤버 강제 퇴장, 방장 위임, 입장 코드 재발급을 구현했다.
- `BookCatalog.java`: 제목·저자·카테고리 기반 서버 검색 API를 유지했다.

### DB migration

기존 Flyway migration은 수정하지 않았다.

- `V7__add_exchange_reading_indexes.sql`
  - 친구 관계와 교환독서 방 멤버 조회 인덱스를 추가했다.
- `V8__remove_legacy_demo_books.sql`
  - 과거 `V2`, `V4`가 삽입하던 아몬드, 불편한 편의점, 채식주의자 시드 도서를 제거한다.
  - 제목만으로 지우지 않고 제목·저자·설명·카테고리·표지 URL까지 일치하는 정확한 시드 지문만 대상으로 한다.
  - 본문, 진행도, 독서노트, 책장, 교환독서 방 연결이 있는 행은 삭제하지 않는다.

## Flutter 변경

### 서버 연동 화면

- `shelves_screen.dart`: 서버 책장 목록, 생성·수정·삭제, 상세, 책 추가·제거를 연결했다.
- `reading_rooms_screen.dart`: 서버 교환독서 방 목록과 상세 화면을 연결했다.
- `book_search_screen.dart`: debounce 검색과 책장 담기를 추가했다.
- `friends_screen.dart`: 서버 친구 기능을 연결했다.
- `server_notifications_screen.dart`: 서버 알림 목록, 읽음 처리, 알림 설정과 배지를 추가했다.
- `account_screen.dart`: 서버 프로필 편집, 로그아웃, 회원 탈퇴를 추가했다.

### 리더 메모 저장 안정화

- `advanced_book_reader.dart`
  - 메모 입력 다이얼로그를 별도 StatefulWidget으로 분리했다.
  - TextEditingController는 다이얼로그가 생성하고 dispose한다.
  - 빈 메모를 차단하고, 저장 중 버튼을 비활성화하며 진행 상태를 표시한다.
  - 저장 실패 시 다이얼로그를 유지하고 오류를 표시한다.
  - 저장 성공 시에만 다이얼로그를 한 번 닫고, 살아 있는 독서노트 BottomSheet에서 성공 메시지를 표시한다.
  - 다이얼로그·BottomSheet가 닫힌 뒤에는 해당 context로 Navigator 또는 ScaffoldMessenger를 호출하지 않는다.
- `book_viewmodel.dart`
  - 메모 API 완료 후 ViewModel이 dispose된 경우 노트 목록과 notifyListeners를 갱신하지 않도록 보호했다.
- `ridi_app.dart`
  - `RidiStore`와 `BookViewModel`의 단일 소유자를 `RidiAppState`로 변경했다.
  - 앱 루트에서 한 번만 생성하고 한 번만 dispose하도록 해 BottomSheet/Dialog가 중복 Provider를 소유하지 않게 했다.

## 메모 assertion 원인과 처리 흐름

기존 메모 저장은 다이얼로그가 닫히기 시작한 직후 controller를 dispose하고, BottomSheet의 비동기 흐름에서 ViewModel 갱신을 수행했다. 이 과정에서 Provider 의존 위젯이 deactivate되는 시점과 notifyListeners가 겹쳐 Flutter의 `_dependents.isEmpty` assertion이 발생할 수 있었다.

수정 후 흐름은 다음과 같다.

1. 메모 다이얼로그가 입력 controller, 로딩, 오류 상태를 소유한다.
2. 저장 시 API 호출을 한 번만 실행한다.
3. 성공한 경우 다이얼로그가 mounted인지 확인한 후 한 번만 pop한다.
4. BookViewModel이 서버의 최신 독서노트 목록을 조회해 갱신한다.
5. 독서노트 BottomSheet가 아직 mounted인 경우에만 성공 SnackBar를 표시한다.
6. 저장 중 뒤로가기로 UI가 닫히면 이후 API 완료가 닫힌 UI를 갱신하지 않는다.

## 더미 도서 재등장 조사 결과

원인은 Flutter fallback이 아니라 과거 Flyway `V2__create_change_book_books.sql`, `V4__seed_missing_sample_books.sql`의 시드 INSERT였다. 이 migration은 이미 적용된 파일이므로 수정하지 않았다.

현재 서버의 `GET /api/books` 응답은 운수 좋은 날만 포함했고, 아몬드·불편한 편의점·채식주의자는 포함하지 않았다. 수정 APK를 설치한 뒤 에뮬레이터 앱을 강제 종료·재실행해 전체 도서와 최근 읽은 도서 화면에서도 세 제목이 표시되지 않는 것을 확인했다.

## 검증 결과

- Spring Boot: `gradlew test` 성공
- Flutter: `flutter test` 성공, 4개 테스트 통과
- Flutter 정적 분석: 컴파일 오류 없음
- Android: debug APK 빌드 성공, emulator-5554 설치 성공
- 에뮬레이터: 앱 강제 종료·재실행 후 더미 도서 미표시 확인
- 에뮬레이터: 운수 좋은 날 리더 진입, 독서노트 BottomSheet와 기존 메모 목록 확인

## 남은 작업

`V8__remove_legacy_demo_books.sql`은 소스에 추가됐지만 이 작업 터미널에는 DB 접속 환경변수가 없어 Flyway를 실제 DB에 적용하지 못했다. 백엔드를 DB 환경변수와 함께 재시작하면 V8 migration이 자동 적용된다.

현재 `flutter analyze`에는 기존 코드의 warning/info가 남아 있다. 대표적으로 사용하지 않는 UI 클래스/import, 일부 async context 경고, `WillPopScope` deprecation 안내가 있다. 이번 변경으로 인한 분석 오류는 없다.
