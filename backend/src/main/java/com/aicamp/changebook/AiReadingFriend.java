package com.aicamp.changebook;

import jakarta.persistence.*;
import java.time.OffsetDateTime;

@Entity
@Table(name = "change_book_ai_reading_friends")
class AiReadingFriend {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    Long id;

    @Column(name = "user_id")
    Long userId;

    @Column(nullable = false, length = 100)
    String name;

    @Column(nullable = false, columnDefinition = "TEXT")
    String persona;

    @Column(name = "is_default", nullable = false)
    boolean isDefault;

    @Column(name = "created_at", nullable = false)
    OffsetDateTime createdAt;

    @Column(name = "updated_at", nullable = false)
    OffsetDateTime updatedAt;
}

interface AiReadingFriendRepository
        extends org.springframework.data.jpa.repository.JpaRepository<AiReadingFriend, Long> {

    java.util.List<AiReadingFriend> findByIsDefaultTrue();
    java.util.List<AiReadingFriend> findByUserIdAndIsDefaultFalseOrderByCreatedAtAsc(Long userId);
    java.util.Optional<AiReadingFriend> findByIdAndUserIdAndIsDefaultFalse(Long id, Long userId);
}
