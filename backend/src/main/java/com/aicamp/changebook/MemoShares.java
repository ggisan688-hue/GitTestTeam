package com.aicamp.changebook;

import jakarta.persistence.*;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotNull;
import java.time.Instant;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;

/** Links existing source notes to rooms; no note content is copied. */
@Entity
@Table(name = "change_book_memo_shares")
class MemoShare {
  @Id @GeneratedValue(strategy = GenerationType.IDENTITY) Long id;
  @Column(name = "personal_memo_id") Long personalMemoId;
  @Column(name = "room_memo_id") Long roomMemoId;
  @Column(name = "target_room_id", nullable = false) Long targetRoomId;
  @Column(name = "shared_by", nullable = false) Long sharedBy;
  @Column(name = "shared_at", nullable = false, insertable = false, updatable = false) Instant sharedAt;
}

interface MemoShareRepository extends JpaRepository<MemoShare, Long> {
  List<MemoShare> findByTargetRoomIdOrderByIdDesc(Long roomId);
  boolean existsByTargetRoomIdAndPersonalMemoId(Long roomId, Long memoId);
  boolean existsByTargetRoomIdAndRoomMemoId(Long roomId, Long memoId);
}

record MemoFeedItem(String source, RoomNoteResponse roomNote, MemoShareResponse sharedMemo) {}

record MemoShareRequest(@NotNull String sourceType, @NotNull Long memoId) {}
record MemoShareResponse(Long shareId, String sourceType, Long memoId, Long bookId,
    Long authorId, String type, int paragraphOrder, Integer startOffset, Integer endOffset,
    String selectedText, String content, String highlightColor, boolean spoilerLocked,
    boolean mine, Instant sharedAt) {}

@Service
class MemoShareService {
  @org.springframework.beans.factory.annotation.Autowired private UserBookProgressRepository globalProgress;
  private final MemoShareRepository shares;
  private final ReadingNoteRepository personal;
  private final ReadingRoomNoteRepository roomNotes;
  private final RoomRepo rooms;
  private final RoomMemberRepo members;
  private final RoomBookRepo roomBooks;
  private final UserFeatureService users;
  private final RoomMemberProgressRepo progress;

  MemoShareService(MemoShareRepository shares, ReadingNoteRepository personal,
      ReadingRoomNoteRepository roomNotes, RoomRepo rooms, RoomMemberRepo members,
      RoomBookRepo roomBooks, UserFeatureService users, RoomMemberProgressRepo progress) {
    this.shares = shares; this.personal = personal; this.roomNotes = roomNotes;
    this.rooms = rooms; this.members = members; this.roomBooks = roomBooks;
    this.users = users; this.progress = progress;
  }

  private AppUser member(String username, Long roomId) {
    AppUser user = users.me(username);
    if (!rooms.existsById(roomId))
      throw new ApiException(HttpStatus.NOT_FOUND, "ROOM_NOT_FOUND", "독서방이 없습니다.");
    if (!members.existsByRoomIdAndUserId(roomId, user.id))
      throw new ApiException(HttpStatus.FORBIDDEN, "ROOM_MEMBER_REQUIRED", "독서방 참여자만 사용할 수 있습니다.");
    return user;
  }

