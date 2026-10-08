package com.aicamp.changebook;

import jakarta.persistence.*;
import org.springframework.data.jpa.repository.JpaRepository;

import java.io.Serializable;
import java.util.List;
import java.util.Objects;

@Entity
@Table(name = "change_book_ai_reading_friend_selections")
@IdClass(AiReadingFriendSelection.Key.class)
class AiReadingFriendSelection {

    @Id
    @Column(name = "user_id")
    Long userId;

    @Id
    @Column(name = "book_id")
    Long bookId;

    @Id
    @Column(name = "friend_id")
    Long friendId;

    protected AiReadingFriendSelection() {
    }

    AiReadingFriendSelection(Long userId, Long bookId, Long friendId) {
        this.userId = userId;
        this.bookId = bookId;
        this.friendId = friendId;
    }

    public static class Key implements Serializable {
        public Long userId;
        public Long bookId;
        public Long friendId;

        public Key() {
        }

        @Override
        public boolean equals(Object other) {
            if (this == other) return true;
            if (!(other instanceof Key key)) return false;

            return Objects.equals(userId, key.userId)
                    && Objects.equals(bookId, key.bookId)
                    && Objects.equals(friendId, key.friendId);
        }

        @Override
        public int hashCode() {
            return Objects.hash(userId, bookId, friendId);
        }
    }
}

interface AiReadingFriendSelectionRepository
        extends JpaRepository<AiReadingFriendSelection, AiReadingFriendSelection.Key> {

    List<AiReadingFriendSelection> findByUserIdAndBookId(
            Long userId,
            Long bookId
    );

    void deleteByUserIdAndBookId(
            Long userId,
            Long bookId
    );
}