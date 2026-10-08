package com.aicamp.changebook;

import org.springframework.web.bind.annotation.*;
import java.util.Map;

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
private final BookParagraphRepository paragraphRepository;
private final AiReadingProgressRepository progressRepository;

// AI 페르소나 생성용
private final GeminiClient geminiClient;
private final CharacterPromptService characterPromptService;



AiReadingController(
        AiReadingService aiReadingService,
        AiReadingNoteRepository noteRepository,
        AiReadingFriendRepository friendRepository,
        UserRepository userRepository,
        BookParagraphRepository paragraphRepository,
        AiReadingProgressRepository progressRepository,
        GeminiClient geminiClient,
        CharacterPromptService characterPromptService
) {
    this.aiReadingService = aiReadingService;
    this.noteRepository = noteRepository;
    this.friendRepository = friendRepository;
    this.userRepository = userRepository;
    this.paragraphRepository = paragraphRepository;
    this.progressRepository = progressRepository;

    this.geminiClient = geminiClient;
    this.characterPromptService = characterPromptService;
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


@PostMapping("/ai-reading-friends")
@ResponseStatus(HttpStatus.CREATED)
@org.springframework.transaction.annotation.Transactional
AiReadingFriendResponse createFriend(
        @Valid @RequestBody CreateAiReadingFriendRequest request,
        org.springframework.security.core.Authentication authentication
) {
    var user = currentUser(authentication);

    // 1. 사용자 입력으로 프롬프트 생성
    String prompt = characterPromptService.makeCharacterPrompt(
            request.name(),
            request.age(),
            request.gender(),
            request.relationship(),
            request.personality(),
            request.speechStyle(),
            request.traits()
    );

    // 2. Gemini로 AI 페르소나 생성
    String generatedPersona = geminiClient.generate(prompt);

    if (generatedPersona == null || generatedPersona.isBlank()) {
        throw new ApiException(
                HttpStatus.SERVICE_UNAVAILABLE,
                "PERSONA_GENERATION_FAILED",
                "AI 독서친구 페르소나 생성에 실패했습니다."
        );
    }

    // 3. AI 독서친구 생성
    AiReadingFriend friend = new AiReadingFriend();

    friend.userId = user.id;
    friend.name = request.name().trim();
    friend.isDefault = false;

    // 4. 사용자 입력 원본 저장
    friend.inputAge = emptyToNull(request.age());
    friend.inputGender = emptyToNull(request.gender());
    friend.inputRelationship = emptyToNull(request.relationship());
    friend.inputPersonality = emptyToNull(request.personality());
    friend.inputSpeechStyle = emptyToNull(request.speechStyle());
    friend.inputTraits = emptyToNull(request.traits());

    // 5. AI 생성 페르소나 저장
    friend.persona = generatedPersona.trim();

    friend.createdAt = java.time.OffsetDateTime.now();
    friend.updatedAt = friend.createdAt;

    // 6. DB에 저장
    return AiReadingFriendResponse.from(
            friendRepository.save(friend)
    );
}


    @DeleteMapping("/ai-reading-friends/{friendId}") @ResponseStatus(HttpStatus.NO_CONTENT)
    @org.springframework.transaction.annotation.Transactional
    void deleteFriend(@PathVariable Long friendId, org.springframework.security.core.Authentication authentication) {
        var user = currentUser(authentication);
        AiReadingFriend friend = friendRepository.findByIdAndUserIdAndIsDefaultFalse(friendId, user.id)
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "AI_FRIEND_NOT_FOUND", "AI 친구를 찾을 수 없습니다."));
        friendRepository.delete(friend);
    }

    
private String emptyToNull(String value) {
    if (value == null || value.isBlank()) {
        return null;
    }
    return value.trim();
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

    
record CreateAiReadingFriendRequest(
        @NotBlank @Size(max = 100) String name,
        String age,
        String gender,
        String relationship,
        String personality,
        String speechStyle,
        String traits
) {}

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
// AI 친구의 독서 진행률 조회
// =========================================================

@GetMapping("/books/{bookId}/ai-reading-friends/{friendId}/progress")
Map<String, Object> getReadingProgress(
        @PathVariable Long bookId,
        @PathVariable Long friendId,
        org.springframework.security.core.Authentication authentication
) {
    var user = currentUser(authentication);
    requireAccessibleFriend(friendId, authentication);

    var paragraphs =
            paragraphRepository.findByBookIdOrderByParagraphOrderAsc(bookId);

    var progress = progressRepository
            .findByUserIdAndFriendIdAndBookId(
                    user.id,
                    friendId,
                    bookId
            );

    int total = paragraphs.size();

    int processed = progress.map(p ->
            (int) paragraphs.stream()
                    .filter(paragraph ->
                            paragraph.paragraphOrder <= p.lastParagraphOrder)
                    .count()
    ).orElse(0);

    boolean completed = progress
            .map(p -> p.completed)
            .orElse(false);

    int percent = completed
            ? 100
            : total == 0
                    ? 0
                    : Math.min(99, processed * 100 / total);

    return Map.of(
            "friendId", friendId,
            "bookId", bookId,
            "percent", percent,
            "completed", completed
    );
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
