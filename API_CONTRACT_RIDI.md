# 책담(리디 UI 버전) — 서버 연결 명세서 v0.4

> 대상: 백엔드 팀 (Spring `:8088`, FastAPI `:8000`)
> 앱 쪽 기준: GitHub `main` 브랜치 (2026-09-29, 커밋 `0316f56` — 방 비밀번호·멤버 관리·여러 방 공유·밑줄·알림 보관·홈 통계) · APK `dist/chaekdam_v2.3.3-0929_release.apk`
> **이 문서의 숫자·규칙은 모두 지금 앱이 실제로 하는 동작 기준이다.** 바꾸고 싶으면 앱과 이 문서를 같이 고친다.
> 작성: 2026-09-26 · 수정: 2026-09-29 · 상태: **초안 — 4절의 빈 "결정" 칸(D1·D10·D13~D16)을 백엔드 팀이 채워서 돌려주세요**

이 문서는 **화면의 버튼 하나하나가 어떤 API를 부르는지**와 **주고받는 JSON**을 정리한 것이다.
리디 UI 버전은 지금 서버 없이 폰 메모리(`lib/view/ridi/ridi_store.dart` 의 `RidiStore`)로만 돈다.
연결은 `RidiStore` 의 메서드 안쪽을 API 호출로 바꾸는 방식이라, **이 문서의 API가 생기면 화면 코드는 거의 안 바뀐다.**

표기: **[기존]** 앱이 이미 이 형식으로 부르는 API (`lib/repository/` 에 있음) · **[수정]** 그 형식에 필드·규칙 추가 · **[신규]** 새 형식
※ 모든 API 는 팀 서버에서 구현 대상이다. 표기는 "앱 쪽 연결 코드가 이미 있는지"를 뜻한다. (옛 원본 서버 `fullstack_app` 은 분리·보관 — 2026-09-28)

---

## 1. 공통 규칙

| 항목 | 규칙 |
|---|---|
| 인증 | 로그인 응답의 `token` 을 모든 요청에 `Authorization: Bearer <token>` (기존과 같음) |
| 응답 형태 | 기존 `ApiResponse` 그대로: `{ "success": true, "message": null, "data": ... }` |
| 오류 형태 | `{ "success": false, "message": "사람이 읽을 문장", "code": "ROOM_FULL" }` — **`code` 필드 추가 요청** (앱이 문장이 아니라 코드로 분기) |
| 로그인 만료 | HTTP `401` → 앱이 로그인 화면으로 보냄. 다른 오류에 401 쓰지 않기 |
| 권한 없음 | HTTP `403` + `code` (예: `NOT_ROOM_MEMBER`, `NOT_ROOM_OWNER`, `SPOILER_LOCKED`, `ROOM_BLOCKED`, `WRONG_PASSWORD`) |
| ID | 서버는 숫자여도 됨. 앱은 모두 **문자열로 받아서** 씀 (`"12"`) |
| 날짜 | ISO-8601, 서버 시간대 포함 (`2026-09-26T13:45:00+09:00`). "3시간 전" 같은 표시는 앱이 계산 |
| 장·문장 번호 | 기존 API와 같게 **장은 1부터**, 문장은 챕터 API가 내려주는 `Line.lineNo` 값. (앱 내부는 0부터 — 변환은 앱이 함) |
| 페이지 번호 | **서버에 저장하지 않음.** 글자 크기·2단/1단에 따라 바뀌는 값이라 위치는 항상 `chapter + lineNo` |
| 목록 크기 | 지금은 한 번에 전부. 알림만 `?after=<id>&size=30` 페이지 나눔 권장 |

### 서버가 필요 없는 것 (만들지 않음)
보기 설정(글자 크기·행간·종이 색), 뷰어 2단/1단, 화면 켜짐 유지, 최근 검색어, 뷰어 "내 메모만 보기", 마지막에 쓴 펜(형광펜/밑줄) → **폰에만 저장**.
책 검색 → 책 목록을 받아서 앱이 거름 (책이 많아지면 `GET /api/books?q=` 추가).

---

## 2. 화면 · 버튼 → API 연결표

화면 번호는 코드 주석(`RIDI_...`)과 화면설계서의 번호와 같다.

