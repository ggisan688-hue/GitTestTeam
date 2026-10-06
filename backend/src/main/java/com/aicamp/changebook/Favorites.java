package com.aicamp.changebook;

import jakarta.persistence.*;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;

@Entity
@Table(name = "change_book_user_favorite_books",
    uniqueConstraints = @UniqueConstraint(name = "uq_change_book_user_favorite_book", columnNames = {"user_id", "book_id"}))
class UserFavoriteBook {
  @Id @GeneratedValue(strategy = GenerationType.IDENTITY) Long id;
  @ManyToOne(fetch = FetchType.LAZY) @JoinColumn(name = "user_id", nullable = false) AppUser user;
  @Column(name = "book_id", nullable = false) Long bookId;
  @Column(name = "created_at", nullable = false) Instant createdAt;
  @PrePersist void create() { if (createdAt == null) createdAt = Instant.now(); }
}

interface UserFavoriteBookRepository extends JpaRepository<UserFavoriteBook, Long> {
  @Query("select new com.aicamp.changebook.FavoriteBookResponse(b.id, b.title, b.author, b.description, b.coverImageUrl, b.category, b.createdAt, b.updatedAt, f.createdAt, true) from UserFavoriteBook f join Book b on b.id = f.bookId where f.user.id = :userId order by f.createdAt desc, f.id desc")
  List<FavoriteBookResponse> findResponsesByUserId(@Param("userId") Long userId);
  Optional<UserFavoriteBook> findByUserIdAndBookId(Long userId, Long bookId);
  boolean existsByUserIdAndBookId(Long userId, Long bookId);
  @Modifying(flushAutomatically = true, clearAutomatically = true)
  @Query(value = "insert into change_book_user_favorite_books (user_id, book_id, created_at) values (:userId, :bookId, current_timestamp) on conflict (user_id, book_id) do nothing", nativeQuery = true)
  int insertIgnore(@Param("userId") Long userId, @Param("bookId") Long bookId);
}

record FavoriteBookResponse(Long id, String title, String author, String description,
                            String coverImageUrl, String category, Instant createdAt,
                            Instant updatedAt, Instant favoriteCreatedAt, boolean isFavorite) {
  static FavoriteBookResponse from(UserFavoriteBook favorite, Book book) {
    return new FavoriteBookResponse(book.id, book.title, book.author, book.description,
        book.coverImageUrl, book.category, book.createdAt, book.updatedAt,
        favorite.createdAt, true);
  }
}
record FavoriteStatusResponse(Long bookId, boolean isFavorite, Instant favoriteCreatedAt) {}

@Service
class FavoriteBookService {
  private final UserFavoriteBookRepository favorites;
  private final UserRepository users;
  private final BookRepository books;

  FavoriteBookService(UserFavoriteBookRepository favorites, UserRepository users, BookRepository books) {
    this.favorites = favorites;
    this.users = users;
    this.books = books;
  }

  private AppUser user(String username) {
    return users.findByUsername(username)
        .orElseThrow(() -> new ApiException(HttpStatus.UNAUTHORIZED, "UNAUTHORIZED", "인증이 필요합니다."));
  }

  private Book book(Long bookId) {
    return books.findById(bookId)
        .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "BOOK_NOT_FOUND", "책을 찾을 수 없습니다."));
  }

  List<FavoriteBookResponse> list(String username) {
    AppUser user = user(username);
    return favorites.findResponsesByUserId(user.id);
  }

  FavoriteStatusResponse status(String username, Long bookId) {
    AppUser user = user(username);
    book(bookId);
    return favorites.findByUserIdAndBookId(user.id, bookId)
        .map(favorite -> new FavoriteStatusResponse(bookId, true, favorite.createdAt))
        .orElseGet(() -> new FavoriteStatusResponse(bookId, false, null));
  }

  @Transactional
  FavoriteStatusResponse add(String username, Long bookId) {
    AppUser user = user(username);
    book(bookId);
    // PostgreSQL ON CONFLICT makes repeated or concurrent taps idempotent.
    favorites.insertIgnore(user.id, bookId);
    UserFavoriteBook favorite = favorites.findByUserIdAndBookId(user.id, bookId).orElseThrow();
    return new FavoriteStatusResponse(bookId, true, favorite.createdAt);
  }

  @Transactional
  void remove(String username, Long bookId) {
    AppUser user = user(username);
    UserFavoriteBook favorite = favorites.findByUserIdAndBookId(user.id, bookId)
        .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "FAVORITE_NOT_FOUND", "즐겨찾기한 도서가 아닙니다."));
    favorites.delete(favorite);
  }
}

@RestController
@RequestMapping("/api/books")
class FavoriteBookController {
  private final FavoriteBookService service;
  FavoriteBookController(FavoriteBookService service) { this.service = service; }

  @GetMapping("/favorites")
  List<FavoriteBookResponse> list(org.springframework.security.core.Authentication authentication) {
    return service.list(authentication.getName());
  }

  @GetMapping("/{bookId}/favorite-status")
  FavoriteStatusResponse status(@PathVariable Long bookId, org.springframework.security.core.Authentication authentication) {
    return service.status(authentication.getName(), bookId);
  }

  @PostMapping("/{bookId}/favorite")
  ResponseEntity<FavoriteStatusResponse> add(@PathVariable Long bookId, org.springframework.security.core.Authentication authentication) {
    return ResponseEntity.ok(service.add(authentication.getName(), bookId));
  }

  @DeleteMapping("/{bookId}/favorite")
  @ResponseStatus(HttpStatus.NO_CONTENT)
  void remove(@PathVariable Long bookId, org.springframework.security.core.Authentication authentication) {
    service.remove(authentication.getName(), bookId);
  }
}
