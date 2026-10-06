package com.aicamp.changebook;

import jakarta.persistence.*;
import java.time.OffsetDateTime;

@Entity
@Table(name = "change_book_ai_reading_notes")
class AiReadingNote {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    Long id;

    @Column(name = "friend_id", nullable = false)
    Long friendId;

    @Column(name = "book_id", nullable = false)
    Long bookId;

    @Column(name = "paragraph_order", nullable = false)
    Integer paragraphOrder;

    @Column(name = "start_offset", nullable = false)
    Integer startOffset;

    @Column(name = "end_offset", nullable = false)
    Integer endOffset;

    @Column(name = "selected_text", nullable = false, columnDefinition = "TEXT")
    String selectedText;

    @Column(nullable = false, columnDefinition = "TEXT")
    String content;

    @Column(name = "created_at", nullable = false)
    OffsetDateTime createdAt;
}

interface AiReadingNoteRepository
        extends org.springframework.data.jpa.repository.JpaRepository<AiReadingNote, Long> {

    java.util.List<AiReadingNote>
        findByFriendIdAndBookIdOrderByParagraphOrderAsc(Long friendId, Long bookId);
}