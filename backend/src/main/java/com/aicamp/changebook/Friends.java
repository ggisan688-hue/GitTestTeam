package com.aicamp.changebook;

import jakarta.persistence.*;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;

@Entity
@Table(name = "change_book_friendships")
class Friendship {
  @Id @GeneratedValue(strategy = GenerationType.IDENTITY) Long id;
  @ManyToOne(fetch = FetchType.LAZY) @JoinColumn(name = "requester_id") AppUser requester;
  @ManyToOne(fetch = FetchType.LAZY) @JoinColumn(name = "addressee_id") AppUser addressee;
  @Column(nullable = false) String status;
  @Column(name = "created_at") Instant createdAt;
  @Column(name = "updated_at") Instant updatedAt;
  @PrePersist void created() { createdAt = updatedAt = Instant.now(); }
  @PreUpdate void updated() { updatedAt = Instant.now(); }
}

interface FriendshipRepository extends JpaRepository<Friendship, Long> {
  List<Friendship> findByRequesterIdOrAddresseeId(Long requesterId, Long addresseeId);
  Optional<Friendship> findByRequesterIdAndAddresseeId(Long requesterId, Long addresseeId);
}

record FriendResponse(Long id, String username, String nickname, String status) {}

@org.springframework.stereotype.Service
class FriendService {
  private final FriendshipRepository friendships;
  private final UserRepository users;
  private final UserFeatureService userFeatures;

  FriendService(FriendshipRepository friendships, UserRepository users,
                UserFeatureService userFeatures) {
    this.friendships = friendships;
    this.users = users;
    this.userFeatures = userFeatures;
  }

  private AppUser me(String username) { return userFeatures.me(username); }

  private AppUser target(String username) {
    return users.findByUsername(username).orElseThrow(
        () -> new ApiException(HttpStatus.NOT_FOUND, "USER_NOT_FOUND", "User not found."));
  }

  List<FriendResponse> list(String username) {
    AppUser current = me(username);
    return friendships.findByRequesterIdOrAddresseeId(current.id, current.id).stream()
        .filter(friendship -> "ACCEPTED".equals(friendship.status))
        .map(friendship -> {
          AppUser user = other(friendship, current);
          return new FriendResponse(friendship.id, user.username, user.nickname, "ACCEPTED");
        })
        .toList();
  }

  List<FriendResponse> incoming(String username) {
    AppUser current = me(username);
    return friendships.findByRequesterIdOrAddresseeId(current.id, current.id).stream()
        .filter(friendship -> friendship.addressee.id.equals(current.id) && "PENDING".equals(friendship.status))
        .map(friendship -> new FriendResponse(friendship.id, friendship.requester.username,
            friendship.requester.nickname, "PENDING"))
        .toList();
  }

  List<FriendResponse> search(String username, String query) {
    AppUser current = me(username);
    String term = query == null ? "" : query.trim().toLowerCase();
    if (term.isEmpty()) return List.of();
    return users.findAll().stream()
        .filter(user -> !user.id.equals(current.id))
        .filter(user -> user.username.toLowerCase().contains(term) || user.nickname.toLowerCase().contains(term))
        .limit(30)
        .map(user -> new FriendResponse(user.id, user.username, user.nickname, relationshipStatus(current.id, user.id)))
        .toList();
  }

  void request(String username, String targetUsername) {
    AppUser current = me(username);
    AppUser target = target(targetUsername);
    if (current.id.equals(target.id)) {
      throw new ApiException(HttpStatus.BAD_REQUEST, "SELF_FRIEND_REQUEST", "You cannot send a friend request to yourself.");
    }
    if (findRelationship(current.id, target.id).isPresent()) {
      throw new ApiException(HttpStatus.CONFLICT, "DUPLICATE_FRIEND_REQUEST", "A friend relationship already exists.");
    }
    Friendship friendship = new Friendship();
    friendship.requester = current;
    friendship.addressee = target;
    friendship.status = "PENDING";
    friendships.save(friendship);
    userFeatures.notify(target.id, "FRIEND_REQUEST", "새 친구 요청", current.nickname + "님이 친구 요청을 보냈습니다.", null, current.id);
  }

  void respond(String username, Long requestId, boolean accept) {
    AppUser current = me(username);
    Friendship friendship = friendships.findById(requestId)
        .filter(value -> value.addressee.id.equals(current.id) && "PENDING".equals(value.status))
        .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "FRIEND_REQUEST_NOT_FOUND", "Friend request not found."));
    friendship.status = accept ? "ACCEPTED" : "REJECTED";
    friendships.save(friendship);
    if (accept) {
      userFeatures.notify(friendship.requester.id, "FRIEND_ACCEPTED", "친구 요청 수락",
          current.nickname + "님이 친구 요청을 수락했습니다.", null, current.id);
    }
  }

  void remove(String username, Long friendId) {
    AppUser current = me(username);
    Friendship friendship = friendships.findById(friendId)
        .filter(value -> value.requester.id.equals(current.id) || value.addressee.id.equals(current.id))
        .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "FRIENDSHIP_NOT_FOUND", "Friendship not found."));
    friendships.delete(friendship);
  }

  private AppUser other(Friendship friendship, AppUser current) {
    return friendship.requester.id.equals(current.id) ? friendship.addressee : friendship.requester;
  }

  private Optional<Friendship> findRelationship(Long first, Long second) {
    return friendships.findByRequesterIdAndAddresseeId(first, second)
        .or(() -> friendships.findByRequesterIdAndAddresseeId(second, first));
  }

  private String relationshipStatus(Long first, Long second) {
    return findRelationship(first, second).map(value -> value.status).orElse("NONE");
  }
}

@RestController
@RequestMapping("/api/friends")
class FriendController {
  private final FriendService service;
  FriendController(FriendService service) { this.service = service; }

  @GetMapping List<FriendResponse> list(org.springframework.security.core.Authentication authentication) {
    return service.list(authentication.getName());
  }
  @GetMapping("/requests/incoming") List<FriendResponse> incoming(org.springframework.security.core.Authentication authentication) {
    return service.incoming(authentication.getName());
  }
  @GetMapping("/search") List<FriendResponse> search(@RequestParam String query, org.springframework.security.core.Authentication authentication) {
    return service.search(authentication.getName(), query);
  }
  @PostMapping("/requests/{username}") @ResponseStatus(HttpStatus.NO_CONTENT)
  void request(@PathVariable String username, org.springframework.security.core.Authentication authentication) {
    service.request(authentication.getName(), username);
  }
  @PatchMapping("/requests/{requestId}")
  void respond(@PathVariable Long requestId, @RequestParam boolean accept, org.springframework.security.core.Authentication authentication) {
    service.respond(authentication.getName(), requestId, accept);
  }
  @DeleteMapping("/{friendId}") @ResponseStatus(HttpStatus.NO_CONTENT)
  void remove(@PathVariable Long friendId, org.springframework.security.core.Authentication authentication) {
    service.remove(authentication.getName(), friendId);
  }
}