| 화면 | 버튼 / 동작 | 앱 메서드 (`RidiStore`) | API | 상태 |
|---|---|---|---|---|
| RIDI_SPLASH_01 스플래시 | (없음) | — | — | 서버 불필요 |
| RIDI_LOGIN_01 로그인 | 로그인 | `login` | `POST /api/members/login` | [기존] |
| RIDI_SIGNUP_01 회원가입 | 가입하기 (중복 확인 버튼은 없음) | — | `POST /api/members/signup` (중복이면 오류 `code`) · 필요하면 `GET /api/members/check-email` · `check-username` | [기존] |
| RIDI_PW_01 비밀번호 찾기 | 재설정 메일 보내기 | — | `POST /api/members/password-reset` | [신규] |
| RIDI_MY_01 MY | 이름·소개 표시 | — | `GET /api/members/me` | [수정] 필드 추가 |
| RIDI_PROFILE_01 내 정보 | 저장 | `saveProfile` | `PATCH /api/members/me` | [신규] |
| RIDI_MY_01 MY | 로그아웃 | `logout` | (토큰 버림. 서버 호출 없음) | — |
| RIDI_HOME_01 홈 | 읽고 있는 책 · 방 소식 | `readingNow` · `rooms` | `GET /api/me/shelf` · `GET /api/rooms` | [신규] |
| 〃 | 이달의 추천 도서 | `monthlyPicks` | `GET /api/books/recommended` | [신규] |
| 〃 | 독서 통계(최근 7일·연속 일수) · 자주 읽는 책 | `weekMinutes` · `streakDays` · `topBooks` | `GET /api/me/stats` | [신규] |
| RIDI_HOME_01 · RIDI_SEARCH_01 | 검색 / 책장에 담기 | `addToShelf` | `GET /api/books` · `PUT /api/me/shelf/{bookId}` | [기존]+[신규] |
| RIDI_LIB_01 내 책장 | 목록 / 편집 → 삭제 | `shelf` · `removeFromShelf` | `GET /api/me/shelf` · `DELETE /api/me/shelf` | [신규] |
| RIDI_ROOMS_01 교환독서 | 방 목록 | `rooms` | `GET /api/rooms` | [신규] (제안서 있음) |
| RIDI_ROOM_CREATE_01 방 만들기 | 만들기 (최대 인원 +/− 2~50 · 입장 방식 시트 → 비밀번호 4자리) | `createRoom` | `POST /api/rooms` | [신규] |
| RIDI_ROOM_JOIN_01 코드 입장 | 코드 입력 즉시 미리보기 (자물쇠·정원·차단 표시) | `findByCode` | `GET /api/rooms/preview?code=` | [신규] |
| 〃 | 들어가기 (비밀번호 방이면 4자리 함께) | `joinRoom` | `POST /api/rooms/join` | [신규] |
| RIDI_ROOMS_02 방 메뉴 | 이름 바꾸기 / AI 바꾸기 / 스포일러 잠금 | `renameRoom` · `setRoomPersona` · `setRoomSpoilerLock` | `PATCH /api/rooms/{id}` | [신규] |
| 〃 (방장) | 최대 인원 +/− · 비밀번호 켜기/끄기/변경 (`RIDI_ROOMS_02 › 비밀번호 설정`) | `setRoomMaxMembers` · `setRoomPassword` | `PATCH /api/rooms/{id}` | [신규] |
| 〃 | 책 추가 | `addRoomBooks` | `PUT /api/rooms/{id}/books` | [신규] |
| 〃 | 방 나가기 (방장이면 가장 먼저 들어온 사람이 방장, 혼자면 방 삭제) | `leaveRoom` | `DELETE /api/rooms/{id}/members/me` | [신규] |
| RIDI_ROOM_MEMBERS_01 멤버 관리 (방장) | 방장 넘기기 | `transferOwner` | `PATCH /api/rooms/{id}` `{ ownerId }` | [신규] |
| 〃 | 내보내기 | `kickMember` | `DELETE /api/rooms/{id}/members/{memberId}` | [신규] |
| 〃 | 차단 / 차단 해제 | `blockMember` · `unblockMember` | `POST /api/rooms/{id}/blocks` · `DELETE /api/rooms/{id}/blocks/{memberId}` | [신규] |
| RIDI_READER_01 뷰어 | 본문 | — | `GET /api/books/{id}/chapters/{n}` | [기존] |
| 〃 | 페이지 넘김 (읽은 위치) | `setPage` | `PUT /api/books/{id}/progress` | [수정] `chapterReached` 응답 |
| RIDI_READER_03 문장 선택 | 어절 길게 누르고 끌기 → [형광펜 \| 밑줄] · 색 | `addNote` · `setNoteColor` · `setNotePenStyle` | `POST /api/books/{id}/memos` · `PATCH /api/memos/{id}` | [수정] |
| RIDI_READER_01 뷰어 | 책갈피 | `toggleBookmark` | `POST` / `DELETE /api/books/{id}/memos` (`noteType: bookmark`) | [수정] |
| 〃 | 문장 끝 말풍선 (방 메모) | `roomNotes` | `GET /api/rooms/{roomId}/books/{bookId}/memos` | [신규] |
| 〃 | 내 메모만 보기 (멤버·AI 말풍선 숨김) | `setOnlyMyNotes` | — (폰에만 저장) | 서버 불필요 |
| RIDI_MEMO_01 메모 쓰기 | 저장 + 공개 범위(이 책을 읽는 내 방 여러 개 / 나만 보기) | `updateMemo` · `setNoteRooms` | `PATCH /api/memos/{id}` | [수정] |
| RIDI_NOTE_01~03 독서노트 | 내 기록 목록 / 편집 → 삭제 | `notesOf` · `deleteNotes` | `GET /api/books/{id}/memos?mine=true` · `DELETE /api/memos` | [수정] |
| RIDI_ROOM_MEMO_01 방 메모 | 목록 · 멤버별 거르기 · 이 문장으로 | `roomNotes` · `isSpoiler` | `GET /api/rooms/{roomId}/books/{bookId}/memos` | [신규] |
| RIDI_COMMENT_01 댓글 | 목록 / 등록 / 내 댓글 삭제 | `commentsOf` · `addComment` · `deleteComment` | `GET` · `POST` · `DELETE /api/memos/{memoId}/comments` | [기존] 권한 규칙 추가 |
| RIDI_AI_01 AI 친구 | 캐릭터 목록 / 방에 적용 | `personas` · `setRoomPersona` | `GET /api/ai/personas` · `PATCH /api/rooms/{id}` | [기존]+[신규] |
| RIDI_AI_02 새 AI 친구 | 만들기 | `createPersona` | `POST /api/ai/personas` | [신규] |
| RIDI_NOTI_01 알림 | 목록 / 누르면 이동·읽음 / 모두 읽음 | `notifications` · `markRead` · `markAllRead` | `GET /api/notifications` · `POST .../{id}/read` · `POST .../read-all` | [신규] |
| 〃 | 밀어서 [보관] / 보관함 탭에서 [되돌리기] | `archiveNotification` · `unarchiveNotification` | `POST` · `DELETE /api/notifications/{id}/archive` | [신규] |
| 〃 | 밀어서 [삭제] (스낵바 되돌리기) | `deleteNotification` · `restoreNotification` | `DELETE /api/notifications/{id}` (되돌리기는 앱이 몇 초 기다렸다가 보냄) | [신규] |
| RIDI_NOTI_SET_01 알림 설정 | 토글 5개 | `setNoti` | `GET` · `PUT /api/me/notification-settings` | [신규] |

