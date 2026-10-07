package com.aicamp.changebook;

import jakarta.persistence.*;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.Base64;
import java.util.Optional;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.http.HttpStatus;
import org.springframework.mail.SimpleMailMessage;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;

@Entity
@Table(name = "change_book_password_reset_tokens")
class PasswordResetToken {
  @Id @GeneratedValue(strategy = GenerationType.IDENTITY) Long id;
  @ManyToOne(fetch = FetchType.LAZY) @JoinColumn(name = "user_id", nullable = false) AppUser user;
  @Column(name = "token_hash", nullable = false, unique = true, length = 64) String tokenHash;
  @Column(name = "expires_at", nullable = false) Instant expiresAt;
  @Column(name = "consumed_at") Instant consumedAt;
  @Column(name = "requested_ip_hash", length = 64) String requestedIpHash;
  @Column(name = "created_at", nullable = false) Instant createdAt;
  @PrePersist void create() { if (createdAt == null) createdAt = Instant.now(); }
}

@Entity
@Table(name = "change_book_password_reset_requests")
class PasswordResetRequestLog {
  @Id @GeneratedValue(strategy = GenerationType.IDENTITY) Long id;
  @Column(name = "email_hash", nullable = false, length = 64) String emailHash;
  @Column(name = "ip_hash", nullable = false, length = 64) String ipHash;
  @Column(name = "created_at", nullable = false) Instant createdAt;
  @PrePersist void create() { if (createdAt == null) createdAt = Instant.now(); }
}

interface PasswordResetTokenRepository extends JpaRepository<PasswordResetToken, Long> {
  Optional<PasswordResetToken> findByTokenHash(String tokenHash);
  @Modifying @Query("update PasswordResetToken t set t.consumedAt = :now where t.user.id = :userId and t.consumedAt is null")
  int invalidateActive(Long userId, Instant now);
  @Modifying @Query("update PasswordResetToken t set t.consumedAt = :now where t.tokenHash = :hash and t.consumedAt is null and t.expiresAt > :now")
  int consumeUsable(String hash, Instant now);
}
interface PasswordResetRequestLogRepository extends JpaRepository<PasswordResetRequestLog, Long> {
  long countByEmailHashAndCreatedAtAfter(String emailHash, Instant after);
  long countByIpHashAndCreatedAtAfter(String ipHash, Instant after);
}

record PasswordResetRequest(@NotBlank @Email @Size(max = 254) String email) {}
record PasswordResetConfirmRequest(@NotBlank @Size(min = 32, max = 512) String token,
                                  @NotBlank @Size(min = 8, max = 72) String password) {}

@Service
class PasswordResetService {
  private static final Logger log = LoggerFactory.getLogger(PasswordResetService.class);
  private static final String GENERIC_MESSAGE = "입력한 이메일로 재설정 안내를 보냈습니다. 메일함과 스팸함을 확인해주세요.";
  private final UserRepository users;
  private final PasswordResetTokenRepository tokens;
  private final PasswordResetRequestLogRepository requests;
  private final org.springframework.security.crypto.password.PasswordEncoder encoder;
  private final ObjectProvider<JavaMailSender> mailSender;
  private final SecureRandom random = new SecureRandom();
  private final int ttlMinutes, emailLimit, ipLimit, windowMinutes;
  private final String resetUrl, from;
  private final boolean mailEnabled;

  PasswordResetService(UserRepository users, PasswordResetTokenRepository tokens,
      PasswordResetRequestLogRepository requests,
      org.springframework.security.crypto.password.PasswordEncoder encoder,
      ObjectProvider<JavaMailSender> mailSender,
      @Value("${app.password-reset.token-ttl-minutes:20}") int ttlMinutes,
      @Value("${app.password-reset.max-requests-per-email:3}") int emailLimit,
      @Value("${app.password-reset.max-requests-per-ip:10}") int ipLimit,
      @Value("${app.password-reset.rate-limit-window-minutes:60}") int windowMinutes,
      @Value("${app.password-reset.url:}") String resetUrl,
      @Value("${app.password-reset.mail-enabled:false}") boolean mailEnabled,
      @Value("${MAIL_FROM:}") String from) {
    this.users = users; this.tokens = tokens; this.requests = requests; this.encoder = encoder;
    this.mailSender = mailSender; this.ttlMinutes = ttlMinutes; this.emailLimit = emailLimit;
    this.ipLimit = ipLimit; this.windowMinutes = windowMinutes; this.resetUrl = resetUrl;
    this.mailEnabled = mailEnabled; this.from = from;
  }

