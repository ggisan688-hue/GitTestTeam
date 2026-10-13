package com.aicamp.changebook;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@Entity
@Table(name = "change_book_user_book_progress")
class UserBookProgress {
  @Id @GeneratedValue(strategy = GenerationType.IDENTITY) Long id;
  @ManyToOne(fetch = FetchType.LAZY) @JoinColumn(name = "user_id", nullable = false) AppUser user;
  // Recent-list responses always render book metadata, so load this relation
  // with the progress row rather than exposing an uninitialized lazy proxy.
  @ManyToOne(fetch = FetchType.EAGER) @JoinColumn(name = "book_id", nullable = false) Book book;
  @Column(name = "progress_percent", nullable = false) int progressPercent;
  @Column(name = "last_read_position", nullable = false) int lastReadPosition;
  @Column(name = "last_read_at", nullable = false) Instant lastReadAt;
  @Column(name = "created_at", nullable = false) Instant createdAt;
  @Column(name = "updated_at", nullable = false) Instant updatedAt;

  @PrePersist void onCreate() { Instant now = Instant.now(); createdAt = updatedAt = lastReadAt = now; }
  @PreUpdate void onUpdate() { updatedAt = Instant.now(); }
}

interface UserBookProgressRepository extends JpaRepository<UserBookProgress, Long> {
  java.util.Optional<UserBookProgress> findByUserIdAndBookId(Long userId, Long bookId);
  List<UserBookProgress> findTop20ByUserIdOrderByLastReadAtDesc(Long userId);
  int countByUserIdAndProgressPercentGreaterThanEqual(Long userId, int progressPercent);
}

record ReadingProgressRequest(@Min(0) @Max(100) Integer progressPercent, @Min(0) Integer lastReadPosition) {}
record ReadingProgressResponse(Long bookId, int progressPercent, int lastReadPosition, Instant lastReadAt) {}
record RecentBookResponse(Long id, String title, String author, String description, String coverImageUrl,
                          String category, int progressPercent, int lastReadPosition, Instant lastReadAt) {
  static RecentBookResponse from(UserBookProgress progress) {
    Book book = progress.book;
    return new RecentBookResponse(book.id, book.title, book.author, book.description, book.coverImageUrl,
        book.category, progress.progressPercent, progress.lastReadPosition, progress.lastReadAt);
  }
}

@Service
class ReadingProgressService {
  private final UserBookProgressRepository progressRepository;
  private final UserRepository users;
  private final BookRepository books; private final ReadingActivityLogRepository activities;
  ReadingProgressService(UserBookProgressRepository progressRepository, UserRepository users, BookRepository books, ReadingActivityLogRepository activities) {
    this.progressRepository = progressRepository; this.users = users; this.books = books; this.activities=activities;
  }

  @Transactional ReadingProgressResponse record(String username, Long bookId, ReadingProgressRequest request) {
    AppUser user = users.findByUsername(username)
        .orElseThrow(() -> new ApiException(HttpStatus.UNAUTHORIZED, "UNAUTHORIZED", "인증이 필요합니다."));
    Book book = books.findById(bookId)
        .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "BOOK_NOT_FOUND", "책을 찾을 수 없습니다."));
    UserBookProgress progress = progressRepository.findByUserIdAndBookId(user.id, book.id).orElseGet(() -> {
      UserBookProgress created = new UserBookProgress(); created.user = user; created.book = book; return created;
    });
    int before=progress.id==null?0:progress.lastReadPosition;
    if (request.progressPercent() != null) progress.progressPercent = request.progressPercent();
    if (request.lastReadPosition() != null) progress.lastReadPosition = request.lastReadPosition();
    progress.lastReadAt = Instant.now();
    UserBookProgress saved = progressRepository.save(progress);
    if(request.lastReadPosition()!=null&&saved.lastReadPosition>before){var date=LocalDate.now(ReadingStatisticsService.ZONE);var log=activities.findByUserIdAndBookIdAndActivityDate(user.id,book.id,date).orElseGet(()->{var x=new ReadingActivityLog();x.user=user;x.book=book;x.activityDate=date;return x;});log.paragraphsRead+=saved.lastReadPosition-before;log.lastPositionBefore=before;log.lastPositionAfter=saved.lastReadPosition;activities.save(log);}
    return new ReadingProgressResponse(book.id, saved.progressPercent, saved.lastReadPosition, saved.lastReadAt);
  }

  List<RecentBookResponse> recent(String username) {
    AppUser user = users.findByUsername(username)
        .orElseThrow(() -> new ApiException(HttpStatus.UNAUTHORIZED, "UNAUTHORIZED", "인증이 필요합니다."));
    return progressRepository.findTop20ByUserIdOrderByLastReadAtDesc(user.id).stream().map(RecentBookResponse::from).toList();
  }

  ReadingProgressResponse get(String username, Long bookId) {
    AppUser user = users.findByUsername(username)
        .orElseThrow(() -> new ApiException(HttpStatus.UNAUTHORIZED, "UNAUTHORIZED", "인증이 필요합니다."));
    books.findById(bookId)
        .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "BOOK_NOT_FOUND", "책을 찾을 수 없습니다."));
    return progressRepository.findByUserIdAndBookId(user.id, bookId)
        .map(progress -> new ReadingProgressResponse(bookId, progress.progressPercent, progress.lastReadPosition, progress.lastReadAt))
        .orElse(new ReadingProgressResponse(bookId, 0, 0, null));
  }
}

@RestController
@RequestMapping("/api/books")
class ReadingProgressController {
  private final ReadingProgressService service;
  ReadingProgressController(ReadingProgressService service) { this.service = service; }

  @GetMapping("/recent")
  List<RecentBookResponse> recent(org.springframework.security.core.Authentication authentication) {
    return service.recent(authentication.getName());
  }

  @PostMapping("/{bookId}/reading-progress")
  ReadingProgressResponse record(@PathVariable Long bookId, @Valid @RequestBody(required = false) ReadingProgressRequest request,
                                 org.springframework.security.core.Authentication authentication) {
    return service.record(authentication.getName(), bookId, request == null ? new ReadingProgressRequest(null, null) : request);
  }

  @GetMapping("/{bookId}/reading-progress")
  ReadingProgressResponse get(@PathVariable Long bookId, org.springframework.security.core.Authentication authentication) {
    return service.get(authentication.getName(), bookId);
  }
}
