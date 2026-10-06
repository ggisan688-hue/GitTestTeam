package com.aicamp.changebook;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import java.time.Instant;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Configuration;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RequestPart;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;
import org.springframework.web.servlet.config.annotation.ResourceHandlerRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

@Entity
@Table(name = "change_book_user_profiles")
class UserProfile {
  @Id
  @Column(name = "user_id")
  Long userId;

  @Column(length = 300)
  String bio;

  @Column(name = "avatar_url", length = 500)
  String avatarUrl;

  @Column(length = 16)
  String avatar;

  @Column(name = "updated_at", nullable = false)
  Instant updatedAt;

  @jakarta.persistence.PrePersist
  @jakarta.persistence.PreUpdate
  void changed() { updatedAt = Instant.now(); }
}

interface UserProfileRepository extends JpaRepository<UserProfile, Long> {}

record ProfileResponse(Long id, String username, String nickname, String bio,
                       String avatar, String profileImageUrl, Instant createdAt, Instant updatedAt) {}

record ProfileUpdateRequest(@NotBlank @Size(max = 50) String nickname,
                            @Size(max = 300) String bio,
                            @Size(max = 16) String avatar) {}

record NotificationResponse(Long id, String type, String title, String body,
                            Long relatedRoomId, Long relatedUserId, boolean read,
                            Instant createdAt) {}

record NotificationSettingsResponse(boolean friendEnabled, boolean roomEnabled,
                                    boolean activityEnabled) {}

record NotificationSettingsRequest(Boolean friendEnabled, Boolean roomEnabled,
                                   Boolean activityEnabled) {}

@Entity
@Table(name = "change_book_notifications")
class AppNotification {
  @Id
  @jakarta.persistence.GeneratedValue(strategy = jakarta.persistence.GenerationType.IDENTITY)
  Long id;
  @Column(name = "user_id", nullable = false)
  Long userId;
  @Column(nullable = false, length = 40)
  String type;
  @Column(nullable = false, length = 160)
  String title;
  @Column(nullable = false, length = 500)
  String body;
  @Column(name = "related_room_id")
  Long relatedRoomId;
  @Column(name = "related_user_id")
  Long relatedUserId;
  @Column(name = "is_read", nullable = false)
  boolean read;
  @Column(name = "created_at", nullable = false)
  Instant createdAt;
  @jakarta.persistence.PrePersist void created() { createdAt = Instant.now(); }
}

@Entity
@Table(name = "change_book_notification_settings")
class NotificationSettings {
  @Id
  @Column(name = "user_id")
  Long userId;
  @Column(name = "friend_enabled", nullable = false)
  boolean friendEnabled = true;
  @Column(name = "room_enabled", nullable = false)
  boolean roomEnabled = true;
  @Column(name = "activity_enabled", nullable = false)
  boolean activityEnabled = true;
  @Column(name = "updated_at", nullable = false)
  Instant updatedAt;
  @jakarta.persistence.PrePersist
  @jakarta.persistence.PreUpdate
  void changed() { updatedAt = Instant.now(); }
}

interface AppNotificationRepository extends JpaRepository<AppNotification, Long> {
  List<AppNotification> findByUserIdOrderByCreatedAtDesc(Long userId);
}

interface NotificationSettingsRepository extends JpaRepository<NotificationSettings, Long> {}

@org.springframework.stereotype.Service
class UserFeatureService {
  private final UserRepository users;
  private final UserProfileRepository profiles;
  private final AppNotificationRepository notifications;
  private final NotificationSettingsRepository settings;

  UserFeatureService(UserRepository users, UserProfileRepository profiles,
                     AppNotificationRepository notifications,
                     NotificationSettingsRepository settings) {
    this.users = users;
    this.profiles = profiles;
    this.notifications = notifications;
    this.settings = settings;
  }

  AppUser me(String username) {
    return users.findByUsername(username).orElseThrow(
        () -> new ApiException(HttpStatus.UNAUTHORIZED, "UNAUTHORIZED", "Authentication is required."));
  }

  ProfileResponse profile(String username) { return profileFor(me(username)); }

