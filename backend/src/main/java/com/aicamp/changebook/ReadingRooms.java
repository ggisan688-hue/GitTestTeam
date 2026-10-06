package com.aicamp.changebook;

import jakarta.persistence.*;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import jakarta.validation.constraints.NotNull;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import java.security.SecureRandom;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

@Entity
@Table(name = "change_book_reading_rooms")
class ReadingRoom {
  @Id @GeneratedValue(strategy = GenerationType.IDENTITY) Long id;
  @ManyToOne(fetch = FetchType.LAZY) @JoinColumn(name = "owner_id") AppUser owner;
  // Read-only scalar counterpart avoids relying on a partially initialized
  // ManyToOne proxy when rooms are looked up by invite code.
  @Column(name = "owner_id", insertable = false, updatable = false) Long ownerId;
  @Column(name = "book_id") Long bookId;
  @Column(nullable = false, length = 100) String name;
  @Column(length = 500) String description;
  @Column(name = "max_members") int maxMembers;
  @Column(name = "is_public") boolean isPublic;
  @Column(name = "join_code") String joinCode;
  @Column(name = "spoiler_lock_enabled") boolean spoilerLockEnabled;
  @Column(name = "selected_ai_friend_type") String selectedAiFriendType;
  @Column(name = "created_at") Instant createdAt;
  @Column(name = "updated_at") Instant updatedAt;
  @PrePersist void created() { createdAt = updatedAt = Instant.now(); }
  @PreUpdate void updated() { updatedAt = Instant.now(); }
}

@Entity
@Table(name = "change_book_reading_room_members")
@IdClass(RoomMemberId.class)
class RoomMember {
  @Id @Column(name = "room_id") Long roomId;
  @Id @Column(name = "user_id") Long userId;
  @Column(nullable = false) String role;
  @Column(name = "room_nickname") String roomNickname;
  @Column(name = "room_profile_image_url", length = 500) String roomProfileImageUrl;
  @Column(name = "joined_at") Instant joinedAt;
  @PrePersist void joined() { if (joinedAt == null) joinedAt = Instant.now(); }
}

class RoomMemberId implements java.io.Serializable {
  Long roomId;
  Long userId;
  public RoomMemberId() {}
  @Override public boolean equals(Object other) {
    if (!(other instanceof RoomMemberId value)) return false;
    return java.util.Objects.equals(roomId, value.roomId) && java.util.Objects.equals(userId, value.userId);
  }
  @Override public int hashCode() { return java.util.Objects.hash(roomId, userId); }
}

interface RoomRepo extends JpaRepository<ReadingRoom, Long> {
  List<ReadingRoom> findByIsPublicTrueOrderByCreatedAtDesc();
  Optional<ReadingRoom> findByJoinCodeIgnoreCase(String joinCode);
}

interface RoomMemberRepo extends JpaRepository<RoomMember, RoomMemberId> {
  long countByRoomId(Long roomId);
  boolean existsByRoomIdAndUserId(Long roomId, Long userId);
  Optional<RoomMember> findByRoomIdAndUserId(Long roomId, Long userId);
  List<RoomMember> findByRoomIdOrderByJoinedAtAsc(Long roomId);
  @Query("select member from RoomMember member where member.userId = :userId order by member.joinedAt desc")
  List<RoomMember> findByUserId(@org.springframework.data.repository.query.Param("userId") Long userId);
}

record RoomRequest(@NotBlank(message = "방 이름을 입력해주세요.") @Size(max = 100) String name,
                   @Size(max = 500) String description,
                   @NotNull(message = "함께 읽을 도서를 선택해주세요.") Long bookId,
                   @NotNull @Min(2) @Max(10) Integer maxMembers,
                   Boolean isPublic,
                   Boolean spoilerLockEnabled,
                   @jakarta.validation.constraints.Pattern(regexp = "^(HAYU|DOHYUN|MINA)?$", message = "Invalid AI friend") String selectedAiFriendType,
                   @Size(max = 40) String roomNickname) {}
record JoinRoomCodeRequest(@NotBlank @Size(max = 16) String inviteCode,
                           @Size(max = 40) String roomNickname) {}
record RoomMemberResponse(Long userId, String nickname, String role, Instant joinedAt,
                          String roomProfileImageUrl) {}