---

## 3. API 상세

### 3-1. 계정

**[신규] 비밀번호 재설정 메일**
```http
POST /api/members/password-reset
{ "email": "reader@team.dx" }
```
→ 항상 `200` (가입 안 된 이메일이어도 같은 응답 — 가입 여부를 알려주지 않기 위해). 메일 링크·새 비밀번호 화면은 웹으로.

**[수정] 내 정보** — `GET /api/members/me` 응답에 3개 추가
```json
{ "id": 12, "email": "...", "username": "...", "name": "박성필",
  "nickname": "박성필", "bio": "밤에 조금씩 읽어요", "avatar": "박" }
```

**[신규] 내 정보 수정**
```http
PATCH /api/members/me
{ "nickname": "성필", "bio": "주말에 몰아 읽어요", "avatar": "성" }
```
→ 바뀐 `Member`. 보낸 필드만 바꿈. `nickname` 2~12자 (앱이 먼저 막음), `bio` 0~40자, `avatar` 는 한 글자 (앱은 `박 지 상 하 미 도` 중에서 고름).

### 3-2. 책 · 내 책장 · 읽은 위치

**[신규] 내 책장**
```http
GET    /api/me/shelf                     → ShelfItem[]
PUT    /api/me/shelf/{bookId}            → ShelfItem   (이미 있으면 그대로 200)
DELETE /api/me/shelf   { "bookIds": [3, 5] }  → 204
```
```json
{ "book": { "id": 3, "title": "봄봄", "author": "김유정", "chapterCount": 12 },
  "addedAt": "2026-09-21T13:45:00+09:00", "lastOpenedAt": "2026-09-26T09:10:00+09:00",
  "progress": { "chapter": 2, "lineNo": 14 }, "chapterReached": 2, "done": false,
  "unreadRoomMemos": 27 }
```
`unreadRoomMemos` = 내가 들어간 방들에서 이 책에 새로 달린 메모 수 (책장 "안 본 이야기 N").

**[수정] 읽은 위치** — 기존 `PUT /api/books/{id}/progress { chapter, lineNo }` 응답에 추가
```json
{ "chapter": 2, "lineNo": 14, "chapterReached": 2 }
```
`chapterReached` = **지금까지 가장 멀리 읽은 장** (뒤로 가도 줄지 않음). 스포일러 판단의 기준.

**[신규] 홈 — 독서 통계** (RIDI_HOME_01 오른쪽 "독서 통계"·"자주 읽는 책")
```http
GET /api/me/stats
```
```json
{ "weekMinutes": [25, 40, 0, 35, 50, 20, 30],
  "streakDays": 4,
  "topBooks": [ { "bookId": 1, "title": "봄봄", "readMinutes": 190 },
                { "bookId": 2, "title": "운수 좋은 날", "readMinutes": 85 } ] }
```
- `weekMinutes` = 최근 7일 하루 독서 시간(분), **마지막이 오늘**. 앱은 막대 7개 + 합계로 보여줌
- `streakDays` = 오늘부터 거꾸로 하루도 안 빠지고 읽은 날 수 (0분인 날에서 끊김)
- `topBooks` = 읽은 시간 많은 순 최대 3권
- 읽은 시간은 서버가 쌓는다: 앱이 보내는 `PUT /api/books/{id}/progress` 사이 간격으로 계산하거나, 앱이 `{ minutes }` 를 같이 보냄 (→ D13)

