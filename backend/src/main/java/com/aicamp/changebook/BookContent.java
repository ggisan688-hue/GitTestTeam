package com.aicamp.changebook;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@Entity
@Table(name = "change_book_paragraphs")
class BookParagraph {
  @Id @GeneratedValue(strategy = GenerationType.IDENTITY) Long id;
  @Column(name = "book_id", nullable = false) Long bookId;
  @Column(name = "paragraph_order", nullable = false) Integer paragraphOrder;
  @Column(nullable = false, columnDefinition = "TEXT") String content;
}

interface BookParagraphRepository extends JpaRepository<BookParagraph, Long> {
  List<BookParagraph> findByBookIdOrderByParagraphOrderAsc(Long bookId);
  java.util.Optional<BookParagraph> findByBookIdAndParagraphOrder(Long bookId, Integer paragraphOrder);
}

record ParagraphResponse(Long id, Integer order, String text) {
  static ParagraphResponse from(BookParagraph paragraph) {
    return new ParagraphResponse(paragraph.id, paragraph.paragraphOrder, paragraph.content);
  }
}
record BookContentResponse(Long bookId, String title, List<ParagraphResponse> paragraphs) {}

@Service
class BookContentService {
  private final BookRepository books;
  private final BookParagraphRepository paragraphs;
  BookContentService(BookRepository books, BookParagraphRepository paragraphs) {
    this.books = books; this.paragraphs = paragraphs;
  }

  BookContentResponse content(Long bookId) {
    Book book = books.findById(bookId)
        .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "BOOK_NOT_FOUND", "책을 찾을 수 없습니다."));
    List<ParagraphResponse> result = paragraphs.findByBookIdOrderByParagraphOrderAsc(bookId).stream()
        .map(ParagraphResponse::from).toList();
    if (result.isEmpty()) {
      throw new ApiException(HttpStatus.NOT_FOUND, "BOOK_CONTENT_NOT_FOUND", "아직 읽을 수 있는 본문이 등록되지 않았습니다.");
    }
    return new BookContentResponse(book.id, book.title, result);
  }
}

@RestController
@RequestMapping("/api/books")
class BookContentController {
  private final BookContentService service;
  BookContentController(BookContentService service) { this.service = service; }

  // This path has two segments after /api/books, so it is deliberately not
  // covered by the public GET /api/books/* security matcher.
  @GetMapping("/{bookId}/content")
  BookContentResponse content(@PathVariable Long bookId,
                              org.springframework.security.core.Authentication authentication) {
    return service.content(bookId);
  }
}
