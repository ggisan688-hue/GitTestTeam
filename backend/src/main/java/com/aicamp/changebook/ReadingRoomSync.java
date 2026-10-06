package com.aicamp.changebook;

import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.persistence.*;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import org.springframework.context.annotation.Configuration;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.socket.CloseStatus;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketSession;
import org.springframework.web.socket.config.annotation.EnableWebSocket;
import org.springframework.web.socket.config.annotation.WebSocketConfigurer;
import org.springframework.web.socket.config.annotation.WebSocketHandlerRegistry;
import org.springframework.web.socket.handler.TextWebSocketHandler;

/**
 * Events intentionally contain no note/comment text. Clients always retrieve
 * the affected room through the normal REST endpoints, where membership and
 * spoiler filtering are evaluated for that specific JWT user.
 */
@Entity
@Table(name = "change_book_reading_room_sync_events")
class ReadingRoomSyncEvent {
  @Id @GeneratedValue(strategy = GenerationType.IDENTITY) Long id;
  @Column(name = "room_id", nullable = false) Long roomId;
  @Column(name = "book_id", nullable = false) Long bookId;
  @Column(name = "event_type", nullable = false) String eventType;
  @Column(name = "entity_id") Long entityId;
  @Column(name = "version_at", nullable = false) Instant versionAt;
  @Column(name = "created_at", nullable = false) Instant createdAt;
  @PrePersist void created() { if (versionAt == null) versionAt = Instant.now(); createdAt = Instant.now(); }
}

interface ReadingRoomSyncEventRepository extends JpaRepository<ReadingRoomSyncEvent, Long> {
  List<ReadingRoomSyncEvent> findByRoomIdAndIdGreaterThanOrderByIdAsc(Long roomId, Long after);
}

record ReadingRoomSyncEventResponse(Long id, Long roomId, Long bookId, String type, Long entityId, Instant versionAt) {
  static ReadingRoomSyncEventResponse from(ReadingRoomSyncEvent event) {
    return new ReadingRoomSyncEventResponse(event.id, event.roomId, event.bookId, event.eventType, event.entityId, event.versionAt);
  }
}

@Service
class ReadingRoomSyncService {
  private final ReadingRoomSyncEventRepository events;
  private final RoomMemberRepo members;
  private final UserFeatureService users;
  private final RoomSyncSocketHandler sockets;

  ReadingRoomSyncService(ReadingRoomSyncEventRepository events, RoomMemberRepo members,
      UserFeatureService users, RoomSyncSocketHandler sockets) {
    this.events = events; this.members = members; this.users = users; this.sockets = sockets;
  }

  @org.springframework.transaction.annotation.Transactional
  void publish(Long roomId, Long bookId, String type, Long entityId) {
    ReadingRoomSyncEvent event = new ReadingRoomSyncEvent();
    event.roomId = roomId; event.bookId = bookId; event.eventType = type; event.entityId = entityId;
    event = events.save(event);
    ReadingRoomSyncEventResponse response = ReadingRoomSyncEventResponse.from(event);
    // A receiver refetches immediately after receiving this metadata. Sending
    // before the note/comment transaction commits can therefore make it fetch
    // stale data and permanently advance past this event id.
    if (TransactionSynchronizationManager.isSynchronizationActive()) {
      TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
        @Override public void afterCommit() { sockets.broadcast(roomId, response); }
      });
    } else {
      sockets.broadcast(roomId, response);
    }
  }

  List<ReadingRoomSyncEventResponse> after(String username, Long roomId, Long after) {
    AppUser user = users.me(username);
    if (!members.existsByRoomIdAndUserId(roomId, user.id)) {
      throw new ApiException(HttpStatus.FORBIDDEN, "ROOM_MEMBER_REQUIRED", "Join this room first.");
    }
    return events.findByRoomIdAndIdGreaterThanOrderByIdAsc(roomId, Math.max(0, after)).stream()
        .map(ReadingRoomSyncEventResponse::from).toList();
  }
}

@Configuration
@EnableWebSocket
class RoomSyncSocketConfig implements WebSocketConfigurer {
  private final RoomSyncSocketHandler handler;
  private final String allowedOrigins;
  RoomSyncSocketConfig(RoomSyncSocketHandler handler,
      @org.springframework.beans.factory.annotation.Value("${app.cors.allowed-origin-patterns:}") String allowedOrigins) {
    this.handler = handler; this.allowedOrigins = allowedOrigins;
  }
  @Override public void registerWebSocketHandlers(WebSocketHandlerRegistry registry) {
    registry.addHandler(handler, "/ws/reading-room-sync")
        .setAllowedOriginPatterns(AuthApplication.originPatterns(allowedOrigins).toArray(String[]::new));
  }
}

@org.springframework.stereotype.Component
class RoomSyncSocketHandler extends TextWebSocketHandler {
  private final JwtService jwt;
  private final UserFeatureService users;
  private final RoomMemberRepo members;
  private final ObjectMapper json;
  private final Map<Long, Map<String, WebSocketSession>> sessions = new ConcurrentHashMap<>();

  RoomSyncSocketHandler(JwtService jwt, UserFeatureService users, RoomMemberRepo members, ObjectMapper json) {
    this.jwt = jwt; this.users = users; this.members = members; this.json = json;
  }

  @Override public void afterConnectionEstablished(WebSocketSession session) throws Exception {
    Map<String, List<String>> query = org.springframework.web.util.UriComponentsBuilder.fromUri(session.getUri()).build().getQueryParams();
    String token = first(query, "token"); String roomValue = first(query, "roomId");
    try {
      Long roomId = Long.valueOf(roomValue); AppUser user = users.me(jwt.subject(token));
      if (!members.existsByRoomIdAndUserId(roomId, user.id)) throw new IllegalArgumentException();
      session.getAttributes().put("roomId", roomId); session.getAttributes().put("userId", user.id);
      sessions.computeIfAbsent(roomId, ignored -> new ConcurrentHashMap<>()).put(session.getId(), session);
    } catch (RuntimeException invalid) { session.close(CloseStatus.POLICY_VIOLATION); }
  }

  @Override public void afterConnectionClosed(WebSocketSession session, CloseStatus status) {
    Object value = session.getAttributes().get("roomId");
    if (value instanceof Long roomId && sessions.containsKey(roomId)) sessions.get(roomId).remove(session.getId());
  }

  void broadcast(Long roomId, ReadingRoomSyncEventResponse event) {
    for (WebSocketSession session : sessions.getOrDefault(roomId, Map.of()).values()) {
      try {
        Object userValue = session.getAttributes().get("userId");
        if (!(userValue instanceof Long userId) || !members.existsByRoomIdAndUserId(roomId, userId)) {
          session.close(CloseStatus.POLICY_VIOLATION); continue;
        }
        session.sendMessage(new TextMessage(json.writeValueAsString(event)));
      } catch (Exception ignored) { try { session.close(); } catch (Exception closeIgnored) {} }
    }
  }

  private String first(Map<String, List<String>> query, String key) {
    List<String> values = query.get(key); return values == null || values.isEmpty() ? null : values.get(0);
  }
}

@RestController
@RequestMapping("/api/reading-rooms/{roomId}/shared-notes/sync")
class ReadingRoomSyncController {
  private final ReadingRoomSyncService sync;
  ReadingRoomSyncController(ReadingRoomSyncService sync) { this.sync = sync; }
  @GetMapping List<ReadingRoomSyncEventResponse> after(@PathVariable Long roomId,
      @RequestParam(defaultValue = "0") Long after,
      org.springframework.security.core.Authentication authentication) {
    return sync.after(authentication.getName(), roomId, after);
  }
}
