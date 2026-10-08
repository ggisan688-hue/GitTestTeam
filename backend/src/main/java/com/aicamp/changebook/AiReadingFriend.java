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

    // 사용자가 직접 입력한 AI 독서친구 정보

@Column(name = "input_age")
String inputAge;

@Column(name = "input_gender")
String inputGender;

@Column(name = "input_relationship", columnDefinition = "TEXT")
String inputRelationship;

@Column(name = "input_personality", columnDefinition = "TEXT")
String inputPersonality;

@Column(name = "input_speech_style", columnDefinition = "TEXT")
String inputSpeechStyle;

@Column(name = "input_traits", columnDefinition = "TEXT")
String inputTraits;

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