record RoomBookResponse(Long id, String title, String author, String coverImageUrl) {
  static RoomBookResponse from(Book book) {
    return new RoomBookResponse(book.id, book.title, book.author, book.coverImageUrl);
  }
}
record RoomResponse(Long id, String name, String description, Long bookId,
                    int members, int maxMembers, boolean isPublic,
                    Long ownerId, String ownerNickname, Instant createdAt,
                    boolean joined, boolean owner, String joinCode,
                    boolean spoilerLockEnabled, String selectedAiFriendType,
                    List<RoomMemberResponse> participants,
                    RoomBookResponse book, String hostNickname, String myRole,
                    int memberCount, String joinType, String aiFriendType) {}
record JoinRoomResponse(RoomResponse room, boolean alreadyJoined) {}

@org.springframework.stereotype.Service
class RoomService {
  private static final Logger log = LoggerFactory.getLogger(RoomService.class);
  private static final SecureRandom CODE_RANDOM = new SecureRandom();
  private static final String CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  private final RoomRepo rooms;
  private final RoomMemberRepo members;
  private final UserRepository users;
  private final BookRepository books;
  private final UserFeatureService userFeatures;

  RoomService(RoomRepo rooms, RoomMemberRepo members, UserRepository users,
              BookRepository books, UserFeatureService userFeatures) {
    this.rooms = rooms;
    this.members = members;
    this.users = users;
    this.books = books;
    this.userFeatures = userFeatures;
  }

  @org.springframework.transaction.annotation.Transactional(readOnly = true)
  List<RoomResponse> list(String username) {
    AppUser current = userFeatures.me(username);
    java.util.Map<Long, ReadingRoom> visible = new java.util.LinkedHashMap<>();
    rooms.findByIsPublicTrueOrderByCreatedAtDesc().stream().filter(this::hasOwner)
        .forEach(room -> visible.put(room.id, room));
    members.findByUserId(current.id).forEach(member -> rooms.findById(member.roomId)
        .filter(this::hasOwner).ifPresent(room -> visible.put(room.id, room)));
    List<RoomResponse> result = visible.values().stream()
        .sorted(java.util.Comparator.comparing((ReadingRoom room) -> room.createdAt).reversed())
        .map(room -> response(room, current)).toList();
    log.info("reading-room list userId={} count={}", current.id, result.size());
    return result;
  }

  @org.springframework.transaction.annotation.Transactional(readOnly = true)
  List<RoomResponse> listMy(String username) {
    AppUser current = userFeatures.me(username);
    List<RoomResponse> result = members.findByUserId(current.id).stream()
        .map(member -> rooms.findById(member.roomId).orElse(null))
        .filter(java.util.Objects::nonNull)
        .filter(this::hasOwner)
        .sorted(java.util.Comparator.comparing((ReadingRoom room) -> room.createdAt).reversed())
        .map(room -> response(room, current)).toList();
    log.info("reading-room my-list userId={} count={} roomIds={}", current.id,
        result.size(), result.stream().map(RoomResponse::id).toList());
    return result;
  }

  @org.springframework.transaction.annotation.Transactional(readOnly = true)
  List<RoomResponse> listPublic(String username) {
    AppUser current = userFeatures.me(username);
    List<RoomResponse> result = rooms.findByIsPublicTrueOrderByCreatedAtDesc().stream()
        .filter(this::hasOwner)
        .map(room -> response(room, current))
        .toList();
    log.info("reading-room public-list userId={} count={}", current.id, result.size());
    return result;
  }

  /** Only active memberships are returned: public-but-unjoined rooms are never
   * valid destinations for a private annotation share. */
  @org.springframework.transaction.annotation.Transactional(readOnly = true)
  List<RoomResponse> shareTargets(String username, Long bookId) {
    AppUser current = userFeatures.me(username);
    return members.findByUserId(current.id).stream()
        .map(member -> rooms.findById(member.roomId).orElse(null))
        .filter(java.util.Objects::nonNull)
        .filter(this::hasOwner)
        .filter(room -> bookId.equals(room.bookId))
        .sorted(java.util.Comparator.comparing((ReadingRoom room) -> room.createdAt).reversed())
        .map(room -> response(room, current))
        .toList();
  }

  @org.springframework.transaction.annotation.Transactional(readOnly = true)
  RoomResponse detail(String username, Long roomId) {
    AppUser current = userFeatures.me(username);
    ReadingRoom room = room(roomId);
    requireOwnerReference(room);
    if (!room.isPublic && !isMember(room, current)) {
      throw new ApiException(HttpStatus.FORBIDDEN, "ROOM_ACCESS_DENIED", "You must join this private room first.");
    }
    return response(room, current);
  }

