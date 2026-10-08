package com.aicamp.changebook;

import jakarta.persistence.*;
import jakarta.persistence.LockModeType;
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
import org.springframework.data.jpa.repository.Lock;
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
  @Column(name = "password_hash", length = 255) String passwordHash;
  @Column(name = "current_book_id") Long currentBookId;
  @Column(name = "spoiler_lock_enabled") boolean spoilerLockEnabled;
  @Column(name = "selected_ai_friend_type") String selectedAiFriendType;
  @Column(name = "cover_image_url", length = 500) String coverImageUrl;
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
  @Lock(LockModeType.PESSIMISTIC_WRITE)
  @Query("select room from ReadingRoom room where lower(room.joinCode) = lower(:joinCode)")
  Optional<ReadingRoom> findByJoinCodeForUpdate(@org.springframework.data.repository.query.Param("joinCode") String joinCode);
  @Lock(LockModeType.PESSIMISTIC_WRITE)
  @Query("select room from ReadingRoom room where room.id = :roomId")
  Optional<ReadingRoom> findByIdForUpdate(@org.springframework.data.repository.query.Param("roomId") Long roomId);
}

interface RoomMemberRepo extends JpaRepository<RoomMember, RoomMemberId> {
  long countByRoomId(Long roomId);
  boolean existsByRoomIdAndUserId(Long roomId, Long userId);
  Optional<RoomMember> findByRoomIdAndUserId(Long roomId, Long userId);
  List<RoomMember> findByRoomIdOrderByJoinedAtAsc(Long roomId);
  @Query("select member from RoomMember member where member.userId = :userId order by member.joinedAt desc")
  List<RoomMember> findByUserId(@org.springframework.data.repository.query.Param("userId") Long userId);
}

@Entity @Table(name = "change_book_reading_room_books")
@IdClass(RoomBookId.class)
class RoomBook {
  @Id @Column(name = "room_id") Long roomId;
  @Id @Column(name = "book_id") Long bookId;
  @Column(name = "display_order", nullable = false) int displayOrder;
  @Column(name = "added_by") Long addedBy;
  @Column(name = "added_at") Instant addedAt;
  @PrePersist void added() { if (addedAt == null) addedAt = Instant.now(); }
}
class RoomBookId implements java.io.Serializable { Long roomId; Long bookId; public RoomBookId() {} @Override public boolean equals(Object o) { return o instanceof RoomBookId x && java.util.Objects.equals(roomId,x.roomId) && java.util.Objects.equals(bookId,x.bookId); } @Override public int hashCode() { return java.util.Objects.hash(roomId,bookId); } }
interface RoomBookRepo extends JpaRepository<RoomBook, RoomBookId> {
  List<RoomBook> findByRoomIdOrderByDisplayOrderAsc(Long roomId);
  boolean existsByRoomIdAndBookId(Long roomId, Long bookId);
  long countByRoomId(Long roomId);
  Optional<RoomBook> findByRoomIdAndBookId(Long roomId, Long bookId);
}

@Entity @Table(name = "change_book_room_member_progress")
@IdClass(RoomMemberProgressId.class)
class RoomMemberProgress {
  @Id @Column(name="room_id") Long roomId; @Id @Column(name="user_id") Long userId; @Id @Column(name="book_id") Long bookId;
  @Column(name="progress_percent", nullable=false) int progressPercent;
  @Column(name="last_read_position", nullable=false) int lastReadPosition;
  @Column(name="updated_at", nullable=false) Instant updatedAt;
}
class RoomMemberProgressId implements java.io.Serializable { Long roomId; Long userId; Long bookId; public RoomMemberProgressId() {} @Override public boolean equals(Object o) { return o instanceof RoomMemberProgressId x && java.util.Objects.equals(roomId,x.roomId)&&java.util.Objects.equals(userId,x.userId)&&java.util.Objects.equals(bookId,x.bookId); } @Override public int hashCode() { return java.util.Objects.hash(roomId,userId,bookId); } }
interface RoomMemberProgressRepo extends JpaRepository<RoomMemberProgress, RoomMemberProgressId> { Optional<RoomMemberProgress> findByRoomIdAndUserIdAndBookId(Long roomId, Long userId, Long bookId); List<RoomMemberProgress> findByRoomIdAndBookIdOrderByUpdatedAtDesc(Long roomId, Long bookId); }

