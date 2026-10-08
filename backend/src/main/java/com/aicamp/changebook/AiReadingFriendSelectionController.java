package com.aicamp.changebook;

import org.springframework.http.HttpStatus;
import org.springframework.security.core.Authentication;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;

import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;

@RestController
@RequestMapping("/api/books/{bookId}/ai-reading-friend-selections")
class AiReadingFriendSelectionController {

    private final AiReadingFriendSelectionRepository selectionRepository;
    private final AiReadingFriendRepository friendRepository;
    private final UserRepository userRepository;

    AiReadingFriendSelectionController(
            AiReadingFriendSelectionRepository selectionRepository,
            AiReadingFriendRepository friendRepository,
            UserRepository userRepository
    ) {
        this.selectionRepository = selectionRepository;
        this.friendRepository = friendRepository;
        this.userRepository = userRepository;
    }

    private AppUser currentUser(Authentication authentication) {
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
                ));
    }

    @GetMapping
    List<Long> getSelections(
            @PathVariable Long bookId,
            Authentication authentication
    ) {
        AppUser user = currentUser(authentication);

        return selectionRepository.findByUserIdAndBookId(user.id, bookId)
                .stream()
                .map(selection -> selection.friendId)
                .toList();
    }

    record SaveSelectionsRequest(List<Long> friendIds) {}

    @PutMapping
    @Transactional
    List<Long> saveSelections(
            @PathVariable Long bookId,
            @RequestBody SaveSelectionsRequest request,
            Authentication authentication
    ) {
        AppUser user = currentUser(authentication);

        if (request == null || request.friendIds() == null) {
            throw new ApiException(
                    HttpStatus.BAD_REQUEST,
                    "INVALID_SELECTION",
                    "AI 친구 선택 목록이 필요합니다."
            );
        }

        Set<Long> selectedIds = new LinkedHashSet<>(request.friendIds());

        for (Long friendId : selectedIds) {
            if (friendId == null) {
                throw new ApiException(
                        HttpStatus.BAD_REQUEST,
                        "INVALID_SELECTION",
                        "잘못된 AI 친구 ID입니다."
                );
            }

            AiReadingFriend friend = friendRepository.findById(friendId)
                    .orElseThrow(() -> new ApiException(
                            HttpStatus.NOT_FOUND,
                            "AI_FRIEND_NOT_FOUND",
                            "AI 친구를 찾을 수 없습니다."
                    ));

            if (!friend.isDefault && !user.id.equals(friend.userId)) {
                throw new ApiException(
                        HttpStatus.NOT_FOUND,
                        "AI_FRIEND_NOT_FOUND",
                        "AI 친구를 찾을 수 없습니다."
                );
            }
        }

        selectionRepository.deleteByUserIdAndBookId(user.id, bookId);
        selectionRepository.flush();

        for (Long friendId : selectedIds) {
            selectionRepository.save(
                    new AiReadingFriendSelection(user.id, bookId, friendId)
            );
        }

        return List.copyOf(selectedIds);
    }
}