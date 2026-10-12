
package com.aicamp.changebook;

import org.springframework.http.HttpStatus;
import org.springframework.security.core.Authentication;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;

import java.util.Set;

@RestController
@RequestMapping("/api/ai-reading-friends/{friendId}/highlight-color")
class AiFriendHighlightColorController {

    private final AiFriendHighlightColorRepository colorRepository;
    private final AiReadingFriendRepository friendRepository;
    private final UserRepository userRepository;

    AiFriendHighlightColorController(
            AiFriendHighlightColorRepository colorRepository,
            AiReadingFriendRepository friendRepository,
            UserRepository userRepository
    ) {
        this.colorRepository = colorRepository;
        this.friendRepository = friendRepository;
        this.userRepository = userRepository;
    }

    private Long getUserId(Authentication authentication) {
        if (authentication == null || !authentication.isAuthenticated()) {
            throw new ApiException(
                    HttpStatus.UNAUTHORIZED,
                    "UNAUTHORIZED",
                    "로그인이 필요합니다."
            );
        }

        return userRepository.findByUsername(authentication.getName())
                .orElseThrow(() -> new ApiException(
                        HttpStatus.UNAUTHORIZED,
                        "UNAUTHORIZED",
                        "로그인이 필요합니다."
                )).id;
    }

    private void checkFriend(Long friendId, Long userId) {
        AiReadingFriend friend = friendRepository.findById(friendId)
                .orElseThrow(() -> new ApiException(
                        HttpStatus.NOT_FOUND,
                        "AI_FRIEND_NOT_FOUND",
                        "AI 친구를 찾을 수 없습니다."
                ));

        if (!friend.isDefault && !userId.equals(friend.userId)) {
            throw new ApiException(
                    HttpStatus.NOT_FOUND,
                    "AI_FRIEND_NOT_FOUND",
                    "AI 친구를 찾을 수 없습니다."
            );
        }
    }

    record ColorResponse(String highlightColor) {}

    record ColorRequest(String highlightColor) {}

    @GetMapping
    ColorResponse getColor(
            @PathVariable Long friendId,
            Authentication authentication
    ) {
        Long userId = getUserId(authentication);
        checkFriend(friendId, userId);

        String color = colorRepository
                .findByUserIdAndFriendId(userId, friendId)
                .map(item -> item.highlightColor)
                .orElse("YELLOW");

        return new ColorResponse(color);
    }

    @PutMapping
    @Transactional
    ColorResponse saveColor(
            @PathVariable Long friendId,
            @RequestBody ColorRequest request,
            Authentication authentication
    ) {
        Long userId = getUserId(authentication);
        checkFriend(friendId, userId);

        Set<String> allowedColors = Set.of(
                "YELLOW", "PINK", "GREEN",
                "BLUE", "PURPLE", "ORANGE"
        );

        if (request == null ||
                request.highlightColor() == null ||
                !allowedColors.contains(request.highlightColor())) {
            throw new ApiException(
                    HttpStatus.BAD_REQUEST,
                    "INVALID_HIGHLIGHT_COLOR",
                    "지원하지 않는 형광펜 색상입니다."
            );
        }

        AiFriendHighlightColor setting = colorRepository
                .findByUserIdAndFriendId(userId, friendId)
                .orElseGet(() -> {
                    AiFriendHighlightColor item = new AiFriendHighlightColor();
                    item.userId = userId;
                    item.friendId = friendId;
                    return item;
                });

        setting.highlightColor = request.highlightColor();
        colorRepository.save(setting);

        return new ColorResponse(setting.highlightColor);
    }
}
