# ChangeBook 운영 배포 가이드

이 문서는 실제 비밀값을 포함하지 않는다. 운영 배포에는 `api.example.com`을 실제 도메인으로, 모든 `CHANGE_ME` 값을 배포 플랫폼의 secret으로 바꾼다.

## 권장 구조

```
Release APK ── HTTPS/WSS ── api.example.com (Caddy) ── Spring Boot ── private PostgreSQL
                                      └────────────── persistent profile-image volume
```

Docker를 실행할 수 있는 단일 VM과 관리형 PostgreSQL을 권장한다. 현재 저장소에 기존 클라우드, Kubernetes, DNS, CI 배포 흔적은 없다. 이 조합은 TLS 자동 갱신과 운영 복잡도의 균형이 좋다. 트래픽/고가용성이 커지면 관리형 컨테이너 서비스와 object storage로 옮긴다.

## 운영 DB

1. PostgreSQL 15 이상 관리형 인스턴스를 private network에 생성한다. 공용 `5432` 포트는 열지 않는다.
2. `changebook_app`처럼 앱 전용 사용자를 만들고, 해당 DB에만 필요한 권한을 준다. 관리자 계정을 앱에 사용하지 않는다.
3. TLS를 요구하고 `DB_SSLMODE=require`을 secret 환경에 넣는다.
4. 배포 전에 암호화된 DB 백업과 복구 점검을 수행한다.
5. 배포 시 순서는 **백업 → Flyway migration → API 교체 → `/actuator/health` 확인 → APK smoke test**다. 파괴적 변경은 expand/contract migration으로 두 릴리스 이상에 나눈다.

Flyway는 앱 시작 중 `V1`부터 순서대로 실행되고 JPA는 `validate`만 수행한다. 실패한 migration은 DB를 고친 뒤 Flyway 상태를 확인하고 재시도한다. migration을 운영 DB에 수동으로 임의 실행하지 않는다.

## VM, DNS, TLS

1. `api.example.com` A/AAAA 레코드를 VM 공인 IP로 설정한다.
2. VM 방화벽은 TCP `80`, `443`만 public으로 허용한다. `8088`과 DB 포트는 public에 열지 않는다.
3. 호스트에서 `deploy/.env.production.example`을 복사해 `.env.production`을 만들고, secret manager/배포 환경에서 값을 주입한다.
4. `deploy`에서 `docker compose up -d --build`를 실행한다. Caddy는 DNS가 준비된 경우 Let's Encrypt 인증서를 발급·갱신하며 HTTP를 HTTPS로 리다이렉트한다.
5. 외부망에서 `curl --fail https://api.example.com/actuator/health`를 확인한다. 응답은 상태만 노출해야 한다.

WebSocket을 사용하므로 proxy는 Upgrade를 지원해야 한다. 제공된 Caddy 설정은 이를 지원한다. JWT가 WebSocket query string에 포함되는 현재 프로토콜은 proxy access log에 기록하지 말고, 이후 short-lived socket token 또는 header/subprotocol 인증으로 교체하는 것이 권장된다.

## 환경 변수

| 변수 | 주입 위치 | 비밀 |
|---|---|---|
| `SPRING_PROFILES_ACTIVE=prod` | API 컨테이너 | 아니오 |
| `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USERNAME` | API 컨테이너 secret/env | 일부 |
| `DB_PASSWORD` | secret manager | 예 |
| `DB_SSLMODE=require` | API 컨테이너 | 아니오 |
| `JWT_SECRET` | secret manager | 예 |
| `JWT_EXPIRATION_MS` | API 컨테이너 | 아니오 |
| `PROFILE_UPLOAD_DIR` | API 컨테이너/volume | 아니오 |
| `CORS_ALLOWED_ORIGIN_PATTERNS` | API 컨테이너 | 아니오 |
| `API_DOMAIN` | Caddy 컨테이너 | 아니오 |

## APK

운영 APK에는 반드시 실제 HTTPS API를 컴파일 타임에 넣는다.

```powershell
flutter build apk --release --dart-define=API_BASE_URL=https://api.example.com
```

`10.0.2.2`는 Android emulator에서만, `localhost`는 개발 PC에서만 사용한다. 실제 기기 로컬 개발은 `--dart-define=API_BASE_URL=http://<PRIVATE_LAN_IP>:8088`로 **debug 빌드에 한정**한다. release 빌드는 HTTPS URL이 없으면 시작 시 실패한다.

release 서명에는 Git 미추적 `android/key.properties`가 필요하다.

```properties
storeFile=C:\secure\changebook-release.keystore
storePassword=CHANGE_ME
keyAlias=changebook
keyPassword=CHANGE_ME
```

keystore와 이 파일은 secret manager 또는 안전한 개발자 장비에만 둔다. APK 공유 전 실제 기기에서 로그인, 방 CRUD, 프로필 업로드, 토큰 만료, 네트워크 단절을 확인한다.

## 운영 점검

- `docker compose ps`, `docker compose logs --tail=200 api`로 프로세스를 확인한다. Authorization/JWT/비밀번호를 로그에 출력하지 않는다.
- `/actuator/health`는 DB 연결을 포함한 health 상태만 제공한다. `info`에는 비밀값을 넣지 않는다.
- 프로필 이미지는 현재 persistent Docker volume에 저장된다. 컨테이너 임시 디스크를 사용하지 않으며, 정기 백업 또는 S3 호환 object storage 이전 계획이 필요하다.
- 현재 프로필 이미지 URL은 공개 static 경로다. 개인정보 정책상 비공개가 필요하면 인증 다운로드 endpoint 또는 signed URL로 교체한 뒤 public path를 닫는다.
- 앱 JWT는 현재 SharedPreferences에 저장된다. 출시 전 `flutter_secure_storage`로 이전하는 것을 권장한다.

## 이 저장소에서 수행한 검증

- `backend\\gradlew.bat clean test bootJar --no-daemon` 성공. 현재 backend 테스트 소스는 없다.
- `flutter test` 성공 (6 tests).
- `flutter build apk --debug --dart-define=API_BASE_URL=https://api.example.invalid`로 debug APK 컴파일을 확인했다.
- release APK는 실제 HTTPS API와 Git 미추적 release keystore가 있어야 한다. 둘 다 이 작업 환경에 제공되지 않아 생성·설치·외부 네트워크 smoke test는 수행하지 않았다.
- Docker/Caddy 실행, DNS/TLS 발급, 운영 PostgreSQL migration은 실제 서버·도메인·secret 권한이 필요하므로 아직 실행하지 않았다.