  @org.springframework.transaction.annotation.Transactional RoomResponse create(String username, RoomRequest request) {
    AppUser current = userFeatures.me(username);
    if (request.bookId() == null) {
      throw new ApiException(HttpStatus.BAD_REQUEST, "ROOM_BOOK_REQUIRED", "Select a book for the room.");
    }
    validateBook(request.bookId());
    ReadingRoom room = new ReadingRoom();
    apply(room, request, 0);
    room.owner = current;
    room = rooms.save(room);
    RoomMember owner = new RoomMember();
    owner.roomId = room.id;
    owner.userId = current.id;
    owner.role = "OWNER";
    owner.roomNickname = java.util.Optional.ofNullable(trimToNull(request.roomNickname())).orElse(current.nickname);
    members.save(owner);
    RoomResponse result = response(room, current);
    log.info("reading-room created roomId={} hostUserId={} bookId={} public={}", room.id, current.id, room.bookId, room.isPublic);
    return result;
  }

  RoomResponse update(String username, Long roomId, RoomRequest request) {
    AppUser current = userFeatures.me(username);
    ReadingRoom room = room(roomId);
    requireOwner(room, current);
    validateBook(request.bookId());
    apply(room, request, (int) members.countByRoomId(room.id));
    return response(rooms.save(room), current);
  }

  @org.springframework.transaction.annotation.Transactional
  RoomMemberResponse updateMyProfileImage(String username, Long roomId, MultipartFile image,
                                          ProfileImageStorage storage) {
    AppUser current = userFeatures.me(username);
    room(roomId);
    RoomMember member = members.findByRoomIdAndUserId(roomId, current.id)
        .orElseThrow(() -> new ApiException(HttpStatus.FORBIDDEN, "ROOM_MEMBER_REQUIRED", "Join the room first."));
    String oldUrl = member.roomProfileImageUrl;
    String savedUrl = storage.save(image);
    try {
      member.roomProfileImageUrl = savedUrl;
      members.save(member);
      storage.delete(oldUrl);
      return memberResponse(member, current);
    } catch (RuntimeException e) {
      storage.delete(savedUrl);
      throw e;
    }
  }

  @org.springframework.transaction.annotation.Transactional
  void deleteMyProfileImage(String username, Long roomId, ProfileImageStorage storage) {
    AppUser current = userFeatures.me(username);
    room(roomId);
    RoomMember member = members.findByRoomIdAndUserId(roomId, current.id)
        .orElseThrow(() -> new ApiException(HttpStatus.FORBIDDEN, "ROOM_MEMBER_REQUIRED", "Join the room first."));
    String oldUrl = member.roomProfileImageUrl;
    member.roomProfileImageUrl = null;
    members.save(member);
    storage.delete(oldUrl);
  }

