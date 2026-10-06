package com.aicamp.changebook;

import io.jsonwebtoken.Claims;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;
import jakarta.persistence.*;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.http.HttpStatus;
import org.springframework.http.HttpMethod;
import org.springframework.http.ResponseEntity;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;
import org.springframework.security.web.AuthenticationEntryPoint;
import org.springframework.security.web.access.AccessDeniedHandler;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.stereotype.Component;
import org.springframework.stereotype.Service;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.filter.OncePerRequestFilter;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.slf4j.MDC;
import com.fasterxml.jackson.databind.ObjectMapper;

import javax.crypto.SecretKey;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.Date;
import java.util.Map;
import java.util.Optional;
import java.util.List;
import java.util.Arrays;
import java.util.stream.Collectors;
import java.util.UUID;

@SpringBootApplication
public class AuthApplication {
  public static void main(String[] args) {
    SpringApplication.run(AuthApplication.class, args);
  }

  @Bean PasswordEncoder passwordEncoder() { return new BCryptPasswordEncoder(); }

  @Bean
  CorsConfigurationSource corsConfigurationSource(
      @Value("${app.cors.allowed-origin-patterns:}") String allowedOrigins) {
    CorsConfiguration configuration = new CorsConfiguration();
    configuration.setAllowedOriginPatterns(originPatterns(allowedOrigins));
    configuration.setAllowedMethods(List.of("GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"));
    configuration.setAllowedHeaders(List.of("Authorization", "Content-Type", "X-Request-ID"));
    configuration.setExposedHeaders(List.of("X-Request-ID"));
    configuration.setAllowCredentials(false);
    configuration.setMaxAge(3600L);
    UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
    source.registerCorsConfiguration("/api/**", configuration);
    return source;
  }

  static List<String> originPatterns(String configured) {
    return Arrays.stream(configured.split(","))
        .map(String::trim).filter(value -> !value.isEmpty()).collect(Collectors.toList());
  }

  @Bean
  SecurityFilterChain securityFilterChain(
      HttpSecurity http, JwtFilter jwtFilter, SecurityErrorHandler securityErrors) throws Exception {
    return http.csrf(csrf -> csrf.disable())
        .cors(cors -> {})
        .exceptionHandling(errors -> errors
            .authenticationEntryPoint(securityErrors)
            .accessDeniedHandler(securityErrors))
        .sessionManagement(session -> session.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
        .authorizeHttpRequests(auth -> auth
            .requestMatchers("/actuator/health", "/actuator/health/**").permitAll()
            .requestMatchers("/api/auth/**").permitAll()
            .requestMatchers("/uploads/profiles/**").permitAll()
            .requestMatchers("/ws/**").permitAll()
            .requestMatchers("/api/books/favorites", "/api/books/*/favorite", "/api/books/*/favorite-status").authenticated()
            .requestMatchers(HttpMethod.GET, "/api/books", "/api/books/*").permitAll()
            .anyRequest().authenticated())
        .addFilterBefore(jwtFilter, UsernamePasswordAuthenticationFilter.class)
        .build();
  }
}

@Entity
@Table(name = "change_book_users")
class AppUser {
  @Id @GeneratedValue(strategy = GenerationType.IDENTITY) Long id;
  @Column(nullable = false, unique = true, length = 20) String username;
  @Column(name = "password_hash", nullable = false, length = 255) String passwordHash;
  @Column(nullable = false, length = 50) String nickname;
  @Column(name = "created_at", nullable = false) Instant createdAt;
  @Column(name = "updated_at", nullable = false) Instant updatedAt;

  @PrePersist void onCreate() { createdAt = updatedAt = Instant.now(); }
  @PreUpdate void onUpdate() { updatedAt = Instant.now(); }
}

interface UserRepository extends JpaRepository<AppUser, Long> {
  Optional<AppUser> findByUsername(String username);
  boolean existsByUsername(String username);
  boolean existsByNicknameIgnoreCase(String nickname);
}

record SignupRequest(
    @NotBlank @Pattern(regexp = "^[A-Za-z0-9_]{4,20}$") String username,
    @NotBlank @Size(min = 8, max = 72) String password,
    @NotBlank @Size(max = 50) String nickname) {}
record LoginRequest(@NotBlank String username, @NotBlank String password) {}
record UserResponse(Long id, String username, String nickname) { static UserResponse from(AppUser u) { return new UserResponse(u.id, u.username, u.nickname); } }
record LoginResponse(String accessToken, String tokenType, UserResponse user) {}
record SuccessResponse(boolean success, String message) {}
record ErrorResponse(boolean success, String code, String message, String requestId) {}

/** Emits the same safe envelope for security failures raised before a controller. */
@Component
class SecurityErrorHandler implements AuthenticationEntryPoint, AccessDeniedHandler {
  private final ObjectMapper json;
  SecurityErrorHandler(ObjectMapper json) { this.json = json; }