  ProfileResponse profileFor(AppUser user) {
    UserProfile profile = profiles.findById(user.id).orElse(null);
    return new ProfileResponse(user.id, user.username, user.nickname,
        profile == null ? null : profile.bio,
        profile == null ? defaultAvatar(user.nickname) : profile.avatar,
        profile == null ? null : profile.avatarUrl,
        user.createdAt, profile == null ? user.updatedAt : profile.updatedAt);
  }

  @Transactional
  ProfileResponse updateProfile(String username, ProfileUpdateRequest request) {
    return updateProfile(username, request, null, false);
  }

  @Transactional
  ProfileResponse updateProfile(String username, ProfileUpdateRequest request, String profileImageUrl, boolean removeProfileImage) {
    AppUser user = me(username);
    String nickname = request.nickname().trim();
    if (!user.nickname.equalsIgnoreCase(nickname) && users.existsByNicknameIgnoreCase(nickname)) {
      throw new ApiException(HttpStatus.CONFLICT, "DUPLICATE_NICKNAME", "This nickname is already in use.");
    }
    user.nickname = nickname;
    users.save(user);
    UserProfile profile = profiles.findById(user.id).orElseGet(() -> {
      UserProfile created = new UserProfile();
      created.userId = user.id;
      return created;
    });
    if (request.bio() != null) profile.bio = trimToNull(request.bio());
    if (request.avatar() != null) profile.avatar = validateAvatar(request.avatar());
    if (profileImageUrl != null) profile.avatarUrl = profileImageUrl;
    else if (removeProfileImage) profile.avatarUrl = null;
    profiles.save(profile);
    return profileFor(user);
  }

  void deleteAccount(String username, String confirmation) {
    AppUser user = me(username);
    if (!user.username.equals(confirmation)) {
      throw new ApiException(HttpStatus.BAD_REQUEST, "ACCOUNT_DELETE_CONFIRMATION_REQUIRED", "Enter your username to confirm account deletion.");
    }
    users.delete(user);
  }

  List<NotificationResponse> notifications(String username) {
    return notifications.findByUserIdOrderByCreatedAtDesc(me(username).id).stream()
        .map(this::notificationResponse).toList();
  }

  void markRead(String username, Long notificationId) {
    AppUser user = me(username);
    AppNotification notification = notifications.findById(notificationId)
        .filter(value -> value.userId.equals(user.id))
        .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "NOTIFICATION_NOT_FOUND", "Notification not found."));
    notification.read = true;
    notifications.save(notification);
  }

  void markAllRead(String username) {
    List<AppNotification> items = notifications.findByUserIdOrderByCreatedAtDesc(me(username).id);
    items.forEach(item -> item.read = true);
    notifications.saveAll(items);
  }

  NotificationSettingsResponse notificationSettings(String username) {
    NotificationSettings value = settings.findById(me(username).id).orElseGet(NotificationSettings::new);
    return new NotificationSettingsResponse(value.userId == null || value.friendEnabled,
        value.userId == null || value.roomEnabled, value.userId == null || value.activityEnabled);
  }

  NotificationSettingsResponse updateNotificationSettings(String username, NotificationSettingsRequest request) {
    AppUser user = me(username);
    NotificationSettings value = settings.findById(user.id).orElseGet(() -> {
      NotificationSettings created = new NotificationSettings();
      created.userId = user.id;
      return created;
    });
    if (request.friendEnabled() != null) value.friendEnabled = request.friendEnabled();
    if (request.roomEnabled() != null) value.roomEnabled = request.roomEnabled();
    if (request.activityEnabled() != null) value.activityEnabled = request.activityEnabled();
    settings.save(value);
    return new NotificationSettingsResponse(value.friendEnabled, value.roomEnabled, value.activityEnabled);
  }

  void notify(Long userId, String type, String title, String body, Long roomId, Long relatedUserId) {
    if (userId == null || userId.equals(relatedUserId)) return;
    NotificationSettings preference = settings.findById(userId).orElse(null);
    boolean enabled = type.startsWith("FRIEND")
        ? preference == null || preference.friendEnabled
        : preference == null || preference.roomEnabled;
    if (!enabled) return;
    AppNotification notification = new AppNotification();
    notification.userId = userId;
    notification.type = type;
    notification.title = title;
    notification.body = body;
    notification.relatedRoomId = roomId;
    notification.relatedUserId = relatedUserId;
    notifications.save(notification);
  }

  private NotificationResponse notificationResponse(AppNotification value) {
    return new NotificationResponse(value.id, value.type, value.title, value.body,
        value.relatedRoomId, value.relatedUserId, value.read, value.createdAt);
  }

  private String trimToNull(String value) {
    if (value == null || value.trim().isEmpty()) return null;
    return value.trim();
  }

  private String validateAvatar(String value) {
    String avatar = value.trim();
    if (avatar.isEmpty() || avatar.length() > 16) {
      throw new ApiException(HttpStatus.BAD_REQUEST, "INVALID_AVATAR", "프로필 아바타를 확인해주세요.");
    }
    return avatar;
  }

  private String defaultAvatar(String nickname) {
    return nickname == null || nickname.isEmpty() ? "🙂" : nickname.substring(0, 1);
  }
}