**[신규] 홈 — 이달의 추천 도서**
```http
GET /api/books/recommended
```
```json
[ { "book": { "id": 4, "title": "메밀꽃 필 무렵", "author": "이효석", "chapterCount": 5 },
    "comment": "짧은 단편이라 한 주 동안 방에서 같이 읽기 좋아요." },
  { "book": { "id": 3, "title": "어린왕자", "author": "생텍쥐페리", "chapterCount": 1 },
    "comment": "어른이 되어 다시 읽으면 전혀 다른 문장이 보여요." } ]
```
첫 번째가 크게 보이는 추천, 나머지는 작은 카드. 누가 고르나(운영자 / 자동)는 → D14. 홈의 "읽고 있는 책"은 `GET /api/me/shelf` 에서 `done:false` 인 것, "방 소식"은 `GET /api/rooms` 로 앱이 만든다.

### 3-3. 방

방 API 전체. (처음 제안은 `docs/archive/ROOM_DESIGN.md` 4절 — 이 절이 그것을 대신한다.)

`Room` JSON — `spoilerLock`, `maxMembers`, `memberCount`, `hasPassword` 추가. **인원은 사람만 센다 (AI 친구는 정원에 안 들어감).**
`members` 는 **들어온 순서대로** (방장 승계 기준). 방장에게만 `password`·`blocked` 를 더 내려준다.
```json
{ "id": "k3x9", "name": "목요일 밤 독서회", "code": "RM-7K2M", "ownerId": 12,
  "members": [ {"memberId": 12, "name": "박성필", "ai": false, "owner": true,  "joinedAt": "2026-09-21T13:45:00+09:00"},
               {"memberId": 15, "name": "서성민", "ai": false, "owner": false, "joinedAt": "2026-09-22T09:00:00+09:00"},
               {"memberId": 3,  "name": "미나",   "ai": true,  "owner": false} ],
  "bookIds": [2], "personaId": "p3", "lastBookId": 2,
  "spoilerLock": true, "maxMembers": 6, "memberCount": 2,
  "hasPassword": false,
  "password": null,                                         // 방장에게만 (숫자 4자리 문자열 또는 null)
  "blocked": [ {"memberId": 18, "name": "윤강은"} ],          // 방장에게만
  "createdAt": "2026-09-21T13:45:00+09:00" }
```

| 요청 | 본문 | 응답 · 오류 |
|---|---|---|
| `GET /api/rooms` | — | 내가 속한 `Room[]` (최근에 들어간·만든 순) |
| `GET /api/rooms/{id}` | — | `Room` · 멤버가 아니면 `403 NOT_ROOM_MEMBER` |
| `POST /api/rooms` | `{ name, bookIds:[], personaId?, spoilerLock:true, maxMembers:6, password?:"1234" }` | `Room` (코드 서버가 생성). `name` 1~20자, `bookIds` 는 비어도 됨(나중에 추가), `maxMembers` **2~50 (기본 6)**, `password` 는 **숫자 4자리** 또는 생략(코드만으로 입장) |
| `GET /api/rooms/preview?code=RM-7K2M` **[신규]** | — | `{ name, bookTitles:[], memberCount, maxMembers, full:false, hasPassword:true, blocked:false, member:false }` · 없으면 `404 ROOM_NOT_FOUND`. `blocked` = 나를 차단한 방, `member` = 이미 들어가 있음 |
| `POST /api/rooms/join` | `{ code, password? }` | `Room` · 검사 순서: `404 ROOM_NOT_FOUND` → `403 ROOM_BLOCKED` → `409 ROOM_FULL` → `403 WRONG_PASSWORD`. **이미 멤버면 비밀번호 없이 그대로 `200`** |
| `PATCH /api/rooms/{id}` | `{ name?, personaId?\|null, spoilerLock?, maxMembers?, password?\|null, ownerId?, lastBookId? }` | `Room` · `lastBookId` 말고는 방장만 → 아니면 `403 NOT_ROOM_OWNER`. `lastBookId` 는 누구나(내 기준 값). 아래 규칙 참고 |
| `PUT /api/rooms/{id}/books` | `{ bookIds:[] }` | `Room` |
| `DELETE /api/rooms/{id}/members/me` | — | `204` · 방장 승계·방 삭제 규칙 아래 |
| `DELETE /api/rooms/{id}/members/{memberId}` **[신규]** | — | 내보내기 (방장). `204`. 코드를 알면 다시 들어올 수 있음. 방장 자신·AI 는 못 내보냄(`400`) |
| `POST /api/rooms/{id}/blocks` **[신규]** | `{ memberId }` | 차단 (방장). 멤버면 내보내고 차단 목록에 넣음 → `Room`. 다시 `join` 하면 `403 ROOM_BLOCKED` |
| `DELETE /api/rooms/{id}/blocks/{memberId}` **[신규]** | — | 차단 해제 (방장) → `Room`. 자동으로 다시 들어오지는 않음 |