  @Transactional
  MemoShareResponse share(String username, Long targetRoomId, MemoShareRequest request) {
    AppUser user = member(username, targetRoomId);
    if (request.memoId() == null || request.memoId() <= 0)
      throw new ApiException(HttpStatus.BAD_REQUEST, "INVALID_MEMO_ID", "메모 ID를 확인해 주세요.");
    MemoShare share = new MemoShare();
    share.targetRoomId = targetRoomId;
    share.sharedBy = user.id;
    Long bookId;
    if ("PERSONAL".equals(request.sourceType())) {
      ReadingNote note = personal.findById(request.memoId())
          .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "MEMO_NOT_FOUND", "메모가 없습니다."));
      if (!note.user.id.equals(user.id))
        throw new ApiException(HttpStatus.FORBIDDEN, "MEMO_OWNER_REQUIRED", "본인 메모만 공유할 수 있습니다.");
      if (note.noteType != ReadingNoteType.MEMO)
        throw new ApiException(HttpStatus.BAD_REQUEST, "MEMO_ONLY", "메모만 공유할 수 있습니다.");
      if (shares.existsByTargetRoomIdAndPersonalMemoId(targetRoomId, note.id))
        throw new ApiException(HttpStatus.CONFLICT, "ALREADY_SHARED", "이미 공유한 메모입니다.");
      bookId = note.bookId;
      share.personalMemoId = note.id;
    } else if ("ROOM".equals(request.sourceType())) {
      ReadingRoomNote note = roomNotes.findById(request.memoId())
          .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "MEMO_NOT_FOUND", "메모가 없습니다."));
      if (!note.userId.equals(user.id))
        throw new ApiException(HttpStatus.FORBIDDEN, "MEMO_OWNER_REQUIRED", "본인 메모만 공유할 수 있습니다.");
      if (!"MEMO".equals(note.type))
        throw new ApiException(HttpStatus.BAD_REQUEST, "MEMO_ONLY", "메모만 공유할 수 있습니다.");
      if (!members.existsByRoomIdAndUserId(note.roomId, user.id))
        throw new ApiException(HttpStatus.FORBIDDEN, "SOURCE_ROOM_MEMBER_REQUIRED", "원본 독서방 참여자여야 합니다.");
      if (note.roomId.equals(targetRoomId))
        throw new ApiException(HttpStatus.BAD_REQUEST, "SAME_ROOM", "이미 원본 메모가 있는 방입니다.");
      if (shares.existsByTargetRoomIdAndRoomMemoId(targetRoomId, note.id))
        throw new ApiException(HttpStatus.CONFLICT, "ALREADY_SHARED", "이미 공유한 메모입니다.");
      bookId = note.bookId;
      share.roomMemoId = note.id;
    } else {
      throw new ApiException(HttpStatus.BAD_REQUEST, "INVALID_SOURCE_TYPE", "PERSONAL 또는 ROOM을 선택해 주세요.");
    }
    if (!roomBooks.existsByRoomIdAndBookId(targetRoomId, bookId))
      throw new ApiException(HttpStatus.BAD_REQUEST, "ROOM_BOOK_MISMATCH", "대상 독서방에 등록된 책이 아닙니다.");
    shares.saveAndFlush(share);
    return response(user, targetRoomId, share);
  }

  @Transactional(readOnly = true)
  List<MemoShareResponse> list(String username, Long roomId, Long bookId) {
    AppUser user = member(username, roomId);
    return shares.findByTargetRoomIdOrderByIdDesc(roomId).stream()
        .map(share -> response(user, roomId, share))
        .filter(r -> bookId == null || bookId.equals(r.bookId()))
        .toList();
  }

  @Transactional
  void revoke(String username, Long roomId, Long shareId) {
    AppUser user = member(username, roomId);
    MemoShare share = shares.findById(shareId)
        .filter(s -> s.targetRoomId.equals(roomId))
        .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "SHARE_NOT_FOUND", "공유 기록이 없습니다."));
    if (!share.sharedBy.equals(user.id))
      throw new ApiException(HttpStatus.FORBIDDEN, "SHARE_OWNER_REQUIRED", "공유한 사람만 취소할 수 있습니다.");
    shares.delete(share);
  }

  private MemoShareResponse response(AppUser viewer, Long roomId, MemoShare share) {
    Long memoId, bookId, authorId;
    String type, selected, content, color;
    int paragraphOrder;
    Integer start, end;
    String selectionRanges;
    if (share.personalMemoId != null) {
      ReadingNote n = personal.findById(share.personalMemoId).orElseThrow();
      memoId = n.id; bookId = n.bookId; authorId = n.user.id;
      type = n.noteType.name(); paragraphOrder = n.paragraphOrder;
      start = n.startOffset; end = n.endOffset; selected = n.selectedText;
      selectionRanges = n.selectionRanges;
      content = n.memoContent; color = n.highlightColor;
    } else {
      ReadingRoomNote n = roomNotes.findById(share.roomMemoId).orElseThrow();
      memoId = n.id; bookId = n.bookId; authorId = n.userId;
      type = n.type; paragraphOrder = n.paragraphOrder;
      start = n.startOffset; end = n.endOffset; selected = n.selectedText;
      selectionRanges = n.selectionRanges;
      content = n.content; color = n.highlightColor;
    }
    boolean lockEnabled = members.findByRoomIdAndUserId(roomId, viewer.id)
        .map(m -> m.spoilerLockEnabled).orElse(false);
    int lastPosition = globalProgress.findByUserIdAndBookId(viewer.id, bookId)
        .map(p -> Math.max(p.maxReadPosition,p.lastReadPosition)).orElse(0);
    var ranges = NoteRangeSupport.decode(selectionRanges);
    int selectionEnd = ranges.isEmpty() ? paragraphOrder : ranges.get(ranges.size()-1).paragraphOrder();
    boolean locked = lockEnabled && !viewer.id.equals(authorId) && selectionEnd > lastPosition;
    return new MemoShareResponse(share.id, share.personalMemoId != null ? "PERSONAL" : "ROOM",
        memoId, bookId, authorId, type, paragraphOrder,
        locked ? null : start, locked ? null : end,
        locked ? null : selected, locked ? null : content, locked ? null : color,
        locked, viewer.id.equals(authorId), share.sharedAt);
  }
}

