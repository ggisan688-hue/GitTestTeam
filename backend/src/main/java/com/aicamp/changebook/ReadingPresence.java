package com.aicamp.changebook;

import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotNull;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Service;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * "지금 책 화면을 열어 둔 친구" 표시용.
 *
 * 책 화면이 열려 있는 동안 앱이 주기적으로(약 15초) 현재 위치를 보낸다.
 * 서버는 DB 없이 메모리에만 들고 있고, 마지막 신호가 [TTL_SECONDS]초 안인 사람만
 * "읽는 중"으로 본다. 앱을 닫거나 탭을 그냥 닫아도 TTL 이 지나면 저절로 사라진다.
 * 서버를 재시작하면 목록이 비지만, 열려 있는 책 화면이 곧 다시 신호를 보내 복구된다.
 */
record ReadingPresenceRequest(@NotNull Long bookId, @NotNull @Min(0) Integer position) {}

record ReadingPresenceResponse(Long userId, Long bookId, int position, Instant updatedAt) {}

@Service
class ReadingPresenceService {
  static final long TTL_SECONDS = 35;

  private record Entry(Long bookId, int position, Instant seenAt) {}

  private final RoomMemberRepo members;
  private final UserFeatureService users;
  private final RoomBookRepo roomBooks;
  // roomId -> (userId -> 마지막 신호)
  private final Map<Long, Map<Long, Entry>> rooms = new ConcurrentHashMap<>();

  ReadingPresenceService(RoomMemberRepo members, UserFeatureService users, RoomBookRepo roomBooks) {
    this.members = members; this.users = users; this.roomBooks = roomBooks;
  }

  private AppUser requireMember(String username, Long roomId) {
    AppUser user = users.me(username);
    if (!members.existsByRoomIdAndUserId(roomId, user.id)) {
      throw new ApiException(HttpStatus.FORBIDDEN, "ROOM_MEMBER_REQUIRED", "방에 가입한 사용자만 볼 수 있습니다.");
    }
    return user;
  }

  void beat(String username, Long roomId, ReadingPresenceRequest request) {
    AppUser user = requireMember(username, roomId);
    if (!roomBooks.existsByRoomIdAndBookId(roomId, request.bookId())) {
      throw new ApiException(HttpStatus.BAD_REQUEST, "ROOM_BOOK_REQUIRED", "방에 추가된 도서만 읽을 수 있습니다.");
    }
    rooms.computeIfAbsent(roomId, ignored -> new ConcurrentHashMap<>())
        .put(user.id, new Entry(request.bookId(), request.position(), Instant.now()));
  }

  void leave(String username, Long roomId) {
    AppUser user = requireMember(username, roomId);
    Map<Long, Entry> room = rooms.get(roomId);
    if (room != null) room.remove(user.id);
  }

  List<ReadingPresenceResponse> active(String username, Long roomId, Long bookId) {
    requireMember(username, roomId);
    Map<Long, Entry> room = rooms.get(roomId);
    if (room == null) return List.of();
    Instant cutoff = Instant.now().minusSeconds(TTL_SECONDS);
    room.values().removeIf(entry -> entry.seenAt().isBefore(cutoff));
    return room.entrySet().stream()
        .filter(e -> bookId == null || bookId.equals(e.getValue().bookId()))
        .map(e -> new ReadingPresenceResponse(
            e.getKey(), e.getValue().bookId(), e.getValue().position(), e.getValue().seenAt()))
        .toList();
  }
}

@RestController
@RequestMapping("/api/reading-rooms/{roomId}/presence")
class ReadingPresenceController {
  private final ReadingPresenceService presence;

  ReadingPresenceController(ReadingPresenceService presence) { this.presence = presence; }

  @PostMapping
  ResponseEntity<Void> beat(@PathVariable Long roomId, @jakarta.validation.Valid @RequestBody ReadingPresenceRequest request,
      org.springframework.security.core.Authentication authentication) {
    presence.beat(authentication.getName(), roomId, request);
    return ResponseEntity.noContent().build();
  }

  @DeleteMapping
  ResponseEntity<Void> leave(@PathVariable Long roomId, org.springframework.security.core.Authentication authentication) {
    presence.leave(authentication.getName(), roomId);
    return ResponseEntity.noContent().build();
  }

  @GetMapping
  List<ReadingPresenceResponse> active(@PathVariable Long roomId, @RequestParam(required = false) Long bookId,
      org.springframework.security.core.Authentication authentication) {
    return presence.active(authentication.getName(), roomId, bookId);
  }
}