@org.springframework.stereotype.Service
class ProfileImageStorage {
  private static final long MAX_SIZE_BYTES = 5L * 1024 * 1024;
  private static final Set<String> ALLOWED_TYPES = Set.of("image/jpeg", "image/png", "image/webp");
  private final Path directory;

  ProfileImageStorage(@Value("${app.profile-upload-dir}") String uploadDirectory) {
    directory = Path.of(uploadDirectory).toAbsolutePath().normalize();
    try {
      Files.createDirectories(directory);
    } catch (IOException e) {
      throw new IllegalStateException("프로필 이미지 저장소를 준비할 수 없습니다.", e);
    }
  }

  String save(MultipartFile image) {
    if (image.isEmpty()) throw new ApiException(HttpStatus.BAD_REQUEST, "EMPTY_PROFILE_IMAGE", "빈 이미지 파일은 등록할 수 없습니다.");
    if (image.getSize() > MAX_SIZE_BYTES) throw new ApiException(HttpStatus.BAD_REQUEST, "PROFILE_IMAGE_TOO_LARGE", "프로필 사진은 5MB 이하만 등록할 수 있습니다.");
    String contentType = image.getContentType();
    if (contentType == null || !ALLOWED_TYPES.contains(contentType.toLowerCase())) {
      throw new ApiException(HttpStatus.BAD_REQUEST, "UNSUPPORTED_PROFILE_IMAGE", "JPG, PNG, WEBP 형식의 이미지만 등록할 수 있습니다.");
    }
    byte[] content;
    try {
      content = image.getBytes();
    } catch (IOException e) {
      throw new ApiException(HttpStatus.BAD_REQUEST, "INVALID_PROFILE_IMAGE", "프로필 사진을 읽을 수 없습니다.");
    }
    if (!hasExpectedSignature(content, contentType)) {
      throw new ApiException(HttpStatus.BAD_REQUEST, "INVALID_PROFILE_IMAGE", "이미지 파일 형식을 확인해주세요.");
    }
    String extension = contentType.equalsIgnoreCase("image/png") ? ".png" : contentType.equalsIgnoreCase("image/webp") ? ".webp" : ".jpg";
    String filename = UUID.randomUUID() + extension;
    Path target = directory.resolve(filename).normalize();
    try {
      Files.write(target, content);
      return "/uploads/profiles/" + filename;
    } catch (IOException e) {
      throw new ApiException(HttpStatus.INTERNAL_SERVER_ERROR, "PROFILE_IMAGE_STORE_FAILED", "프로필 사진을 저장하지 못했습니다.");
    }
  }

  private boolean hasExpectedSignature(byte[] content, String contentType) {
    if (contentType.equalsIgnoreCase("image/jpeg")) return content.length >= 3 && (content[0] & 0xFF) == 0xFF && (content[1] & 0xFF) == 0xD8 && (content[2] & 0xFF) == 0xFF;
    if (contentType.equalsIgnoreCase("image/png")) return content.length >= 8 && (content[0] & 0xFF) == 0x89 && content[1] == 0x50 && content[2] == 0x4E && content[3] == 0x47;
    return content.length >= 12 && content[0] == 0x52 && content[1] == 0x49 && content[2] == 0x46 && content[3] == 0x46 && content[8] == 0x57 && content[9] == 0x45 && content[10] == 0x42 && content[11] == 0x50;
  }

