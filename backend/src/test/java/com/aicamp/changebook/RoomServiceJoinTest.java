package com.aicamp.changebook;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import java.util.List;
import java.util.Optional;
import java.util.concurrent.atomic.AtomicBoolean;
import org.junit.jupiter.api.Test;

class RoomServiceJoinTest {
  @Test
  void joinsLegacyRoomWhenOwnerIsRepresentedByOwnerMembership() {
    RoomRepo rooms = mock(RoomRepo.class);
    RoomMemberRepo members = mock(RoomMemberRepo.class);
    UserRepository users = mock(UserRepository.class);
    BookRepository books = mock(BookRepository.class);
    UserFeatureService userFeatures = mock(UserFeatureService.class);
    RoomService service = new RoomService(rooms, members, users, books, userFeatures);

    AppUser owner = user(10L, "owner", "방장");
    AppUser joiningUser = user(20L, "joiner", "참가자");
    ReadingRoom room = new ReadingRoom();
    room.id = 100L;
    room.name = "교환독서";
    room.maxMembers = 4;
    room.joinCode = "NJV6-3GCD";
    room.isPublic = false;
    // Simulates the malformed legacy row that caused users.findById(null).
    room.owner = null;
    room.ownerId = null;

    RoomMember ownerMember = member(100L, 10L, "OWNER");
    RoomMember joiningMember = member(100L, 20L, "MEMBER");
    AtomicBoolean joined = new AtomicBoolean(false);

    when(userFeatures.me("joiner")).thenReturn(joiningUser);
    when(userFeatures.profileFor(owner))
        .thenReturn(new ProfileResponse(10L, "owner", "방장", null, null, null, null, null));
    when(rooms.findByJoinCodeForUpdate("NJV6-3GCD")).thenReturn(Optional.of(room));
    when(members.existsByRoomIdAndUserId(100L, 20L)).thenAnswer(invocation -> joined.get());
    when(members.countByRoomId(100L)).thenReturn(1L);
    when(members.findByRoomIdOrderByJoinedAtAsc(100L)).thenReturn(List.of(ownerMember));
    when(members.findByRoomIdAndUserId(100L, 20L))
        .thenAnswer(invocation -> joined.get() ? Optional.of(joiningMember) : Optional.empty());
    when(members.saveAndFlush(any(RoomMember.class))).thenAnswer(invocation -> {
      joined.set(true);
      return invocation.getArgument(0);
    });
    when(users.findById(10L)).thenReturn(Optional.of(owner));

    JoinRoomResponse result = service.join("joiner", "njv6-3gcd", null);

    assertFalse(result.alreadyJoined());
    assertEquals(100L, result.room().id());
    assertEquals(10L, result.room().ownerId());
  }

  private static AppUser user(Long id, String username, String nickname) {
    AppUser user = new AppUser();
    user.id = id;
    user.username = username;
    user.nickname = nickname;
    return user;
  }

  private static RoomMember member(Long roomId, Long userId, String role) {
    RoomMember member = new RoomMember();
    member.roomId = roomId;
    member.userId = userId;
    member.role = role;
    return member;
  }
}