@RestController
@RequestMapping("/api/reading-rooms/{roomId}/memo-shares")
class MemoShareController {
  private final MemoShareService service;
  private final ReadingRoomNoteService roomNoteService;
  MemoShareController(MemoShareService service, ReadingRoomNoteService roomNoteService) {
    this.service = service; this.roomNoteService = roomNoteService;
  }

  /** Combined read-only feed. Original note APIs and comment IDs remain untouched. */
  @GetMapping("/feed")
  List<MemoFeedItem> feed(@PathVariable Long roomId, @RequestParam(required = false) Long bookId,
      org.springframework.security.core.Authentication auth) {
    List<MemoFeedItem> result = new java.util.ArrayList<>();
    for (RoomNoteResponse note : roomNoteService.list(auth.getName(), roomId, bookId))
      result.add(new MemoFeedItem("ROOM", note, null));
    for (MemoShareResponse share : service.list(auth.getName(), roomId, bookId))
      result.add(new MemoFeedItem("SHARED", null, share));
    result.sort(java.util.Comparator.comparingInt(item ->
        item.roomNote() != null ? item.roomNote().paragraphOrder() : item.sharedMemo().paragraphOrder()));
    return result;
  }

  @PostMapping
  @ResponseStatus(HttpStatus.CREATED)
  MemoShareResponse share(@PathVariable Long roomId, @Valid @RequestBody MemoShareRequest request,
      org.springframework.security.core.Authentication auth) {
    return service.share(auth.getName(), roomId, request);
  }

  @GetMapping
  List<MemoShareResponse> list(@PathVariable Long roomId, @RequestParam(required = false) Long bookId,
      org.springframework.security.core.Authentication auth) {
    return service.list(auth.getName(), roomId, bookId);
  }

  @DeleteMapping("/{shareId}")
  @ResponseStatus(HttpStatus.NO_CONTENT)
  void revoke(@PathVariable Long roomId, @PathVariable Long shareId,
      org.springframework.security.core.Authentication auth) {
    service.revoke(auth.getName(), roomId, shareId);
  }
}