  @org.springframework.transaction.annotation.Transactional
  JoinRoomResponse join(String username, String code, String roomNickname) {
    AppUser current = userFeatures.me(username);
    if (code == null || code.trim().isEmpty() || code.trim().length() > 16) {
      throw new ApiException(HttpStatus.BAD_REQUEST, "INVALID_INVITE_CODE", "Enter a room code.");
    }
    ReadingRoom room = rooms.findByJoinCodeIgnoreCase(code.trim())
        .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "INVALID_INVITE_CODE", "Room code not found."));
    if (isMember(room, current)) {
      log.info("reading-room join-by-code already-member roomId={} userId={}", room.id, current.id);
      return new JoinRoomResponse(response(room, current), true);
    }
    addMember(room, current, roomNickname);
    log.info("reading-room join-by-code joined roomId={} userId={}", room.id, current.id);
    return new JoinRoomResponse(response(room, current), false);
  }

  @org.springframework.transaction.annotation.Transactional
  RoomResponse joinPublic(String username, Long roomId) {
    AppUser current = userFeatures.me(username);
    ReadingRoom room = room(roomId);
    if (!room.isPublic) {
      throw new ApiException(HttpStatus.FORBIDDEN, "PRIVATE_ROOM_CODE_REQUIRED", "Use the room code to join this private room.");
    }
    addMember(room, current, null);
    return response(room, current);
  }

  @org.springframework.transaction.annotation.Transactional
  RoomResponse reissueCode(String username, Long roomId) {
    AppUser current = userFeatures.me(username);
    ReadingRoom room = room(roomId);
    requireOwner(room, current);
    room.joinCode = newCode();
    return response(rooms.save(room), current);
  }

  @org.springframework.transaction.annotation.Transactional
  void kick(String username, Long roomId, Long memberId) {
    AppUser current = userFeatures.me(username);
    ReadingRoom room = room(roomId);
    requireOwner(room, current);
    if (ownerIdOf(room).equals(memberId)) {
      throw new ApiException(HttpStatus.BAD_REQUEST, "OWNER_CANNOT_BE_KICKED", "Transfer ownership or leave the room instead.");
    }
    RoomMember member = members.findByRoomIdAndUserId(roomId, memberId)
        .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "ROOM_MEMBER_NOT_FOUND", "Room member not found."));
    members.delete(member);
    userFeatures.notify(memberId, "ROOM_REMOVED", "방에서 나갔습니다.", room.name + " 방에서 퇴장되었습니다.", room.id, current.id);
  }

  @org.springframework.transaction.annotation.Transactional
  void leave(String username, Long roomId) {
    AppUser current = userFeatures.me(username);
    ReadingRoom room = room(roomId);
    RoomMember currentMember = members.findByRoomIdAndUserId(roomId, current.id)
        .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "ROOM_MEMBER_NOT_FOUND", "You are not in this room."));
    members.delete(currentMember);
    if (!ownerIdOf(room).equals(current.id)) return;
    List<RoomMember> remaining = members.findByRoomIdOrderByJoinedAtAsc(room.id);
    if (remaining.isEmpty()) {
      rooms.delete(room);
      return;
    }
    RoomMember next = remaining.get(0);
    AppUser nextOwner = users.findById(next.userId).orElseThrow();
    room.owner = nextOwner;
    next.role = "OWNER";
    members.save(next);
    rooms.save(room);
    userFeatures.notify(nextOwner.id, "ROOM_OWNER_CHANGED", "방장이 되었습니다.", room.name + " 방의 새 방장입니다.", room.id, current.id);
  }

  @org.springframework.transaction.annotation.Transactional
  void delete(String username, Long roomId) {
    AppUser current = userFeatures.me(username);
    ReadingRoom room = room(roomId);
    requireOwner(room, current);
    rooms.delete(room);
  }

  private ReadingRoom room(Long roomId) {
    return rooms.findById(roomId).orElseThrow(
        () -> new ApiException(HttpStatus.NOT_FOUND, "ROOM_NOT_FOUND", "Room not found."));
  }

  private boolean hasOwner(ReadingRoom room) {
    Long ownerId = ownerIdOf(room);
    return ownerId != null && users.existsById(ownerId);
  }

  private Long ownerIdOf(ReadingRoom room) {
    if (room == null) return null;
    if (room.ownerId != null) return room.ownerId;
    return room.owner == null ? null : room.owner.id;
  }

  private void requireOwnerReference(ReadingRoom room) {
    if (!hasOwner(room)) {
      throw new ApiException(HttpStatus.CONFLICT, "ROOM_OWNER_NOT_FOUND", "This room has an invalid owner.");
    }
  }

  private void validateBook(Long bookId) {
    if (bookId != null && !books.existsById(bookId)) {
      throw new ApiException(HttpStatus.NOT_FOUND, "BOOK_NOT_FOUND", "Book not found.");
    }
  }

  private void apply(ReadingRoom room, RoomRequest request, int currentMembers) {
    int maximum = request.maxMembers() == null ? (room.id == null ? 6 : room.maxMembers) : request.maxMembers();
    if (maximum < currentMembers) {
      throw new ApiException(HttpStatus.CONFLICT, "MAX_MEMBERS_BELOW_CURRENT", "Maximum members cannot be less than current members.");
    }
    room.name = request.name().trim();
    room.description = trimToNull(request.description());
    room.bookId = request.bookId();
    room.maxMembers = maximum;
    room.isPublic = !Boolean.FALSE.equals(request.isPublic());
    room.spoilerLockEnabled = Boolean.TRUE.equals(request.spoilerLockEnabled());
    room.selectedAiFriendType = trimToNull(request.selectedAiFriendType());
    // Public rooms remain joinable from the directory, but also receive the
    // same private invite-code mechanism for direct invitations.
    if (room.joinCode == null || room.joinCode.isBlank()) room.joinCode = newCode();
  }

  private RoomResponse response(ReadingRoom room, AppUser current) {
    boolean joined = isMember(room, current);
    Long ownerId = ownerIdOf(room);
    AppUser ownerUser = users.findById(ownerId).orElseThrow(
        () -> new ApiException(HttpStatus.CONFLICT, "ROOM_OWNER_NOT_FOUND", "This room has an invalid owner."));
    RoomMember currentMember = members.findByRoomIdAndUserId(room.id, current.id).orElse(null);
    boolean owner = isOwner(room, current, currentMember);
    List<RoomMemberResponse> participants = members.findByRoomIdOrderByJoinedAtAsc(room.id).stream()
        .map(member -> users.findById(member.userId)
            .map(user -> memberResponse(member, user))
            .orElse(null))
        .filter(java.util.Objects::nonNull)
        .toList();
    RoomBookResponse book = room.bookId == null ? null : books.findById(room.bookId)
        .map(RoomBookResponse::from).orElse(null);
    return new RoomResponse(room.id, room.name, room.description, room.bookId,
        participants.size(), room.maxMembers, room.isPublic, ownerId,
        ownerUser.nickname, room.createdAt, joined, owner,
        owner ? room.joinCode : null, room.spoilerLockEnabled, room.selectedAiFriendType, participants,
        book, ownerUser.nickname, currentMember == null ? null : currentMember.role,
        participants.size(), room.isPublic ? "PUBLIC" : "PRIVATE", room.selectedAiFriendType);
  }

  private RoomMemberResponse memberResponse(RoomMember member, AppUser user) {
    String imageUrl = member.roomProfileImageUrl;
    if (imageUrl == null || imageUrl.isBlank()) imageUrl = userFeatures.profileFor(user).profileImageUrl();
    return new RoomMemberResponse(user.id,
        member.roomNickname == null || member.roomNickname.isBlank() ? user.nickname : member.roomNickname,
        member.role, member.joinedAt, imageUrl);
  }

  private boolean isMember(ReadingRoom room, AppUser user) {
    return members.existsByRoomIdAndUserId(room.id, user.id);
  }

  private void addMember(ReadingRoom room, AppUser user, String roomNickname) {
    if (isMember(room, user)) {
      throw new ApiException(HttpStatus.CONFLICT, "ALREADY_ROOM_MEMBER", "You are already in this room.");
    }
    if (members.countByRoomId(room.id) >= room.maxMembers) {
      throw new ApiException(HttpStatus.CONFLICT, "ROOM_CAPACITY_REACHED", "This room is full.");
    }
    RoomMember member = new RoomMember();
    member.roomId = room.id;
    member.userId = user.id;
    member.role = "MEMBER";
    member.roomNickname = trimToNull(roomNickname);
    members.save(member);
    userFeatures.notify(ownerIdOf(room), "ROOM_JOINED", "새 참여자", user.nickname + "님이 " + room.name + " 방에 참여했습니다.", room.id, user.id);
  }

  private void requireOwner(ReadingRoom room, AppUser user) {
    RoomMember member = members.findByRoomIdAndUserId(room.id, user.id).orElse(null);
    if (!isOwner(room, user, member)) {
      throw new ApiException(HttpStatus.FORBIDDEN, "ROOM_OWNER_REQUIRED", "Only the room owner can do this.");
    }
  }

  private boolean isOwner(ReadingRoom room, AppUser user, RoomMember member) {
    if (java.util.Objects.equals(ownerIdOf(room), user.id)) return true;
    // Some existing rows identify the host through the member role.  Treat
    // both historical HOST and current OWNER values as the same authority.
    return member != null && ("OWNER".equals(member.role) || "HOST".equals(member.role));
  }

  private String newCode() {
    // The database UNIQUE constraint remains the final guard.  Check first so
    // a collision is retried before a room update/creation is flushed.
    for (int attempt = 0; attempt < 20; attempt++) {
      StringBuilder code = new StringBuilder(9);
      for (int i = 0; i < 8; i++) {
        if (i == 4) code.append('-');
        code.append(CODE_ALPHABET.charAt(CODE_RANDOM.nextInt(CODE_ALPHABET.length())));
      }
      String candidate = code.toString();
      if (rooms.findByJoinCodeIgnoreCase(candidate).isEmpty()) return candidate;
    }
    throw new ApiException(HttpStatus.CONFLICT, "INVITE_CODE_GENERATION_FAILED", "Could not generate a unique invite code.");
  }
  private String trimToNull(String value) { return value == null || value.trim().isEmpty() ? null : value.trim(); }
}