  void delete(String url) {
    if (url == null || !url.startsWith("/uploads/profiles/")) return;
    Path target = directory.resolve(url.substring("/uploads/profiles/".length())).normalize();
    if (!target.getParent().equals(directory)) return;
    try {
      Files.deleteIfExists(target);
    } catch (IOException ignored) {
      // DB update is already complete. Leave a harmless orphan for scheduled cleanup.
    }
  }

  String resourceLocation() { return directory.toUri().toString(); }
}

@Configuration
class ProfileImageResourceConfiguration implements WebMvcConfigurer {
  private final ProfileImageStorage storage;
  ProfileImageResourceConfiguration(ProfileImageStorage storage) { this.storage = storage; }
  @Override public void addResourceHandlers(ResourceHandlerRegistry registry) {
    registry.addResourceHandler("/uploads/profiles/**").addResourceLocations(storage.resourceLocation());
  }
}

@RestController
@RequestMapping("/api/users/me")
class UserFeatureController {
  private final UserFeatureService service;
  private final ProfileImageStorage images;
  UserFeatureController(UserFeatureService service, ProfileImageStorage images) { this.service = service; this.images = images; }

  @GetMapping({"", "/profile"})
  ProfileResponse profile(org.springframework.security.core.Authentication authentication) {
    return service.profile(authentication.getName());
  }

  @PatchMapping(value = {"", "/profile"}, consumes = MediaType.APPLICATION_JSON_VALUE)
  ProfileResponse updateProfile(@Valid @RequestBody ProfileUpdateRequest request,
                                org.springframework.security.core.Authentication authentication) {
    return service.updateProfile(authentication.getName(), request);
  }

  @PatchMapping(value = {"", "/profile"}, consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
  ProfileResponse updateProfileMultipart(@RequestParam String nickname,
                                         @RequestParam(required = false) String bio,
                                         @RequestPart(required = false) MultipartFile profileImage,
                                         @RequestParam(defaultValue = "false") boolean removeProfileImage,
                                         org.springframework.security.core.Authentication authentication) {
    if (profileImage != null && removeProfileImage) {
      throw new ApiException(HttpStatus.BAD_REQUEST, "INVALID_PROFILE_IMAGE_REQUEST", "사진 등록과 삭제를 동시에 요청할 수 없습니다.");
    }
    String oldUrl = service.profile(authentication.getName()).profileImageUrl();
    String savedUrl = profileImage == null ? null : images.save(profileImage);
    try {
      ProfileResponse response = service.updateProfile(authentication.getName(), new ProfileUpdateRequest(nickname, bio, null), savedUrl, removeProfileImage);
      if (savedUrl != null || removeProfileImage) images.delete(oldUrl);
      return response;
    } catch (RuntimeException e) {
      if (savedUrl != null) images.delete(savedUrl);
      throw e;
    }
  }

  @DeleteMapping
  void deleteAccount(@RequestParam String confirmation,
                     org.springframework.security.core.Authentication authentication) {
    service.deleteAccount(authentication.getName(), confirmation);
  }
}

@RestController
@RequestMapping("/api/notifications")
class NotificationController {
  private final UserFeatureService service;
  NotificationController(UserFeatureService service) { this.service = service; }

  @GetMapping
  List<NotificationResponse> list(org.springframework.security.core.Authentication authentication) {
    return service.notifications(authentication.getName());
  }

  @PostMapping("/{notificationId}/read")
  void read(@PathVariable Long notificationId, org.springframework.security.core.Authentication authentication) {
    service.markRead(authentication.getName(), notificationId);
  }

  @PostMapping("/read-all")
  void readAll(org.springframework.security.core.Authentication authentication) {
    service.markAllRead(authentication.getName());
  }
}

@RestController
@RequestMapping("/api/me/notification-settings")
class NotificationSettingsController {
  private final UserFeatureService service;
  NotificationSettingsController(UserFeatureService service) { this.service = service; }

  @GetMapping
  NotificationSettingsResponse get(org.springframework.security.core.Authentication authentication) {
    return service.notificationSettings(authentication.getName());
  }

  @PutMapping
  NotificationSettingsResponse put(@RequestBody NotificationSettingsRequest request,
                                   org.springframework.security.core.Authentication authentication) {
    return service.updateNotificationSettings(authentication.getName(), request);
  }
}
