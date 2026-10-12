
package com.aicamp.changebook;

import jakarta.persistence.*;

@Entity
@Table(
    name = "change_book_ai_friend_highlight_colors",
    uniqueConstraints = @UniqueConstraint(
        columnNames = {"user_id", "friend_id"}
    )
)
class AiFriendHighlightColor {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    Long id;

    @Column(name = "user_id", nullable = false)
    Long userId;

    @Column(name = "friend_id", nullable = false)
    Long friendId;

    @Column(name = "highlight_color", nullable = false, length = 20)
    String highlightColor = "YELLOW";
}

interface AiFriendHighlightColorRepository
    extends org.springframework.data.jpa.repository.JpaRepository<
        AiFriendHighlightColor, Long> {

    java.util.Optional<AiFriendHighlightColor>
        findByUserIdAndFriendId(Long userId, Long friendId);
}