@RestController
@RequestMapping("/api/reading-rooms")
class RoomController {
  private final RoomService service;
  private final ProfileImageStorage images;
  RoomController(RoomService service, ProfileImageStorage images) { this.service = service; this.images = images; }
  @GetMapping List<RoomResponse> list(org.springframework.security.core.Authentication authentication) { return service.list(authentication.getName()); }
  @GetMapping("/my") List<RoomResponse> my(org.springframework.security.core.Authentication authentication) { return service.listMy(authentication.getName()); }
  @GetMapping("/public") List<RoomResponse> publicRooms(org.springframework.security.core.Authentication authentication) { return service.listPublic(authentication.getName()); }
  @GetMapping("/share-targets/books/{bookId}") List<RoomResponse> shareTargets(@PathVariable Long bookId, org.springframework.security.core.Authentication authentication) { return service.shareTargets(authentication.getName(), bookId); }
  @GetMapping("/{roomId}") RoomResponse detail(@PathVariable Long roomId, org.springframework.security.core.Authentication authentication) { return service.detail(authentication.getName(), roomId); }
  @PostMapping @ResponseStatus(HttpStatus.CREATED) RoomResponse create(@Valid @RequestBody RoomRequest request, org.springframework.security.core.Authentication authentication) { return service.create(authentication.getName(), request); }
  @PatchMapping("/{roomId}") RoomResponse update(@PathVariable Long roomId, @Valid @RequestBody RoomRequest request, org.springframework.security.core.Authentication authentication) { return service.update(authentication.getName(), roomId, request); }
  @PostMapping("/join") JoinRoomResponse join(@RequestParam String code, org.springframework.security.core.Authentication authentication) { return service.join(authentication.getName(), code, null); }
  @PostMapping("/join-by-code") JoinRoomResponse joinByCode(@Valid @RequestBody JoinRoomCodeRequest request, org.springframework.security.core.Authentication authentication) { return service.join(authentication.getName(), request.inviteCode(), request.roomNickname()); }
  @PostMapping("/{roomId}/members") RoomResponse joinPublic(@PathVariable Long roomId, org.springframework.security.core.Authentication authentication) { return service.joinPublic(authentication.getName(), roomId); }
  @PostMapping("/{roomId}/join-code") RoomResponse reissueCode(@PathVariable Long roomId, org.springframework.security.core.Authentication authentication) { return service.reissueCode(authentication.getName(), roomId); }
  @PostMapping("/{roomId}/invite-code/regenerate") RoomResponse regenerateInviteCode(@PathVariable Long roomId, org.springframework.security.core.Authentication authentication) { return service.reissueCode(authentication.getName(), roomId); }
  @PutMapping(value = "/{roomId}/members/me/profile-image", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
  RoomMemberResponse uploadMyProfileImage(@PathVariable Long roomId, @RequestPart("profileImage") MultipartFile profileImage, org.springframework.security.core.Authentication authentication) { return service.updateMyProfileImage(authentication.getName(), roomId, profileImage, images); }
  @DeleteMapping("/{roomId}/members/me/profile-image") @ResponseStatus(HttpStatus.NO_CONTENT)
  void deleteMyProfileImage(@PathVariable Long roomId, org.springframework.security.core.Authentication authentication) { service.deleteMyProfileImage(authentication.getName(), roomId, images); }
  @DeleteMapping("/{roomId}/members/{memberId}") @ResponseStatus(HttpStatus.NO_CONTENT) void kick(@PathVariable Long roomId, @PathVariable Long memberId, org.springframework.security.core.Authentication authentication) { service.kick(authentication.getName(), roomId, memberId); }
  @DeleteMapping("/{roomId}/members/me") @ResponseStatus(HttpStatus.NO_CONTENT) void leave(@PathVariable Long roomId, org.springframework.security.core.Authentication authentication) { service.leave(authentication.getName(), roomId); }
  @DeleteMapping("/{roomId}") @ResponseStatus(HttpStatus.NO_CONTENT) void delete(@PathVariable Long roomId, org.springframework.security.core.Authentication authentication) { service.delete(authentication.getName(), roomId); }
}