record RoomRequest(@NotBlank(message = "방 이름을 입력해주세요.") @Size(max = 100) String name,
                   @Size(max = 500) String description,
                   @NotNull(message = "함께 읽을 도서를 선택해주세요.") Long bookId,
                   @Size(min = 1, max = 100) List<@NotNull Long> bookIds,
                   @NotNull @Min(1) @Max(50) Integer maxMembers,
                   Boolean isPublic,
                   Boolean spoilerLockEnabled,
                   @jakarta.validation.constraints.Pattern(regexp = "^(HAYU|DOHYUN|MINA)?$", message = "Invalid AI friend") String selectedAiFriendType,
                   @Size(max = 40) String roomNickname,
                   @Size(min = 4, max = 72) String password) {}
record JoinRoomCodeRequest(@NotBlank @Size(max = 16) String inviteCode,
                           @Size(max = 40) String roomNickname,
                           @Size(max = 72) String password) {}
/** Safe preflight data for the two-step invite flow; no membership mutation. */
record InviteCodeValidationRequest(@NotBlank @Size(max = 16) String inviteCode) {}
record InviteCodeValidationResponse(boolean valid, Long roomId, String roomName,
                                    boolean passwordRequired, int capacity,
                                    int currentMemberCount, boolean alreadyJoined) {}
record RoomMemberResponse(Long userId, String nickname, String role, Instant joinedAt,
                          String roomProfileImageUrl) {}
record RoomBookResponse(Long id, String title, String author, String coverImageUrl) {
  static RoomBookResponse from(Book book) {
    return new RoomBookResponse(book.id, book.title, book.author, book.coverImageUrl);
  }
}
record RoomBookItemResponse(RoomBookResponse book, int order, boolean current) {}
record RoomPasswordRequest(@Size(min = 4, max = 72) String password) {}
record RoomNicknameRequest(@NotBlank @Size(max = 40) String roomNickname) {}
record RoomBookOrderRequest(@NotNull @Min(0) Integer order) {}
record RoomProgressRequest(@Min(0) @Max(100) Integer progressPercent, @Min(0) Integer lastReadPosition) {}
record RoomProgressResponse(Long roomId, Long userId, Long bookId, int progressPercent, int lastReadPosition, Instant updatedAt) {}
record RoomParticipantProgressResponse(Long userId, String nickname, String profileImageUrl,
                                       int progressPercent, int lastReadPosition, Instant updatedAt,
                                       boolean currentUser) {}