**`PATCH /api/rooms/{id}` 규칙 (방장)**
- `maxMembers`: 2~50, **지금 사람 멤버 수보다 작게는 못 줄임** → `400 MAX_BELOW_MEMBERS` (앱의 − 버튼도 거기서 멈춤)
- `password`: 숫자 4자리(`^\d{4}$`) 로 걸기·바꾸기, `null` 로 풀기. 코드 재발급은 없음(D8) — 코드가 퍼지면 비밀번호를 건다
- `ownerId`: 방장 넘기기 (RIDI_ROOM_MEMBERS_01). 사람 멤버만 가능, 넘기면 나는 일반 멤버

**방 나가기 규칙 (D5)**: 방장이 나가면 **남은 사람 멤버 중 가장 먼저 들어온 사람(`joinedAt` 가장 이른)이 방장**이 된다. 사람 멤버가 나 혼자면 **방을 삭제**한다(방 메모도 같이). 방장이 바뀌면 남은 멤버에게 `room` 알림(선택).

방 코드 규칙: `RM-` + 4자, 헷갈리는 글자(`0 O 1 I`) 제외 → `ABCDEFGHJKLMNPQRSTUVWXYZ23456789`. 서버에서 중복 검사.

### 3-4. 형광펜 · 메모 · 책갈피 (기존 memos 확장)

기존 `memos` 에 칼럼을 더하는 쪽을 권한다. 이유: **댓글 API(`/api/memos/{memoId}/comments`)를 그대로 쓸 수 있음.**

`Memo` JSON — 굵은 글씨가 추가
```json
{ "id": 101, "bookId": 2, "chapter": 1, "lineNo": 4,
  "noteType": "highlight",            // ← 추가: highlight | bookmark
  "kind": "text",                     //   기존 칼럼. 책담은 항상 text (손글씨 ink 없음)
  "phrase": "뒤통수를 긁고, 나이가 찼으니", // ← 추가: 형광펜이 걸린 어절들 (책갈피는 장 제목)
  "wordFrom": 2, "wordTo": 5,         // ← 추가: 문장을 공백으로 나눈 어절 번호(0부터), 형광펜 범위
  "color": 0,                         // ← 추가: 0~4 (노랑·초록·보라·파랑·분홍)
  "penStyle": "highlight",            // ← 추가: highlight(형광펜 배경) | underline(색 밑줄)
  "roomIds": ["k3x9", "p7q2"],        // ← 추가: 공유한 방들. [] = 나만 보기
  "text": "반전 ㅋㅋ 사람 키 얘기가 아니었네",
  "memberId": 12, "author": "박성필", "mine": true, "ai": false,
  "spoiler": false, "commentCount": 2,
  "createdAt": "2026-09-24T21:10:00+09:00" }
```

| 요청 | 본문 | 비고 |
|---|---|---|
| `POST /api/books/{bookId}/memos` [수정] | `{ noteType, chapter, lineNo, wordFrom, wordTo, phrase, color, penStyle, text?, roomIds:[] }` | 방에서 읽는 중이면 앱이 `roomIds:[그 방]` 을 넣음 (기본 = 방에 공유, D2). `text` 0~1500자 (형광펜·밑줄만 남겨도 됨) |
| `PATCH /api/memos/{id}` [신규] | `{ text?, color?, penStyle?, roomIds? }` | 내 것만. `roomIds` 는 **통째로 바꿈** — `[]` = 나만 보기. 넣는 방은 모두 **내가 멤버이고 이 책이 있는 방**이어야 함 → 아니면 `403 NOT_ROOM_MEMBER` / `400 BOOK_NOT_IN_ROOM` |
| `GET /api/books/{bookId}/memos?mine=true` [수정] | — | 독서노트 = **내 것만** (공유 여부 무관) |
| `DELETE /api/memos` [신규] | `{ ids:[101,102] }` | 여러 개 한 번에 (독서노트 편집). 내 것만, 댓글도 같이 삭제 |
| `DELETE /api/books/{bookId}/memos/{id}` | — | [기존] 한 개 삭제 — 그대로 둬도 됨 |

책갈피: `noteType: "bookmark"`, `roomIds` 는 항상 `[]`, 위치는 그 페이지 첫 문장의 `chapter`·`lineNo`.

형광펜 범위: 한 문장 안에서 **길게 누른 어절 ~ 끌어서 놓은 어절** (`wordFrom`~`wordTo`). 한 문장에 여러 개 가능, 내 형광펜끼리는 겹치지 않게 앱이 막음. 문장을 넘어가는 선택은 아직 없음 (→ D12).

펜 모양: `penStyle` 은 `noteType: "highlight"` 안의 모양 구분일 뿐이다 (밑줄도 메모·댓글·방 공유가 똑같이 됨). 기존 데이터는 `"highlight"` 로 채운다. 펜 메뉴의 [형광펜 | 밑줄] 을 바꾸면 바로 `PATCH { penStyle }`.