  @Override
  public void commence(HttpServletRequest request, HttpServletResponse response,
      org.springframework.security.core.AuthenticationException exception) throws IOException {
    write(response, HttpStatus.UNAUTHORIZED, "UNAUTHORIZED", "인증이 필요합니다.");
  }

  @Override
  public void handle(HttpServletRequest request, HttpServletResponse response,
      AccessDeniedException exception) throws IOException {
    write(response, HttpStatus.FORBIDDEN, "ACCESS_DENIED", "접근 권한이 없습니다.");
  }

  private void write(HttpServletResponse response, HttpStatus status, String code, String message)
      throws IOException {
    response.setStatus(status.value());
    response.setContentType("application/json;charset=UTF-8");
    json.writeValue(response.getOutputStream(),
        new ErrorResponse(false, code, message, RequestCorrelationFilter.currentId()));
  }
}

@Service
class AuthService {
  private final UserRepository users;
  private final PasswordEncoder encoder;
  private final JwtService jwt;
  AuthService(UserRepository users, PasswordEncoder encoder, JwtService jwt) { this.users = users; this.encoder = encoder; this.jwt = jwt; }

  void signup(SignupRequest request) {
    if (users.existsByUsername(request.username())) throw new ApiException(HttpStatus.CONFLICT, "DUPLICATE_USERNAME", "이미 사용 중인 아이디입니다.");
    AppUser user = new AppUser();
    user.username = request.username();
    user.passwordHash = encoder.encode(request.password());
    user.nickname = request.nickname().trim();
    users.save(user);
  }

  LoginResponse login(LoginRequest request) {
    AppUser user = users.findByUsername(request.username())
        .filter(found -> encoder.matches(request.password(), found.passwordHash))
        .orElseThrow(() -> new ApiException(HttpStatus.UNAUTHORIZED, "INVALID_CREDENTIALS", "아이디 또는 비밀번호가 올바르지 않습니다."));
    return new LoginResponse(jwt.create(user), "Bearer", UserResponse.from(user));
  }

  UserResponse me(String username) {
    return users.findByUsername(username).map(UserResponse::from)
        .orElseThrow(() -> new ApiException(HttpStatus.UNAUTHORIZED, "UNAUTHORIZED", "인증이 필요합니다."));
  }
}

@RestController
@RequestMapping("/api")
class AuthController {
  private final AuthService auth;
  AuthController(AuthService auth) { this.auth = auth; }

  @PostMapping("/auth/signup")
  ResponseEntity<SuccessResponse> signup(@Valid @RequestBody SignupRequest request) {
    auth.signup(request);
    return ResponseEntity.status(HttpStatus.CREATED).body(new SuccessResponse(true, "회원가입이 완료되었습니다."));
  }

  @PostMapping("/auth/login")
  LoginResponse login(@Valid @RequestBody LoginRequest request) { return auth.login(request); }

}

@Component
class JwtService {
  private final SecretKey key;
  private final long expirationMs;
  JwtService(@Value("${app.jwt.secret}") String secret, @Value("${app.jwt.expiration-ms}") long expirationMs) {
    if (secret == null || secret.length() < 32) throw new IllegalStateException("JWT_SECRET must contain at least 32 characters.");
    this.key = Keys.hmacShaKeyFor(secret.getBytes(StandardCharsets.UTF_8));
    this.expirationMs = expirationMs;
  }
  String create(AppUser user) {
    return Jwts.builder().subject(user.username).issuedAt(new Date()).expiration(new Date(System.currentTimeMillis() + expirationMs)).signWith(key).compact();
  }
  String subject(String token) { return Jwts.parser().verifyWith(key).build().parseSignedClaims(token).getPayload().getSubject(); }
}

@Component
class JwtFilter extends OncePerRequestFilter {
  private final JwtService jwt;
  JwtFilter(JwtService jwt) { this.jwt = jwt; }
  @Override protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain) throws ServletException, IOException {
    String header = request.getHeader("Authorization");
    if (header != null && header.startsWith("Bearer ")) {
      try {
        String subject = jwt.subject(header.substring(7));
        SecurityContextHolder.getContext().setAuthentication(new UsernamePasswordAuthenticationToken(subject, null, java.util.List.of()));
      } catch (RuntimeException ignored) { SecurityContextHolder.clearContext(); }
    }
    chain.doFilter(request, response);
  }
}

