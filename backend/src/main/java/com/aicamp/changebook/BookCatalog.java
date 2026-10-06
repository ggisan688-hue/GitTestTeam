package com.aicamp.changebook;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EntityListeners;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import java.time.Instant;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Service;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

@Entity
@Table(name = "change_book_books")
class Book {
  @Id @GeneratedValue(strategy = GenerationType.IDENTITY) Long id;
  @Column(nullable = false, length = 200) String title;
  @Column(nullable = false, length = 100) String author;
  @Column(columnDefinition = "TEXT") String description;
  @Column(name = "cover_image_url", length = 500) String coverImageUrl;
  @Column(length = 50) String category;
  @Column(name = "created_at", nullable = false) Instant createdAt;
  @Column(name = "updated_at", nullable = false) Instant updatedAt;

  // Kept consistent with AppUser: timestamps are maintained by JPA callbacks.
  @PrePersist void onCreate() { createdAt = updatedAt = Instant.now(); }
  @PreUpdate void onUpdate() { updatedAt = Instant.now(); }
}

interface BookRepository extends JpaRepository<Book, Long> {
  List<Book> findAllByOrderByCreatedAtDescIdDesc();
  @Query("select b from Book b where (:category is null or lower(coalesce(b.category,'')) = lower(:category)) and (lower(b.title) like lower(concat('%',:query,'%')) or lower(b.author) like lower(concat('%',:query,'%'))) order by b.createdAt desc, b.id desc")
  List<Book> search(String query, String category);
}

record CreateBookRequest(
    @NotBlank @Size(max = 200) String title,
    @NotBlank @Size(max = 100) String author,
    @Size(max = 10000) String description,
    @Size(max = 500) String coverImageUrl,
    @Size(max = 50) String category) {}

record BookResponse(Long id, String title, String author, String description,
                    String coverImageUrl, String category, Instant createdAt, Instant updatedAt) {
  static BookResponse from(Book book) {
    return new BookResponse(book.id, book.title, book.author, book.description,
        book.coverImageUrl, book.category, book.createdAt, book.updatedAt);
  }
}

@Service
class BookService {
  private final BookRepository books;
  BookService(BookRepository books) { this.books = books; }

  List<BookResponse> list() {
    return books.findAllByOrderByCreatedAtDescIdDesc().stream().map(BookResponse::from).toList();
  }

  BookResponse get(Long id) {
    return books.findById(id).map(BookResponse::from)
        .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "BOOK_NOT_FOUND", "책을 찾을 수 없습니다."));
  }
  List<BookResponse> search(String query, String category) {
    String q = query == null ? "" : query.trim();
    if (q.isEmpty()) throw new ApiException(HttpStatus.BAD_REQUEST, "SEARCH_QUERY_REQUIRED", "검색어를 입력해 주세요.");
    String c = category == null || category.trim().isEmpty() ? null : category.trim();
    return books.search(q, c).stream().limit(50).map(BookResponse::from).toList();
  }

  BookResponse create(CreateBookRequest request) {
    Book book = new Book();
    book.title = request.title().trim();
    book.author = request.author().trim();
    book.description = trimToNull(request.description());
    book.coverImageUrl = trimToNull(request.coverImageUrl());
    book.category = trimToNull(request.category());
    return BookResponse.from(books.save(book));
  }

  private String trimToNull(String value) {
    if (value == null) return null;
    String trimmed = value.trim();
    return trimmed.isEmpty() ? null : trimmed;
  }
}

@RestController
@RequestMapping("/api/books")
class BookController {
  private static final Logger log = LoggerFactory.getLogger(BookController.class);
  private final BookService service;
  BookController(BookService service) { this.service = service; }

  @GetMapping
  List<BookResponse> list() {
    List<BookResponse> books = service.list();
    log.info("GET /api/books -> {} book(s)", books.size());
    return books;
  }

  @GetMapping("/{bookId}")
  BookResponse get(@PathVariable Long bookId) {
    log.info("GET /api/books/{}", bookId);
    return service.get(bookId);
  }

  @GetMapping("/search")
  List<BookResponse> search(@RequestParam String query, @RequestParam(required = false) String category) {
    return service.search(query, category);
  }

  @PostMapping
  ResponseEntity<BookResponse> create(@Valid @RequestBody CreateBookRequest request) {
    return ResponseEntity.status(HttpStatus.CREATED).body(service.create(request));
  }
}