여러 방 공유(D3): 메모 창(RIDI_MEMO_01)에서 **이 책을 읽는 내 방들**을 칩으로 여러 개 켤 수 있다. 저장하면 `PATCH { roomIds }`. 테이블은 `memo_rooms(memo_id, room_id)` 연결 테이블을 권한다. 방에서 나가거나 방이 삭제되면 그 방만 `roomIds` 에서 빠진다(메모는 남음). 댓글은 메모 하나에 달린다 — **공유한 방들이 댓글을 같이 본다** (→ D15).

### 3-5. 방 메모 (핵심)

```http
GET /api/rooms/{roomId}/books/{bookId}/memos?chapter=2     (chapter 생략 = 책 전체)
```
→ `Memo[]` — 이 방에 공유된 메모 전부 (`roomIds` 에 이 방이 있는 것: 나 + 멤버 + 방 AI), `chapter`→`lineNo` 순.

**서버가 계산할 것**
- `mine` : 요청한 사람이 쓴 것인지
- `spoiler` : **요청한 방**(`{roomId}`)의 `spoilerLock == true` 이고, 남의 메모이고, `memo.chapter > 내 chapterReached` 이면 `true` (장 단위, D4). 같은 메모도 여러 방에 공유됐으면 방마다 다를 수 있음
  → 이때 **`text` 와 `phrase` 를 빈 문자열로** 내려준다 (앱은 자물쇠만 보여줌. 기존 규칙과 같음)
- `commentCount`
- 방 멤버가 아니면 `403 NOT_ROOM_MEMBER`

### 3-6. 댓글 [기존] + 권한 규칙

`GET/POST/DELETE /api/memos/{memoId}/comments` 는 그대로 쓴다. `Comment` JSON: `id, memoId, author, ai, mine, text, createdAt`. (기존의 `imageUrl` 은 책담에서 안 씀 — 사진 댓글 없음)

추가 규칙
- 메모가 방에 공유된 것이면 **공유한 방들 중 한 곳이라도 멤버면** 읽기·쓰기 (아니면 `403 NOT_ROOM_MEMBER`)
- 나에게 스포일러인 메모에는 댓글 읽기·쓰기 불가 (`403 SPOILER_LOCKED`)
- 댓글 1~300자. 삭제는 내 댓글만

### 3-7. AI 독서 친구

- `GET /api/ai/personas` [기존] 응답에 `tone`(말투), `intro`(한 줄 소개), `sample`(예시 문장), `custom`(내가 만든 것인지) 추가
- `POST /api/ai/personas` [신규] `{ name, tone: "감성적|분석적|유머러스|차분함", intro }` → `Persona` (만든 사람만 보임). `name` 1~10자, `intro` 0~40자 (비면 앱이 "○○ 말투의 AI 독서 친구")
- 방 AI 지정은 `PATCH /api/rooms/{id} { personaId }` — 기존 사용자별 `PUT /api/ai/persona` 대신
- AI 메모 생성(FastAPI)은 **방 단위**로: 방 멤버 누군가 그 장을 읽으면 그 장에 AI 메모를 1~2개 남김 → `Memo` 로 저장 (`ai:true`, `roomIds:[그 방]`, `penStyle:"highlight"`). 이때 알림 발생

### 3-8. 알림 [신규]

```http
GET    /api/notifications?archived=false&after=<id>&size=30   → Notification[] (최신순. archived=true 면 보관함)
POST   /api/notifications/{id}/read            → 204
POST   /api/notifications/read-all             → 204   (보관 안 한 것만)
POST   /api/notifications/{id}/archive         → 204   보관 (읽음도 같이 처리)
DELETE /api/notifications/{id}/archive         → 204   보관함 → 전체로 되돌리기
DELETE /api/notifications/{id}                 → 204   삭제 (내 알림만)
GET    /api/me/notification-settings           → Settings
PUT    /api/me/notification-settings           → Settings
```
```json
{ "id": "m3", "kind": "comment",            // comment | room | ai
  "title": "내 메모에 댓글이 달렸어요",
  "body": "운수 좋은 날 1장 · 문장 4 · 서성민 \"나도 여기서 빵 터짐\"",
  "createdAt": "2026-09-25T10:00:00+09:00", "read": false,
  "archived": false,                        // ← 추가: 보관함에 있는지
  "roomId": "k3x9", "bookId": 2, "memoId": 101 }
```
화면(RIDI_NOTI_01): 위 탭 **전체 / 보관함**. 알림을 왼쪽으로 밀면 전체 탭은 [보관]·[삭제], 보관함 탭은 [되돌리기]·[삭제].
삭제는 스낵바 "되돌리기"가 있어서 앱이 **스낵바가 닫힌 뒤에** `DELETE` 를 보낸다 (서버에 되살리기 API 는 필요 없음).
하단 탭의 안 읽은 알림 점은 **보관 안 한 것만** 센다.
```json
{ "roomMemo": true, "comment": true, "ai": true, "newMember": false, "quietHours": false }
```
앱 토글과 짝: 방 메모 알림=`roomMemo` · 댓글 알림=`comment` · AI 독서 친구 알림=`ai` · 새 멤버 입장=`newMember` · 방해 금지(22:00~08:00)=`quietHours`. 기본값도 위와 같음.