/**
 * Creates or propagates a bounded correlation ID without ever recording
 * Authorization, request bodies, passwords, or invite-code text.
 */
@Component
@Order(Ordered.HIGHEST_PRECEDENCE)
class RequestCorrelationFilter extends OncePerRequestFilter {
  private static final Logger log = LoggerFactory.getLogger(RequestCorrelationFilter.class);
  private static final String HEADER = "X-Request-ID";
  private static final String MDC_KEY = "requestId";

  static String currentId() {
    String value = MDC.get(MDC_KEY);
    return value == null ? "unknown" : value;
  }

  @Override
  protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response,
      FilterChain chain) throws ServletException, IOException {
    String supplied = request.getHeader(HEADER);
    String requestId = supplied != null && supplied.matches("[A-Za-z0-9._-]{8,80}")
        ? supplied : UUID.randomUUID().toString();
    long started = System.nanoTime();
    MDC.put(MDC_KEY, requestId);
    response.setHeader(HEADER, requestId);
    try {
      chain.doFilter(request, response);
    } finally {
      long elapsedMs = (System.nanoTime() - started) / 1_000_000;
      var authentication = SecurityContextHolder.getContext().getAuthentication();
      String user = authentication == null || !authentication.isAuthenticated()
          ? "anonymous" : masked(authentication.getName());
      log.info("http request method={} path={} status={} latencyMs={} contentLength={} user={}",
          request.getMethod(), request.getRequestURI(), response.getStatus(), elapsedMs,
          request.getContentLengthLong(), user);
      MDC.remove(MDC_KEY);
    }
  }

  private static String masked(String value) {
    if (value == null || value.isBlank()) return "anonymous";
    return value.length() <= 2 ? "**" : value.substring(0, 1) + "***" + value.substring(value.length() - 1);
  }
}

class ApiException extends RuntimeException {
  final HttpStatus status; final String code;
  ApiException(HttpStatus status, String code, String message) { super(message); this.status = status; this.code = code; }
}

@RestControllerAdvice
class ApiErrorHandler {
  private static final Logger log = LoggerFactory.getLogger(ApiErrorHandler.class);
  @ExceptionHandler(ApiException.class)
  ResponseEntity<ErrorResponse> api(ApiException e) {
    log.warn("API request failed status={} code={} message={}", e.status.value(), e.code, e.getMessage());
    return ResponseEntity.status(e.status).body(error(e.code, e.getMessage()));
  }
  @ExceptionHandler(MethodArgumentNotValidException.class)
  ResponseEntity<ErrorResponse> invalid(MethodArgumentNotValidException e) {
    log.warn("API validation failed: {}", e.getMessage());
    return ResponseEntity.badRequest().body(error("INVALID_REQUEST", "입력값을 확인해주세요."));
  }
  @ExceptionHandler(DataIntegrityViolationException.class)
  ResponseEntity<ErrorResponse> integrity(DataIntegrityViolationException e) {
    log.warn("API data constraint failed", e);
    return ResponseEntity.status(HttpStatus.CONFLICT)
        .body(error("DATA_CONFLICT", "요청이 이미 처리되었거나 현재 상태와 충돌합니다."));
  }
  @ExceptionHandler(AccessDeniedException.class)
  ResponseEntity<ErrorResponse> forbidden(AccessDeniedException e) {
    log.warn("API access denied");
    return ResponseEntity.status(HttpStatus.FORBIDDEN)
        .body(error("ACCESS_DENIED", "접근 권한이 없습니다."));
  }
  @ExceptionHandler(Exception.class)
  ResponseEntity<ErrorResponse> unexpected(Exception e) {
    log.error("Unhandled API error", e);
    return ResponseEntity.status(500).body(error("INTERNAL_SERVER_ERROR", "서버 오류가 발생했습니다."));
  }
  private ErrorResponse error(String code, String message) {
    return new ErrorResponse(false, code, message, RequestCorrelationFilter.currentId());
  }
}