  @Transactional
  void request(String rawEmail, String rawIp) {
    String email = rawEmail.trim().toLowerCase(java.util.Locale.ROOT);
    String emailHash = sha256(email), ipHash = sha256(rawIp == null ? "" : rawIp);
    Instant cutoff = Instant.now().minus(windowMinutes, ChronoUnit.MINUTES);
    boolean allowed = requests.countByEmailHashAndCreatedAtAfter(emailHash, cutoff) < emailLimit
        && requests.countByIpHashAndCreatedAtAfter(ipHash, cutoff) < ipLimit;
    PasswordResetRequestLog entry = new PasswordResetRequestLog(); entry.emailHash = emailHash; entry.ipHash = ipHash; requests.save(entry);
    Optional<AppUser> found = users.findByEmailIgnoreCase(email);
    // Always take the same database path for a valid-looking address; no account state is returned.
    if (!allowed || found.isEmpty()) return;
    AppUser user = found.get();
    byte[] bytes = new byte[32]; random.nextBytes(bytes);
    String token = Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
    tokens.invalidateActive(user.id, Instant.now());
    PasswordResetToken reset = new PasswordResetToken(); reset.user = user; reset.tokenHash = sha256(token);
    reset.expiresAt = Instant.now().plus(ttlMinutes, ChronoUnit.MINUTES); reset.requestedIpHash = ipHash; tokens.save(reset);
    sendMail(email, token);
  }

  @Transactional
  void confirm(PasswordResetConfirmRequest request) {
    if (request.password().trim().length() < 8) throw new ApiException(HttpStatus.BAD_REQUEST, "WEAK_PASSWORD", "비밀번호는 8자 이상이어야 합니다.");
    String hash = sha256(request.token());
    // Conditional update makes the one-time use guarantee atomic under concurrent requests.
    if (tokens.consumeUsable(hash, Instant.now()) != 1)
      throw new ApiException(HttpStatus.BAD_REQUEST, "INVALID_RESET_TOKEN", "재설정 링크가 만료되었거나 이미 사용되었습니다.");
    PasswordResetToken token = tokens.findByTokenHash(hash).orElseThrow();
    AppUser user = token.user;
    user.passwordHash = encoder.encode(request.password());
    user.authVersion++;
    users.save(user);
  }

  String genericMessage() { return GENERIC_MESSAGE; }
  private void sendMail(String email, String token) {
    String requestId = RequestCorrelationFilter.currentId();
    if (!mailEnabled || resetUrl.isBlank() || mailSender.getIfAvailable() == null) {
      log.warn("password-reset delivery unavailable requestId={} reason=mail_not_configured", requestId);
      return;
    }
    try {
      String separator = resetUrl.contains("?") ? "&" : "?";
      SimpleMailMessage message = new SimpleMailMessage();
      if (!from.isBlank()) message.setFrom(from);
      message.setTo(email); message.setSubject("ChangeBook 비밀번호 재설정");
      message.setText("아래 링크에서 비밀번호를 재설정하세요. 링크는 짧은 시간 동안 한 번만 사용할 수 있습니다.\n" + resetUrl + separator + "token=" + token);
      mailSender.getObject().send(message);
    } catch (RuntimeException e) {
      log.warn("password-reset delivery failed requestId={} reason={}", requestId, e.getClass().getSimpleName());
    }
  }
  static String sha256(String value) {
    try { return java.util.HexFormat.of().formatHex(java.security.MessageDigest.getInstance("SHA-256").digest(value.getBytes(StandardCharsets.UTF_8))); }
    catch (java.security.NoSuchAlgorithmException e) { throw new IllegalStateException(e); }
  }
}

@RestController
@RequestMapping("/api/auth/password-reset")
class PasswordResetController {
  private final PasswordResetService service;
  PasswordResetController(PasswordResetService service) { this.service = service; }
  @PostMapping("/request") SuccessResponse request(@Valid @RequestBody PasswordResetRequest request, HttpServletRequest http) {
    service.request(request.email(), clientIp(http)); return new SuccessResponse(true, service.genericMessage());
  }
  @PostMapping("/confirm") SuccessResponse confirm(@Valid @RequestBody PasswordResetConfirmRequest request) {
    service.confirm(request); return new SuccessResponse(true, "비밀번호가 변경되었습니다. 다시 로그인해주세요.");
  }
  private String clientIp(HttpServletRequest request) { return request.getRemoteAddr(); }
}
