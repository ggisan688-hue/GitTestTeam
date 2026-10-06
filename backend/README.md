# Change Book Auth API

Flutter 앱은 이 REST API만 호출하며 PostgreSQL에 직접 접속하지 않습니다.

## 구성

`Flutter/Android → Spring Boot REST API → PostgreSQL`

- Java 17, Spring Boot 3.x, Gradle
- Flyway가 앱 전용 `change_book_users` 테이블을 생성합니다. 공용 DB의
  기존 `users` 테이블과 데이터는 읽거나 변경하지 않습니다.
- 비밀번호는 BCrypt 해시만 저장합니다.
- 로그인 성공 시 JWT access token을 반환합니다.

## 환경 변수 설정 (VS Code CMD)

실제 비밀번호나 JWT 시크릿을 파일에 저장하거나 Git에 커밋하지 마세요.

```cmd
set DB_HOST=project-db-campus.smhrd.com
set DB_PORT=3310
set DB_NAME=campus_26k_lgdx19_p3_2
set DB_USERNAME=campus_26k_lgdx19_p3_2
set DB_PASSWORD=YOUR_DB_PASSWORD
set JWT_SECRET=YOUR_LONG_RANDOM_SECRET_AT_LEAST_32_CHARACTERS
set JWT_EXPIRATION_MS=86400000
gradlew bootRun
```

`bootRun`은 웹 서버를 계속 실행하는 작업이므로 Gradle/VS Code에서
`EXECUTING`으로 남아 있는 것이 정상입니다. 아래 로그가 나오면 서버는
정상 시작된 것입니다.

```text
Tomcat started on port 8088 (http)
Started AuthApplication
```

서버를 종료할 때는 실행 중인 터미널에서 `Ctrl+C`를 한 번 누릅니다.

`.env.example`은 변수 이름만 보여 주는 예시입니다. 실행 전에 실제 값은 현재 CMD 세션 또는 안전한 배포 환경 변수에 설정하세요.

## API

- `POST /api/auth/signup` — `{ "username", "password", "nickname" }`
- `POST /api/auth/login` — `{ "username", "password" }`
- `GET /api/users/me` — `Authorization: Bearer <accessToken>`

에뮬레이터에서 백엔드를 실행할 때 Flutter의 API 주소는 `http://10.0.2.2:8088`을 사용합니다.