알림을 누르면 앱이 하는 일: `comment` → 그 메모의 댓글 창, `room`·`ai` → 그 방에서 그 책 열기.

**언제 만드나**
| kind | 받는 사람 | 조건 |
|---|---|---|
| `comment` | 메모 쓴 사람 | 내 메모에 남이 댓글 |
| `room` | 방 멤버 전원(본인 제외) | 새 멤버 입장 (`newMember` 켠 사람만) |
| `ai` | 방 멤버 전원 | 방 AI가 메모를 남김 |
| (방 메모) | 방 멤버 전원(본인 제외) | 멤버가 방에 메모 공유 (`roomMemo`) — 많으면 묶어서 "새 메모 5개" |

**중요: 알림 본문이 스포일러를 흘리면 안 됨.** 받는 사람 기준으로 스포일러면 본문을 "2장 · 아직 안 읽은 장이라 내용은 가려 뒀어요" 로.
푸시(FCM)는 2단계. 1단계는 앱이 열릴 때 목록만 가져옴.

---

## 4. 결정 사항 · 결정 필요

D3~D8 은 **2026-09-29 기획(사용자)이 정함** — 앱이 이미 그렇게 동작한다. 나머지 빈칸은 백엔드 팀이 채워 주세요 (그전까지는 "앱의 지금 동작" 그대로).

| # | 질문 | 앱의 지금 동작 | 결정 |
|---|---|---|---|
| D1 | 메모를 기존 `memos` 확장으로 할지, `notes` 새 테이블로 할지 | 확장 전제로 작성 | |
| D2 | 방에서 쓴 메모의 기본 공개 범위 | **방에 공유** (메모 창에서 다른 방 추가·"나만 보기" 로 바꿀 수 있음) | 지금 동작 그대로 (09-29) |
| D3 | 한 메모를 여러 방에 공유할 수 있나 | **여러 방** (`roomIds`) — 이 책을 읽는 내 방들 중에서 고름 | ✅ 여러 방 (09-29) |
| D4 | 스포일러 기준을 "장"으로 할지 "문장"까지 볼지 | 장 단위 (`chapterReached`), 보고 있는 방의 잠금 설정 기준 | ✅ 장 단위 (09-29) |
| D5 | 방장이 나가면 | 가장 먼저 들어온 사람이 방장, 사람이 혼자면 방 삭제. 나가기 전에 멤버 관리에서 직접 넘길 수도 있음 | ✅ 먼저 들어온 순 승계 (09-29) |
| D6 | 정원 기본값·최대값 | 기본 6, **2~50** (+/− 버튼, AI 제외·사람만). 방장이 방 메뉴에서 바꿈(지금 인원 아래로는 못 줄임) | ✅ 2~50 (09-29) |
| D7 | 멤버 강퇴 기능 | 방장이 **내보내기**(다시 들어올 수 있음)·**차단**(못 들어옴)·차단 해제 | ✅ 있음 (09-29) |
| D8 | 방 코드 재발급(유출 시) | 재발급 없음. 대신 **방 비밀번호(숫자 4자리)** 걸기·바꾸기·풀기 | ✅ 비밀번호로 대신 (09-29) |
| D9 | 알림 보관 기간 | 무제한 (지우는 건 사용자가 직접, 보관함은 따로) | 지금 동작 그대로 (09-29) |
| D10 | 비밀번호 재설정 링크 → 어디서 새 비밀번호를 받나 (웹 페이지?) | 앱은 "메일 보냈어요" 까지만 | |
| D11 | 새 AI 친구: 만든 사람만 쓰나, 방 멤버 모두 쓰나 | 만든 사람 목록에만 | 지금 동작 그대로 (09-29) |
| D12 | 형광펜이 여러 문장에 걸치게 할지 | 한 문장 안에서만 (어절 범위) | 지금 동작 그대로 (09-29) |
| D13 | 독서 시간(홈 통계)을 어떻게 잴까 | 시연 숫자 고정 | |
| D14 | 이달의 추천 도서는 누가 고르나 (운영자 입력 / 자동) | 시연 2권 고정 | |
| D15 | 여러 방에 공유한 메모의 댓글: 방끼리 같이 볼지, 방마다 따로일지 | 메모 하나에 댓글 한 묶음 (같이 봄) | |
| D16 | 방 비밀번호 저장 방식 | 앱은 방장 설정 화면·코드 안내 팝업에서 번호를 보여줌 → 서버는 방장에게만 내려줌. 해시로 저장하면 방장도 못 봄(화면 수정 필요) | |

---

