package com.aicamp.changebook;

import org.springframework.web.bind.annotation.*;

import java.util.List;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import org.springframework.http.HttpStatus;

@RestController
@RequestMapping("/api")
class AiReadingController {

    private final AiReadingService aiReadingService;
    private final AiReadingNoteRepository noteRepository;
    private final AiReadingFriendRepository friendRepository;
    private final UserRepository userRepository;

    AiReadingController(
            AiReadingService aiReadingService,
            AiReadingNoteRepository noteRepository,
            AiReadingFriendRepository friendRepository, UserRepository userRepository
    ) {
        this.aiReadingService = aiReadingService;
        this.noteRepository = noteRepository;
        this.friendRepository = friendRepository;
        this.userRepository = userRepository;
    }


    // =========================================================
    // 기본 AI 독서 친구 목록
    // =========================================================

    @GetMapping("/ai-reading-friends/defaults")
    List<AiReadingFriendResponse> getDefaultFriends() {

        return friendRepository
                .findByIsDefaultTrue()
                .stream()
                .map(AiReadingFriendResponse::from)
                .toList();
    }

    @GetMapping("/ai-reading-friends")
    List<AiReadingFriendResponse> myFriends(org.springframework.security.core.Authentication authentication) {
        var user = currentUser(authentication);
        return friendRepository.findByUserIdAndIsDefaultFalseOrderByCreatedAtAsc(user.id).stream().map(AiReadingFriendResponse::from).toList();
    }

    @PostMapping("/ai-reading-friends") @ResponseStatus(HttpStatus.CREATED)
    @org.springframework.transaction.annotation.Transactional
    AiReadingFriendResponse createFriend(@Valid @RequestBody CreateAiReadingFriendRequest request, org.springframework.security.core.Authentication authentication) {
        var user = currentUser(authentication);
        AiReadingFriend friend = new AiReadingFriend();
        friend.userId = user.id; friend.name = request.name().trim(); friend.persona = request.persona().trim(); friend.isDefault = false;
        friend.createdAt = friend.updatedAt = java.time.OffsetDateTime.now();
        return AiReadingFriendResponse.from(friendRepository.save(friend));
    }

    @DeleteMapping("/ai-reading-friends/{friendId}") @ResponseStatus(HttpStatus.NO_CONTENT)
    @org.springframework.transaction.annotation.Transactional
    void deleteFriend(@PathVariable Long friendId, org.springframework.security.core.Authentication authentication) {
        var user = currentUser(authentication);
        AiReadingFriend friend = friendRepository.findByIdAndUserIdAndIsDefaultFalse(friendId, user.id)
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "AI_FRIEND_NOT_FOUND", "AI 친구를 찾을 수 없습니다."));
        friendRepository.delete(friend);
    }

    private AppUser currentUser(org.springframework.security.core.Authentication authentication) {
        if (authentication == null || !authentication.isAuthenticated()) throw new ApiException(HttpStatus.UNAUTHORIZED, "UNAUTHORIZED", "로그인이 필요합니다.");
        return userRepository.findByUsername(authentication.getName()).orElseThrow(() -> new ApiException(HttpStatus.UNAUTHORIZED, "UNAUTHORIZED", "로그인이 필요합니다."));
    }

    private void requireAccessibleFriend(Long friendId, org.springframework.security.core.Authentication authentication) {
        var current = currentUser(authentication);
        boolean allowed = friendRepository.findById(friendId)
                .map(friend -> friend.isDefault || current.id.equals(friend.userId))
                .orElse(false);
        if (!allowed) throw new ApiException(HttpStatus.NOT_FOUND, "AI_FRIEND_NOT_FOUND", "AI 친구를 찾을 수 없습니다.");
    }

    record CreateAiReadingFriendRequest(@NotBlank @Size(max=100) String name, @NotBlank @Size(max=4000) String persona) {}


           // =========================================================
    // 해당 책의 AI 메모 생성
    // =========================================================

    @PostMapping(
            "/books/{bookId}/ai-reading-friends/{friendId}/generate"
    )
    List<AiReadingNoteResponse> generate(
            @PathVariable Long bookId,
            @PathVariable Long friendId,
            org.springframework.security.core.Authentication authentication
    ) {
        var user = currentUser(authentication);
        requireAccessibleFriend(friendId, authentication);

        aiReadingService.generateNotes(
                user.id,
                bookId,
                friendId
        );

        return noteRepository
                .findByUserIdAndFriendIdAndBookIdOrderByParagraphOrderAsc(
                        user.id,
                        friendId,
                        bookId
                )
                .stream()
                .map(AiReadingNoteResponse::from)
                .toList();
    }

    // =========================================================
    // 해당 책의 AI 메모 조회
    // =========================================================

    @GetMapping(
            "/books/{bookId}/ai-reading-friends/{friendId}/notes"
    )
    List<AiReadingNoteResponse> getNotes(
            @PathVariable Long bookId,
            @PathVariable Long friendId,
            org.springframework.security.core.Authentication authentication
    ) {
        var user = currentUser(authentication);
        requireAccessibleFriend(friendId, authentication);

        return noteRepository
                .findByUserIdAndFriendIdAndBookIdOrderByParagraphOrderAsc(
                        user.id,
                        friendId,
                        bookId
                )
                .stream()
                .map(AiReadingNoteResponse::from)
                .toList();
    }

    // =========================================================
    // AI 친구 응답
    // =========================================================

    record AiReadingFriendResponse(
            Long id,
            String name,
            boolean isDefault,
            String persona
    ) {

        static AiReadingFriendResponse from(
                AiReadingFriend friend
        ) {

            return new AiReadingFriendResponse(
                    friend.id,
                    friend.name,
                    friend.isDefault,
                    friend.persona
            );
        }
    }


    // =========================================================
    // AI 메모 응답
    // =========================================================

    record AiReadingNoteResponse(
            Long id,
            Long friendId,
            Long bookId,
            Integer paragraphOrder,
            Integer startOffset,
            Integer endOffset,
            String selectedText,
            String content
    ) {

        static AiReadingNoteResponse from(
                AiReadingNote note
        ) {

            return new AiReadingNoteResponse(
                    note.id,
                    note.friendId,
                    note.bookId,
                    note.paragraphOrder,
                    note.startOffset,
                    note.endOffset,
                    note.selectedText,
                    note.content
            );
        }
    }
}
