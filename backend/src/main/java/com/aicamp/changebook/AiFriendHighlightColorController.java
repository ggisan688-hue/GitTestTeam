
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
    @Transactional
    ColorResponse getColor(
            @PathVariable Long friendId,
            Authentication authentication
    ) {
        Long userId = getUserId(authentication);
        checkFriend(friendId, userId);

        var setting = colorRepository.findByUserIdAndFriendId(userId, friendId);
        String color = setting.map(item -> HighlightColorSupport.normalize(item.highlightColor))
                .orElse("#FFF59D");
        setting.ifPresent(item -> {
            if (!color.equals(item.highlightColor)) {
                item.highlightColor = color;
                colorRepository.save(item);
            }
        });
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

        if (request == null || request.highlightColor() == null) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "INVALID_HIGHLIGHT_COLOR", "색상을 선택해 주세요.");
        }
        String color = HighlightColorSupport.normalize(request.highlightColor());

        AiFriendHighlightColor setting = colorRepository
                .findByUserIdAndFriendId(userId, friendId)
                .orElseGet(() -> {
                    AiFriendHighlightColor item = new AiFriendHighlightColor();
                    item.userId = userId;
                    item.friendId = friendId;
                    return item;
                });

        setting.highlightColor = color;
        colorRepository.save(setting);

        return new ColorResponse(setting.highlightColor);
    }
}