## 5. 앱 쪽 연결 순서 (참고)

1. `lib/repository` 에 없는 API(방·알림·책장·내 정보 수정)는 이 명세에 맞춰 **새 파일을 추가**한다 (2026-09-28 부터 명세 기준으로 추가·수정 가능)
2. 기존 API부터: 로그인·가입 → 책 목록·본문 → 읽은 위치 → 댓글
3. 그다음 신규: 방(비밀번호·멤버 관리 포함) → 방 메모 → 메모 공개 범위(여러 방) → 알림(보관·삭제) → 홈 통계·추천
4. `RidiStore` 메서드는 이름을 그대로 두고 안쪽만 API 호출로 바꾼다. 각 화면에 로딩·오류·빈 화면 상태를 붙인다
5. 시연용 더미 데이터(`_seed`)·더미 계정은 서버 연결 후 지운다
6. 코드 입장의 비밀번호 비교는 지금 앱이 직접 한다 → 서버 연결 후에는 `join` 의 `403 WRONG_PASSWORD` 로만 판단

## 6. 시연 데이터로 확인하는 법 (APK)

**더미 계정 5명** — 아이디 = 이름, 비밀번호 모두 `1234`: 김기산 · 서성민 · 손지유 · 윤강은 · 박성필.
계정마다 들어간 방·내 메모·댓글·알림이 다르다. 그 밖의 아이디(빈칸 포함)는 박성필로 들어간다. (앱 전용 — 서버 계정 아님)

| 방 | 코드 | 방장 | 멤버 | 특징 |
|---|---|---|---|---|
| 목요일 밤 독서회 | `RM-7K2M` | 박성필 | 서성민 · 손지유 · AI 미나 | 윤강은 **차단**됨, 스포일러 잠금 |
| Thursday Club | `RM-DPZT` | 김기산 | 윤강은 · 박성필 · AI 하루 | 책 3권 |
| 주말 고전 읽기 | `RM-8QHN` | 손지유 | 김기산 | **비밀번호 1234**, 정원 8 |

- 박성필 → 내 서재 → 교환독서 → **목요일 밤 독서회** → 문장 끝 말풍선(서성민·손지유·미나) → 방 메모. 2장 메모는 **자물쇠**(스포일러)
- 뷰어 아래 **내 메모만** → 멤버 말풍선이 숨음
- 문장 길게 누르기 → [형광펜 | 밑줄]·색 → 메모 → 공개 범위에서 **목요일 밤 독서회 + Thursday Club** 두 방 켜기 → Thursday Club 에서도 보임
- 방 메뉴(⋯) → 방장만 보이는 **최대 인원 +/−** · **비밀번호** · 멤버 **[관리]** → 내보내기 / 차단 / 차단 해제(윤강은) / 방장 넘기기
- 코드로 입장 → `RM-8QHN` → 비밀번호 칸 → `0000` 오류, `1234` 입장
- 윤강은으로 로그인 → `RM-7K2M` 입력 → "이 방에는 들어갈 수 없어요"(차단)
- 알림 → 왼쪽으로 밀기 → [보관]·[삭제](되돌리기) → 보관함 탭

---

변경 이력
- v0.4 (2026-09-29) **기획 결정 반영(D2~D9·D11·D12) + 새 화면 API**: 메모 `roomId` → `roomIds`(여러 방 공유)·`penStyle`(형광펜/밑줄), 스포일러는 요청한 방 기준(장 단위), 정원 2~50·방 비밀번호(숫자 4자리, `hasPassword`·방장에게만 `password`·`blocked`)·`join` 오류 `ROOM_BLOCKED`/`WRONG_PASSWORD`·검사 순서, 멤버 내보내기·차단·해제·방장 넘기기(`ownerId`), 방장이 나가면 가장 먼저 들어온 사람이 방장(`joinedAt`)·혼자면 방 삭제, 알림 `archived`·보관/되돌리기/삭제 API, 홈 `GET /api/me/stats`·`GET /api/books/recommended`, 새 결정 필요 D13~D16, 시연 데이터를 더미 계정 5명 기준으로
- v0.3 (2026-09-28) **지금 앱 기준으로 맞춤**: 정원 2·4·6·8·12(기본 6, 사람만), 입력 길이(방 이름 20·메모 1500·댓글 300·닉네임 2~12·소개 40·AI 이름 10), 연결표 화면 번호(ROOMS_02·READER_03·SEARCH_01), 가입은 중복 확인 버튼 없음, 댓글 `imageUrl`·메모 `ink` 안 씀, 알림 설정 토글↔필드 짝, 방 목록·방 조회 API(3-3), 표기 뜻, 앱 기준 `main`/`v2.3.3-ridi` (닉네임 2~12자 검사 추가)
- v0.2 (2026-09-27) 형광펜 어절 범위(`wordFrom`·`wordTo`) 추가, D12
- v0.1 (2026-09-26) 초안 — 방 메모·댓글·스포일러·알림 이동·비밀번호 찾기 화면 추가와 함께 작성