record RoomResponse(Long id, String name, String description, Long bookId,
                    int members, int maxMembers, boolean isPublic,
                    Long ownerId, String ownerNickname, Instant createdAt,
                    boolean joined, boolean owner, String joinCode,
                    boolean spoilerLockEnabled, String selectedAiFriendType,
                    List<RoomMemberResponse> participants,
                    RoomBookResponse book, RoomBookResponse coverBook, String hostNickname, String myRole,
                    int memberCount, String joinType, String aiFriendType,
                    boolean passwordRequired, Long currentBookId, List<RoomBookItemResponse> books,
                    String coverImageUrl) {}
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
  private final RoomBookRepo roomBooks;
  private final RoomMemberProgressRepo roomProgress;
  private final org.springframework.security.crypto.password.PasswordEncoder passwords;

  RoomService(RoomRepo rooms, RoomMemberRepo members, UserRepository users,
              BookRepository books, UserFeatureService userFeatures, RoomBookRepo roomBooks,
              RoomMemberProgressRepo roomProgress, org.springframework.security.crypto.password.PasswordEncoder passwords) {
    this.rooms = rooms;
    this.members = members;
    this.users = users;
    this.books = books;
    this.userFeatures = userFeatures;
    this.roomBooks = roomBooks; this.roomProgress = roomProgress; this.passwords = passwords;
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
        .filter(room -> roomBooks.existsByRoomIdAndBookId(room.id, bookId))
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
    List<Long> selectedBookIds = selectedBookIds(request);
    ReadingRoom room = new ReadingRoom();
    apply(room, request, 0);
    room.bookId = selectedBookIds.get(0);
    room.owner = current;
    // Flush both rows before serializing the response. This makes a 201 mean
    // the generated id/code and owner membership are query-visible together.
    room = rooms.saveAndFlush(room);
    for (int order = 0; order < selectedBookIds.size(); order++) {
      RoomBook roomBook = new RoomBook();
      roomBook.roomId = room.id;
      roomBook.bookId = selectedBookIds.get(order);
      roomBook.displayOrder = order;
      roomBook.addedBy = current.id;
      roomBooks.save(roomBook);
    }
    room.currentBookId = room.bookId;
    if (request.password() != null && !request.password().isBlank()) room.passwordHash = passwords.encode(request.password());
    room = rooms.save(room);
    RoomMember owner = new RoomMember();
    owner.roomId = room.id;
    owner.userId = current.id;
    owner.role = "OWNER";
    owner.roomNickname = java.util.Optional.ofNullable(trimToNull(request.roomNickname())).orElse(current.nickname);
    members.saveAndFlush(owner);
    RoomResponse result = response(room, current);
    log.info("reading-room created roomId={} hostUserId={} bookIds={} public={}", room.id, current.id, selectedBookIds, room.isPublic);
    return result;
  }

  RoomResponse update(String username, Long roomId, RoomRequest request) {
    AppUser current = userFeatures.me(username);
    ReadingRoom room = room(roomId);
    requireOwner(room, current);
    validateBook(request.bookId());
    if (!roomBooks.existsByRoomIdAndBookId(roomId, request.bookId()))
      throw new ApiException(HttpStatus.BAD_REQUEST, "ROOM_BOOK_REQUIRED", "현재 도서는 방에 추가된 도서여야 합니다.");
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

  /** A room cover belongs to the room itself; only its owner may change it. */
  @org.springframework.transaction.annotation.Transactional
  RoomResponse updateCoverImage(String username, Long roomId, MultipartFile image,
                                 ProfileImageStorage storage) {
    AppUser current = userFeatures.me(username);
    ReadingRoom room = room(roomId);
    requireOwner(room, current);
    String oldUrl = room.coverImageUrl;
    String savedUrl = storage.save(image);
    try {
      room.coverImageUrl = savedUrl;
      rooms.save(room);
      storage.delete(oldUrl);
      return response(room, current);
    } catch (RuntimeException e) {
      storage.delete(savedUrl);
      throw e;
    }
  }

  @org.springframework.transaction.annotation.Transactional
  void deleteCoverImage(String username, Long roomId, ProfileImageStorage storage) {
    AppUser current = userFeatures.me(username);
    ReadingRoom room = room(roomId);
    requireOwner(room, current);
    String oldUrl = room.coverImageUrl;
    room.coverImageUrl = null;
    rooms.save(room);
    storage.delete(oldUrl);
  }

  @org.springframework.transaction.annotation.Transactional
  JoinRoomResponse join(String username, String code, String roomNickname, String password) {
    AppUser current = userFeatures.me(username);
    String normalizedCode = normalizeCode(code);
    if (normalizedCode == null) {
      throw new ApiException(HttpStatus.BAD_REQUEST, "INVALID_INVITE_CODE", "Enter a room code.");
    }
    ReadingRoom room = rooms.findByJoinCodeForUpdate(normalizedCode)
        .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "INVALID_INVITE_CODE", "Room code not found."));
    if (isMember(room, current)) {
      log.info("reading-room join-by-code already-member roomId={} userId={}", room.id, current.id);
      return new JoinRoomResponse(response(room, current), true);
    }
    if (room.passwordHash != null && (password == null || password.isBlank()))
      throw new ApiException(HttpStatus.BAD_REQUEST, "ROOM_PASSWORD_REQUIRED", "방 비밀번호를 입력해 주세요.");
    if (room.passwordHash != null && !passwords.matches(password, room.passwordHash))
      throw new ApiException(HttpStatus.FORBIDDEN, "ROOM_PASSWORD_INCORRECT", "방 비밀번호가 올바르지 않습니다.");
    addMember(room, current, roomNickname);
    log.info("reading-room join-by-code joined roomId={} userId={}", room.id, current.id);
    return new JoinRoomResponse(response(room, current), false);
  }

  @org.springframework.transaction.annotation.Transactional(readOnly = true)
  InviteCodeValidationResponse validateInviteCode(String username, String code) {
    AppUser current = userFeatures.me(username);
    String normalizedCode = normalizeCode(code);
    if (normalizedCode == null) throw new ApiException(HttpStatus.BAD_REQUEST, "INVALID_INVITE_CODE", "유효하지 않거나 만료된 초대 코드입니다.");
    ReadingRoom room = rooms.findByJoinCodeIgnoreCase(normalizedCode)
        .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "INVALID_INVITE_CODE", "유효하지 않거나 만료된 초대 코드입니다."));
    return new InviteCodeValidationResponse(true, room.id, room.name, room.passwordHash != null,
        room.maxMembers, (int) members.countByRoomId(room.id), isMember(room, current));
  }

  @org.springframework.transaction.annotation.Transactional
  RoomResponse joinPublic(String username, Long roomId) {
    AppUser current = userFeatures.me(username);
    ReadingRoom room = rooms.findByIdForUpdate(roomId).orElseThrow(
        () -> new ApiException(HttpStatus.NOT_FOUND, "ROOM_NOT_FOUND", "Room not found."));
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
  RoomResponse setPassword(String username, Long roomId, String password) {
    AppUser current = userFeatures.me(username); ReadingRoom room = room(roomId); requireOwner(room, current);
    room.passwordHash = password == null || password.isBlank() ? null : passwords.encode(password);
    return response(rooms.save(room), current);
  }

  @org.springframework.transaction.annotation.Transactional
  RoomMemberResponse updateMyNickname(String username, Long roomId, String nickname) {
    AppUser current = userFeatures.me(username);
    RoomMember member = members.findByRoomIdAndUserId(roomId, current.id).orElseThrow(() -> new ApiException(HttpStatus.FORBIDDEN, "ROOM_MEMBER_REQUIRED", "방에 가입한 사용자만 변경할 수 있습니다."));
    member.roomNickname = trimToNull(nickname); return memberResponse(members.save(member), current);
  }

  @org.springframework.transaction.annotation.Transactional
  RoomResponse addBook(String username, Long roomId, Long bookId) {
    AppUser current=userFeatures.me(username); ReadingRoom room=room(roomId); requireOwner(room,current); validateBook(bookId);
    if (roomBooks.existsByRoomIdAndBookId(roomId,bookId)) throw new ApiException(HttpStatus.CONFLICT,"DUPLICATE_ROOM_BOOK","이미 방에 추가된 도서입니다.");
    RoomBook item=new RoomBook(); item.roomId=roomId; item.bookId=bookId; item.displayOrder=(int)roomBooks.countByRoomId(roomId); item.addedBy=current.id; roomBooks.save(item);
    return response(room,current);
  }
  @org.springframework.transaction.annotation.Transactional
  RoomResponse removeBook(String username, Long roomId, Long bookId) {
    AppUser current=userFeatures.me(username); ReadingRoom room=room(roomId); requireOwner(room,current);
    if (roomBooks.countByRoomId(roomId) <= 1) throw new ApiException(HttpStatus.CONFLICT,"LAST_ROOM_BOOK","방의 마지막 도서는 삭제할 수 없습니다.");
    RoomBook item=roomBooks.findByRoomIdAndBookId(roomId,bookId).orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND,"ROOM_BOOK_NOT_FOUND","방 도서를 찾을 수 없습니다."));
    roomBooks.delete(item); roomBooks.flush(); normalizeBookOrder(roomId);
    if (java.util.Objects.equals(room.currentBookId,bookId)) room.currentBookId=roomBooks.findByRoomIdOrderByDisplayOrderAsc(roomId).get(0).bookId;
    if (java.util.Objects.equals(room.bookId,bookId)) room.bookId=room.currentBookId;
    return response(rooms.save(room),current);
  }
  @org.springframework.transaction.annotation.Transactional
  RoomResponse moveBook(String username, Long roomId, Long bookId, int target) {
    AppUser current=userFeatures.me(username); ReadingRoom room=room(roomId); requireOwner(room,current);
    List<RoomBook> list=new java.util.ArrayList<>(roomBooks.findByRoomIdOrderByDisplayOrderAsc(roomId));
    RoomBook item=list.stream().filter(x -> x.bookId.equals(bookId)).findFirst().orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND,"ROOM_BOOK_NOT_FOUND","방 도서를 찾을 수 없습니다."));
    if (target < 0 || target >= list.size()) throw new ApiException(HttpStatus.BAD_REQUEST,"INVALID_BOOK_ORDER","도서 순서를 확인해주세요.");
    list.remove(item); list.add(target,item); for(int i=0;i<list.size();i++) list.get(i).displayOrder=i; roomBooks.saveAll(list);
    return response(room,current);
  }
  @org.springframework.transaction.annotation.Transactional
  RoomResponse setCurrentBook(String username, Long roomId, Long bookId) {
    AppUser current=userFeatures.me(username); ReadingRoom room=room(roomId); requireOwner(room,current);
    if(!roomBooks.existsByRoomIdAndBookId(roomId,bookId)) throw new ApiException(HttpStatus.BAD_REQUEST,"ROOM_BOOK_REQUIRED","방에 있는 도서만 현재 도서로 지정할 수 있습니다.");
    room.currentBookId=bookId; room.bookId=bookId; return response(rooms.save(room),current);
  }
  @org.springframework.transaction.annotation.Transactional
  RoomProgressResponse saveProgress(String username,Long roomId,Long bookId,RoomProgressRequest request) {
    AppUser current=userFeatures.me(username); room(roomId);
    if(!members.existsByRoomIdAndUserId(roomId,current.id)) throw new ApiException(HttpStatus.FORBIDDEN,"ROOM_MEMBER_REQUIRED","방에 가입한 사용자만 진행률을 저장할 수 있습니다.");
    if(!roomBooks.existsByRoomIdAndBookId(roomId,bookId)) throw new ApiException(HttpStatus.BAD_REQUEST,"ROOM_BOOK_REQUIRED","방에 추가된 도서만 읽을 수 있습니다.");
    RoomMemberProgress p=roomProgress.findByRoomIdAndUserIdAndBookId(roomId,current.id,bookId).orElseGet(RoomMemberProgress::new);
    p.roomId=roomId;p.userId=current.id;p.bookId=bookId;if(request.progressPercent()!=null)p.progressPercent=request.progressPercent();if(request.lastReadPosition()!=null)p.lastReadPosition=request.lastReadPosition();p.updatedAt=Instant.now();p=roomProgress.save(p);
    return progressResponse(p);
  }
  @org.springframework.transaction.annotation.Transactional(readOnly=true)
  RoomProgressResponse myProgress(String username,Long roomId,Long bookId) { AppUser current=userFeatures.me(username); if(!members.existsByRoomIdAndUserId(roomId,current.id))throw new ApiException(HttpStatus.FORBIDDEN,"ROOM_MEMBER_REQUIRED","방에 가입한 사용자만 볼 수 있습니다."); return roomProgress.findByRoomIdAndUserIdAndBookId(roomId,current.id,bookId).map(this::progressResponse).orElse(new RoomProgressResponse(roomId,current.id,bookId,0,0,null)); }
  @org.springframework.transaction.annotation.Transactional(readOnly=true)
  List<RoomParticipantProgressResponse> participantProgress(String username,Long roomId,Long bookId) {
    AppUser current=userFeatures.me(username); room(roomId);
    if(!members.existsByRoomIdAndUserId(roomId,current.id)) throw new ApiException(HttpStatus.FORBIDDEN,"ROOM_MEMBER_REQUIRED","방에 가입한 사용자만 볼 수 있습니다.");
    if(!roomBooks.existsByRoomIdAndBookId(roomId,bookId)) throw new ApiException(HttpStatus.NOT_FOUND,"ROOM_BOOK_NOT_FOUND","방의 책을 찾을 수 없습니다.");
    java.util.Map<Long,RoomMemberProgress> byUser=roomProgress.findByRoomIdAndBookIdOrderByUpdatedAtDesc(roomId,bookId).stream().collect(java.util.stream.Collectors.toMap(p->p.userId,p->p,(first,ignored)->first));
    return members.findByRoomIdOrderByJoinedAtAsc(roomId).stream().map(member->{
      RoomMemberProgress p=byUser.get(member.userId);
      RoomMemberResponse identity=users.findById(member.userId)
          .map(user->memberResponse(member,user))
          .orElse(new RoomMemberResponse(member.userId,"참여자",member.role,member.joinedAt,member.roomProfileImageUrl));
      return new RoomParticipantProgressResponse(member.userId,identity.nickname(),identity.roomProfileImageUrl(),p==null?0:p.progressPercent,p==null?0:p.lastReadPosition,p==null?null:p.updatedAt,java.util.Objects.equals(member.userId,current.id));
    }).toList();
  }
  private RoomProgressResponse progressResponse(RoomMemberProgress p){return new RoomProgressResponse(p.roomId,p.userId,p.bookId,p.progressPercent,p.lastReadPosition,p.updatedAt);}
  private void normalizeBookOrder(Long roomId){List<RoomBook> list=roomBooks.findByRoomIdOrderByDisplayOrderAsc(roomId);for(int i=0;i<list.size();i++)list.get(i).displayOrder=i;roomBooks.saveAll(list);}

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
  void delete(String username, Long roomId, ProfileImageStorage storage) {
    AppUser current = userFeatures.me(username);
    ReadingRoom room = room(roomId);
    requireOwner(room, current);
    String coverImageUrl = room.coverImageUrl;
    rooms.delete(room);
    rooms.flush();
    storage.delete(coverImageUrl);
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
    if (room.owner != null && room.owner.id != null) return room.owner.id;
    // Older room rows can have an absent owner reference even though their
    // authoritative OWNER/HOST membership still exists. Use that persisted
    // relationship rather than passing a null id to UserRepository.findById.
    if (room.id == null) return null;
    return members.findByRoomIdOrderByJoinedAtAsc(room.id).stream()
        .filter(member -> "OWNER".equals(member.role) || "HOST".equals(member.role))
        .map(member -> member.userId)
        .filter(java.util.Objects::nonNull)
        .findFirst()
        .orElse(null);
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

  /**
   * `bookId` remains the legacy representative-book field. New clients send
   * the ordered `bookIds` list as well, and its first entry is authoritative.
   */
  private List<Long> selectedBookIds(RoomRequest request) {
    List<Long> ids = request.bookIds() == null ? List.of(request.bookId()) : request.bookIds();
    if (ids.isEmpty() || ids.stream().anyMatch(java.util.Objects::isNull)) {
      throw new ApiException(HttpStatus.BAD_REQUEST, "ROOM_BOOK_REQUIRED", "Select at least one book for the room.");
    }
    java.util.LinkedHashSet<Long> unique = new java.util.LinkedHashSet<>(ids);
    if (unique.size() != ids.size()) {
      throw new ApiException(HttpStatus.BAD_REQUEST, "DUPLICATE_ROOM_BOOK", "A book can only be selected once.");
    }
    List<Long> ordered = List.copyOf(unique);
    if (!java.util.Objects.equals(request.bookId(), ordered.get(0))) {
      throw new ApiException(HttpStatus.BAD_REQUEST, "ROOM_BOOK_ORDER_INVALID", "bookId must match the first bookIds entry.");
    }
    ordered.forEach(this::validateBook);
    return ordered;
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
    if (ownerId == null) {
      throw new ApiException(HttpStatus.CONFLICT, "ROOM_OWNER_NOT_FOUND", "This room has an invalid owner.");
    }
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
    List<RoomBookItemResponse> roomBooks = roomBookResponses(room);
    RoomBookResponse book = room.bookId == null ? null : books.findById(room.bookId)
        .map(RoomBookResponse::from).orElse(null);
    // The current book is the room's primary book. Older rooms that predate
    // current_book_id retain their first linked book (display_order ASC).
    // This is computed, not persisted, so existing rows require no migration.
    RoomBookResponse coverBook = roomBooks.stream().filter(RoomBookItemResponse::current)
        .map(RoomBookItemResponse::book).findFirst()
        .orElseGet(() -> roomBooks.isEmpty() ? book : roomBooks.get(0).book());
    return new RoomResponse(room.id, room.name, room.description, room.bookId,
        participants.size(), room.maxMembers, room.isPublic, ownerId,
        ownerUser.nickname, room.createdAt, joined, owner,
        owner ? room.joinCode : null, room.spoilerLockEnabled, room.selectedAiFriendType, participants,
        book, coverBook, ownerUser.nickname, currentMember == null ? null : currentMember.role,
        participants.size(), room.isPublic ? "PUBLIC" : "PRIVATE", room.selectedAiFriendType,
        room.passwordHash != null, room.currentBookId, roomBooks, room.coverImageUrl);
  }

  private List<RoomBookItemResponse> roomBookResponses(ReadingRoom room) { return roomBooks.findByRoomIdOrderByDisplayOrderAsc(room.id).stream().map(item -> books.findById(item.bookId).map(book -> new RoomBookItemResponse(RoomBookResponse.from(book),item.displayOrder,java.util.Objects.equals(room.currentBookId,item.bookId))).orElse(null)).filter(java.util.Objects::nonNull).toList(); }

  private RoomMemberResponse memberResponse(RoomMember member, AppUser user) {
    if (member.userId == null) {
      throw new ApiException(HttpStatus.CONFLICT, "ROOM_MEMBER_USER_NOT_FOUND", "A room member has no user reference.");
    }
    String imageUrl = member.roomProfileImageUrl;
    if (imageUrl == null || imageUrl.isBlank()) {
      imageUrl = userFeatures.profileImageUrlForUserId(member.userId);
    }
    return new RoomMemberResponse(member.userId,
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
    members.saveAndFlush(member);
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
  private String normalizeCode(String value) {
    if (value == null) return null;
    String compact = value.trim()
        .replaceAll("[\\s\\u00A0\\u2000-\\u200B\\u202F\\u205F\\u3000-]+", "")
        .toUpperCase(java.util.Locale.ROOT);
    if (!compact.matches("[A-Z0-9]{8}")) return null;
    return compact.substring(0, 4) + "-" + compact.substring(4);
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
  @PostMapping("/join") JoinRoomResponse join(@RequestParam String code, @RequestParam(required=false) String password, org.springframework.security.core.Authentication authentication) { return service.join(authentication.getName(), code, null, password); }
  @PostMapping("/invite-codes/validate") InviteCodeValidationResponse validateInviteCode(@Valid @RequestBody InviteCodeValidationRequest request, org.springframework.security.core.Authentication authentication) { return service.validateInviteCode(authentication.getName(), request.inviteCode()); }
  @PostMapping("/join-by-code") JoinRoomResponse joinByCode(@Valid @RequestBody JoinRoomCodeRequest request, org.springframework.security.core.Authentication authentication) { return service.join(authentication.getName(), request.inviteCode(), request.roomNickname(), request.password()); }
  @PostMapping("/{roomId}/members") RoomResponse joinPublic(@PathVariable Long roomId, org.springframework.security.core.Authentication authentication) { return service.joinPublic(authentication.getName(), roomId); }
  @PostMapping("/{roomId}/join-code") RoomResponse reissueCode(@PathVariable Long roomId, org.springframework.security.core.Authentication authentication) { return service.reissueCode(authentication.getName(), roomId); }
  @PostMapping("/{roomId}/invite-code/regenerate") RoomResponse regenerateInviteCode(@PathVariable Long roomId, org.springframework.security.core.Authentication authentication) { return service.reissueCode(authentication.getName(), roomId); }
  @PutMapping("/{roomId}/password") RoomResponse password(@PathVariable Long roomId, @Valid @RequestBody RoomPasswordRequest request, org.springframework.security.core.Authentication authentication) { return service.setPassword(authentication.getName(),roomId,request.password()); }
  @PatchMapping("/{roomId}/members/me") RoomMemberResponse nickname(@PathVariable Long roomId, @Valid @RequestBody RoomNicknameRequest request, org.springframework.security.core.Authentication authentication) { return service.updateMyNickname(authentication.getName(),roomId,request.roomNickname()); }
  @PostMapping("/{roomId}/books") RoomResponse addBook(@PathVariable Long roomId,@RequestParam Long bookId,org.springframework.security.core.Authentication authentication){return service.addBook(authentication.getName(),roomId,bookId);}
  @DeleteMapping("/{roomId}/books/{bookId}") RoomResponse removeBook(@PathVariable Long roomId,@PathVariable Long bookId,org.springframework.security.core.Authentication authentication){return service.removeBook(authentication.getName(),roomId,bookId);}
  @PatchMapping("/{roomId}/books/{bookId}/order") RoomResponse moveBook(@PathVariable Long roomId,@PathVariable Long bookId,@Valid @RequestBody RoomBookOrderRequest request,org.springframework.security.core.Authentication authentication){return service.moveBook(authentication.getName(),roomId,bookId,request.order());}
  @PutMapping("/{roomId}/current-book/{bookId}") RoomResponse currentBook(@PathVariable Long roomId,@PathVariable Long bookId,org.springframework.security.core.Authentication authentication){return service.setCurrentBook(authentication.getName(),roomId,bookId);}
  @PostMapping("/{roomId}/books/{bookId}/progress") RoomProgressResponse saveProgress(@PathVariable Long roomId,@PathVariable Long bookId,@Valid @RequestBody(required=false) RoomProgressRequest request,org.springframework.security.core.Authentication authentication){return service.saveProgress(authentication.getName(),roomId,bookId,request==null?new RoomProgressRequest(null,null):request);}
  @GetMapping("/{roomId}/books/{bookId}/progress/me") RoomProgressResponse myProgress(@PathVariable Long roomId,@PathVariable Long bookId,org.springframework.security.core.Authentication authentication){return service.myProgress(authentication.getName(),roomId,bookId);}
  @GetMapping("/{roomId}/books/{bookId}/progress/participants") List<RoomParticipantProgressResponse> participantProgress(@PathVariable Long roomId,@PathVariable Long bookId,org.springframework.security.core.Authentication authentication){return service.participantProgress(authentication.getName(),roomId,bookId);}
  @PutMapping(value = "/{roomId}/members/me/profile-image", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
  RoomMemberResponse uploadMyProfileImage(@PathVariable Long roomId, @RequestPart("profileImage") MultipartFile profileImage, org.springframework.security.core.Authentication authentication) { return service.updateMyProfileImage(authentication.getName(), roomId, profileImage, images); }
  @DeleteMapping("/{roomId}/members/me/profile-image") @ResponseStatus(HttpStatus.NO_CONTENT)
  void deleteMyProfileImage(@PathVariable Long roomId, org.springframework.security.core.Authentication authentication) { service.deleteMyProfileImage(authentication.getName(), roomId, images); }
  @PutMapping(value = "/{roomId}/cover-image", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
  RoomResponse uploadCoverImage(@PathVariable Long roomId, @RequestPart("coverImage") MultipartFile coverImage, org.springframework.security.core.Authentication authentication) { return service.updateCoverImage(authentication.getName(), roomId, coverImage, images); }
  @DeleteMapping("/{roomId}/cover-image") @ResponseStatus(HttpStatus.NO_CONTENT)
  void deleteCoverImage(@PathVariable Long roomId, org.springframework.security.core.Authentication authentication) { service.deleteCoverImage(authentication.getName(), roomId, images); }
  @DeleteMapping("/{roomId}/members/{memberId}") @ResponseStatus(HttpStatus.NO_CONTENT) void kick(@PathVariable Long roomId, @PathVariable Long memberId, org.springframework.security.core.Authentication authentication) { service.kick(authentication.getName(), roomId, memberId); }
  @DeleteMapping("/{roomId}/members/me") @ResponseStatus(HttpStatus.NO_CONTENT) void leave(@PathVariable Long roomId, org.springframework.security.core.Authentication authentication) { service.leave(authentication.getName(), roomId); }
  @DeleteMapping("/{roomId}") @ResponseStatus(HttpStatus.NO_CONTENT) void delete(@PathVariable Long roomId, org.springframework.security.core.Authentication authentication) { service.delete(authentication.getName(), roomId, images); }
}
