package com.aicamp.changebook;

import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/api")
class AiReadingController {

    private final AiReadingService aiReadingService;
    private final AiReadingNoteRepository noteRepository;
    private final AiReadingFriendRepository friendRepository;

    AiReadingController(
            AiReadingService aiReadingService,
            AiReadingNoteRepository noteRepository,
            AiReadingFriendRepository friendRepository
    ) {
        this.aiReadingService = aiReadingService;
        this.noteRepository = noteRepository;
        this.friendRepository = friendRepository;
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


    // =========================================================
    // 해당 책의 AI 메모 생성
    //
    // 이미 생성된 메모가 있으면 Gemini를 다시 실행하지 않는다.
    // =========================================================

    @PostMapping(
            "/books/{bookId}/ai-reading-friends/{friendId}/generate"
    )
    List<AiReadingNoteResponse> generate(
            @PathVariable Long bookId,
            @PathVariable Long friendId
    ) {

        List<AiReadingNote> existingNotes =
                noteRepository
                        .findByFriendIdAndBookIdOrderByParagraphOrderAsc(
                                friendId,
                                bookId
                        );


        if (existingNotes.isEmpty()) {

            aiReadingService.generateNotes(
                    bookId,
                    friendId
            );
        }


        return noteRepository
                .findByFriendIdAndBookIdOrderByParagraphOrderAsc(
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
            @PathVariable Long friendId
    ) {

        return noteRepository
                .findByFriendIdAndBookIdOrderByParagraphOrderAsc(
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
            boolean isDefault
    ) {

        static AiReadingFriendResponse from(
                AiReadingFriend friend
        ) {

            return new AiReadingFriendResponse(
                    friend.id,
                    friend.name,
                    friend.isDefault
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