package com.aicamp.changebook;

import jakarta.persistence.*;
import java.time.OffsetDateTime;
import java.util.Optional;

@Entity
@Table(name = "change_book_ai_reading_progress")
class AiReadingProgress {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    Long id;

    @Column(name = "friend_id", nullable = false)
    Long friendId;

    @Column(name = "book_id", nullable = false)
    Long bookId;

    @Column(name = "last_paragraph_order", nullable = false)
    Integer lastParagraphOrder;

    @Column(name = "book_memory", nullable = false, columnDefinition = "TEXT")
    String bookMemory;

    @Column(name = "persona_memory", nullable = false, columnDefinition = "TEXT")
    String personaMemory;

    @Column(nullable = false)
    boolean completed;

    @Column(name = "updated_at", nullable = false)
    OffsetDateTime updatedAt;
}

interface AiReadingProgressRepository
        extends org.springframework.data.jpa.repository.JpaRepository<AiReadingProgress, Long> {

    Optional<AiReadingProgress> findByFriendIdAndBookId(
            Long friendId,
            Long bookId
    );
}