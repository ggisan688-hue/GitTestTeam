package com.aicamp.changebook;

import jakarta.persistence.*;
import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import java.math.BigDecimal;
import java.time.Instant;
import java.util.*;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;

@Entity @Table(name = "change_book_chapters")
class ReaderChapter {
  @Id @GeneratedValue(strategy = GenerationType.IDENTITY) Long id;
  @Column(name="book_id", nullable=false) Long bookId;
  @Column(name="chapter_number", nullable=false) int chapterNumber;
  @Column(name="chapter_title", nullable=false) String chapterTitle;
  @Column(name="start_paragraph_order", nullable=false) int startParagraphOrder;
}
interface ReaderChapterRepository extends JpaRepository<ReaderChapter, Long> {
  List<ReaderChapter> findByBookIdOrderByChapterNumberAsc(Long bookId);
}
record ChapterResponse(Long id, int chapterNumber, String title, int startParagraphOrder) {
  static ChapterResponse from(ReaderChapter c) { return new ChapterResponse(c.id, c.chapterNumber, c.chapterTitle, c.startParagraphOrder); }
}

enum ReadingNoteType { HIGHLIGHT, MEMO, BOOKMARK }
@Entity @Table(name="change_book_reading_notes")
class ReadingNote {
  @Id @GeneratedValue(strategy=GenerationType.IDENTITY) Long id;
  @ManyToOne(fetch=FetchType.LAZY) @JoinColumn(name="user_id", nullable=false) AppUser user;
  @Column(name="book_id", nullable=false) Long bookId;
  @Column(name="paragraph_order", nullable=false) int paragraphOrder;
  @Enumerated(EnumType.STRING) @Column(name="note_type", nullable=false) ReadingNoteType noteType;
  @Column(name="memo_content", columnDefinition="TEXT") String memoContent;
  @Column(name="selected_text", columnDefinition="TEXT") String selectedText;
  @Column(name="start_offset") Integer startOffset;
  @Column(name="end_offset") Integer endOffset;
  @Column(name="highlight_color") String highlightColor;
  @Column(name="created_at", nullable=false) Instant createdAt;
  @Column(name="updated_at", nullable=false) Instant updatedAt;
  @PrePersist void create() { createdAt=updatedAt=Instant.now(); }
  @PreUpdate void update() { updatedAt=Instant.now(); }
}
interface ReadingNoteRepository extends JpaRepository<ReadingNote, Long> {
  List<ReadingNote> findByUserIdAndBookIdOrderByCreatedAtDesc(Long userId, Long bookId);
  List<ReadingNote> findByUserIdAndBookIdAndNoteTypeOrderByCreatedAtDesc(Long userId, Long bookId, ReadingNoteType type);
  Optional<ReadingNote> findByUserIdAndBookIdAndParagraphOrderAndNoteType(Long userId, Long bookId, int paragraphOrder, ReadingNoteType type);
  Optional<ReadingNote> findByUserIdAndBookIdAndParagraphOrderAndStartOffsetAndEndOffsetAndNoteType(Long userId, Long bookId, int paragraphOrder, Integer startOffset, Integer endOffset, ReadingNoteType type);
  List<ReadingNote> findAllByUserIdAndBookIdAndParagraphOrderAndNoteType(Long userId, Long bookId, int paragraphOrder, ReadingNoteType type);
  long countByUserIdAndNoteType(Long userId, ReadingNoteType type);
  long countByUserIdAndNoteTypeAndCreatedAtBetween(Long userId, ReadingNoteType type, Instant from, Instant to);
  Optional<ReadingNote> findByIdAndUserIdAndBookId(Long id, Long userId, Long bookId);
  @Modifying(clearAutomatically=true, flushAutomatically=true)
  @Query("delete from ReadingNote n where n.user.id=:userId and n.bookId=:bookId")
  int deleteAllForUserAndBook(@Param("userId") Long userId, @Param("bookId") Long bookId);
  @Modifying(clearAutomatically=true, flushAutomatically=true)
  @Query("delete from ReadingNote n where n.user.id=:userId and n.bookId=:bookId and n.noteType=:type")
  int deleteAllForUserAndBookAndType(@Param("userId") Long userId, @Param("bookId") Long bookId, @Param("type") ReadingNoteType type);
}
record ReadingNoteRequest(@NotNull ReadingNoteType noteType, @Min(1) Integer paragraphOrder,
  @Size(max=3000) String memoContent, @Size(max=3000) String selectedText,
  @Min(0) Integer startOffset, @Min(0) Integer endOffset, @Size(max=20) String highlightColor) {}
record ReadingNoteUpdateRequest(@Size(max=3000) String memoContent, @Size(max=20) String highlightColor) {}
record ReadingNoteResponse(Long id, Long noteId, String type, int paragraphOrder, String memoContent, String selectedText,
  Integer startOffset, Integer endOffset, String highlightColor, String paragraphPreview, Instant createdAt, Instant updatedAt) {
  static ReadingNoteResponse from(ReadingNote n, String preview) { return new ReadingNoteResponse(n.id,n.id,n.noteType.name(),n.paragraphOrder,n.memoContent,n.selectedText,n.startOffset,n.endOffset,n.highlightColor,preview,n.createdAt,n.updatedAt); }
}
record ReadingNoteBulkDeleteResponse(int deletedCount) {}

@Entity @Table(name="change_book_reader_settings")
class ReaderSettings {
 @Id @GeneratedValue(strategy=GenerationType.IDENTITY) Long id;
 @ManyToOne(fetch=FetchType.LAZY) @JoinColumn(name="user_id",nullable=false,unique=true) AppUser user;
 @Column(name="font_scale",nullable=false) BigDecimal fontScale;
 @Column(name="line_height_step",nullable=false) int lineHeightStep;
 @Column(nullable=false) String theme;
 @Column(name="two_column",nullable=false) boolean twoColumn;
 @Column(name="keep_screen_on",nullable=false) boolean keepScreenOn;
 @Column(name="default_highlight_color",nullable=false) String defaultHighlightColor;
 @PrePersist void create(){ if(fontScale==null)fontScale=BigDecimal.ONE; if(theme==null)theme="LIGHT"; if(defaultHighlightColor==null)defaultHighlightColor="#FFF59D"; }
}
interface ReaderSettingsRepository extends JpaRepository<ReaderSettings,Long>{ Optional<ReaderSettings> findByUserId(Long userId); }
record ReaderSettingsRequest(@DecimalMin("0.80") @DecimalMax("1.40") BigDecimal fontScale, @Min(0) @Max(2) Integer lineHeightStep, @Pattern(regexp="LIGHT|SEPIA|DARK") String theme, Boolean twoColumn, Boolean keepScreenOn, String defaultHighlightColor) {}
record ReaderSettingsResponse(double fontScale,int lineHeightStep,String theme,boolean twoColumn,boolean keepScreenOn,String defaultHighlightColor){
 static ReaderSettingsResponse from(ReaderSettings s){return new ReaderSettingsResponse(s.fontScale.doubleValue(),s.lineHeightStep,s.theme,s.twoColumn,s.keepScreenOn,s.defaultHighlightColor);}
}

@Service class ReaderFeatureService {
 private final UserRepository users; private final BookRepository books; private final BookParagraphRepository paragraphs;
 private final ReaderChapterRepository chapters; private final ReadingNoteRepository notes; private final ReaderSettingsRepository settings;
 private static final Set<String> HIGHLIGHT_COLORS=Set.of("#FFF59D","#A5D6A7","#90CAF9","#FFCCBC","#CE93D8");
 ReaderFeatureService(UserRepository u, BookRepository b, BookParagraphRepository p, ReaderChapterRepository c, ReadingNoteRepository n, ReaderSettingsRepository s){users=u;books=b;paragraphs=p;chapters=c;notes=n;settings=s;}
 private AppUser user(String username){return users.findByUsername(username).orElseThrow(()->new ApiException(HttpStatus.UNAUTHORIZED,"UNAUTHORIZED","인증이 필요합니다."));}
 private void book(Long id){if(!books.existsById(id))throw new ApiException(HttpStatus.NOT_FOUND,"BOOK_NOT_FOUND","책을 찾을 수 없습니다.");}
 List<ChapterResponse> chapters(Long id){book(id); return chapters.findByBookIdOrderByChapterNumberAsc(id).stream().map(ChapterResponse::from).toList();}
 List<ReadingNoteResponse> notes(String username,Long bookId,ReadingNoteType type){AppUser u=user(username);book(bookId); List<ReadingNote> all=type==null?notes.findByUserIdAndBookIdOrderByCreatedAtDesc(u.id,bookId):notes.findByUserIdAndBookIdAndNoteTypeOrderByCreatedAtDesc(u.id,bookId,type);return all.stream().map(n->ReadingNoteResponse.from(n,preview(bookId,n.paragraphOrder))).toList();}
 @Transactional ReadingNoteResponse create(String username,Long bookId,ReadingNoteRequest r){
  AppUser u=user(username); book(bookId);
  var paragraph=paragraphs.findByBookIdAndParagraphOrder(bookId,r.paragraphOrder()).orElseThrow(()->new ApiException(HttpStatus.NOT_FOUND,"PARAGRAPH_NOT_FOUND","본문 위치를 찾을 수 없습니다."));
  boolean selectionFieldsPresent=r.startOffset()!=null||r.endOffset()!=null||r.selectedText()!=null;
  if(r.noteType()==ReadingNoteType.HIGHLIGHT||selectionFieldsPresent){
   if(r.startOffset()==null||r.endOffset()==null||r.selectedText()==null||r.endOffset()<=r.startOffset()||r.endOffset()>paragraph.content.length())throw new ApiException(HttpStatus.BAD_REQUEST,"INVALID_REQUEST","선택 범위를 확인해 주세요.");
   String actual=paragraph.content.substring(r.startOffset(),r.endOffset());
   if(!actual.equals(r.selectedText()))throw new ApiException(HttpStatus.BAD_REQUEST,"INVALID_REQUEST","선택한 문장이 본문과 일치하지 않습니다.");
  }
  if(r.noteType()==ReadingNoteType.HIGHLIGHT){if(r.highlightColor()!=null&&!HIGHLIGHT_COLORS.contains(r.highlightColor()))throw new ApiException(HttpStatus.BAD_REQUEST,"INVALID_HIGHLIGHT_COLOR","형광펜 색상을 확인해 주세요.");normalizeHighlights(u,bookId,r.paragraphOrder(),r.startOffset(),r.endOffset(),paragraph.content);}
  if(r.noteType()==ReadingNoteType.MEMO&&(r.memoContent()==null||r.memoContent().trim().isEmpty()))throw new ApiException(HttpStatus.BAD_REQUEST,"INVALID_REQUEST","빈 메모는 저장할 수 없습니다.");
  if(r.noteType()==ReadingNoteType.BOOKMARK){var exists=notes.findByUserIdAndBookIdAndParagraphOrderAndNoteType(u.id,bookId,r.paragraphOrder(),ReadingNoteType.BOOKMARK);if(exists.isPresent())return ReadingNoteResponse.from(exists.get(),preview(bookId,r.paragraphOrder()));}
  ReadingNote n=new ReadingNote();n.user=u;n.bookId=bookId;n.paragraphOrder=r.paragraphOrder();n.noteType=r.noteType();n.memoContent=r.memoContent()==null?null:r.memoContent().trim();n.selectedText=r.selectedText();n.startOffset=r.startOffset();n.endOffset=r.endOffset();n.highlightColor=r.noteType()==ReadingNoteType.HIGHLIGHT?(r.highlightColor()!=null?r.highlightColor():settings.findByUserId(u.id).map(s->s.defaultHighlightColor).orElse("#FFF59D")):r.highlightColor();
  try{n=notes.saveAndFlush(n);}catch(DataIntegrityViolationException ex){if(r.noteType()==ReadingNoteType.HIGHLIGHT)throw new ApiException(HttpStatus.CONFLICT,"DUPLICATE_HIGHLIGHT","이미 형광펜 표시된 문장입니다.");throw ex;}
 return ReadingNoteResponse.from(n,preview(bookId,n.paragraphOrder));
 }
 private void normalizeHighlights(AppUser user,Long bookId,int order,int start,int end,String content){
  var overlaps=notes.findAllByUserIdAndBookIdAndParagraphOrderAndNoteType(user.id,bookId,order,ReadingNoteType.HIGHLIGHT).stream().filter(n->n.startOffset!=null&&n.endOffset!=null&&n.startOffset<end&&n.endOffset>start).toList();
  if(overlaps.isEmpty())return;
  var remnants=new ArrayList<ReadingNote>();
  for(var old:overlaps){
   if(old.startOffset<start)remnants.add(highlightPart(user,bookId,order,old,old.startOffset,start,content));
   if(old.endOffset>end)remnants.add(highlightPart(user,bookId,order,old,end,old.endOffset,content));
  }
  notes.deleteAll(overlaps); notes.flush();
  notes.saveAll(remnants);
 }
 private ReadingNote highlightPart(AppUser user,Long bookId,int order,ReadingNote source,int start,int end,String content){ReadingNote n=new ReadingNote();n.user=user;n.bookId=bookId;n.paragraphOrder=order;n.noteType=ReadingNoteType.HIGHLIGHT;n.startOffset=start;n.endOffset=end;n.selectedText=content.substring(start,end);n.highlightColor=source.highlightColor==null?"#FFF59D":source.highlightColor;return n;}
 ReadingNoteResponse update(String username,Long bookId,Long noteId,ReadingNoteUpdateRequest r){AppUser u=user(username);ReadingNote n=notes.findByIdAndUserIdAndBookId(noteId,u.id,bookId).orElseThrow(()->new ApiException(HttpStatus.NOT_FOUND,"READING_NOTE_NOT_FOUND","독서노트를 찾을 수 없습니다."));if(r.memoContent()!=null){if(n.noteType!=ReadingNoteType.MEMO||r.memoContent().trim().isEmpty())throw new ApiException(HttpStatus.BAD_REQUEST,"INVALID_REQUEST","메모 내용을 확인해 주세요.");n.memoContent=r.memoContent().trim();}if(r.highlightColor()!=null){if(n.noteType!=ReadingNoteType.HIGHLIGHT||!HIGHLIGHT_COLORS.contains(r.highlightColor()))throw new ApiException(HttpStatus.BAD_REQUEST,"INVALID_HIGHLIGHT_COLOR","형광펜 색상을 확인해 주세요.");n.highlightColor=r.highlightColor();}return ReadingNoteResponse.from(notes.save(n),preview(bookId,n.paragraphOrder));}
 void delete(String username,Long bookId,Long noteId){AppUser u=user(username);ReadingNote n=notes.findByIdAndUserIdAndBookId(noteId,u.id,bookId).orElseThrow(()->new ApiException(HttpStatus.NOT_FOUND,"READING_NOTE_NOT_FOUND","독서노트를 찾을 수 없습니다."));notes.delete(n);}
 @Transactional ReadingNoteBulkDeleteResponse deleteAll(String username,Long bookId,ReadingNoteType type){AppUser u=user(username);book(bookId);int count=type==null?notes.deleteAllForUserAndBook(u.id,bookId):notes.deleteAllForUserAndBookAndType(u.id,bookId,type);return new ReadingNoteBulkDeleteResponse(count);}
 private String preview(Long bookId,int order){return paragraphs.findByBookIdAndParagraphOrder(bookId,order).map(p->p.content.length()>120?p.content.substring(0,120)+"…":p.content).orElse("");}
 ReaderSettingsResponse settings(String username){AppUser u=user(username);return ReaderSettingsResponse.from(settings.findByUserId(u.id).orElseGet(()->defaults(u)));}
 ReaderSettingsResponse saveSettings(String username,ReaderSettingsRequest r){AppUser u=user(username);ReaderSettings s=settings.findByUserId(u.id).orElseGet(()->defaults(u));if(r.fontScale()!=null)s.fontScale=r.fontScale();if(r.lineHeightStep()!=null)s.lineHeightStep=r.lineHeightStep();if(r.theme()!=null)s.theme=r.theme();if(r.twoColumn()!=null)s.twoColumn=r.twoColumn();if(r.keepScreenOn()!=null)s.keepScreenOn=r.keepScreenOn();if(r.defaultHighlightColor()!=null){if(!HIGHLIGHT_COLORS.contains(r.defaultHighlightColor()))throw new ApiException(HttpStatus.BAD_REQUEST,"INVALID_HIGHLIGHT_COLOR","형광펜 색상을 확인해 주세요.");s.defaultHighlightColor=r.defaultHighlightColor();}return ReaderSettingsResponse.from(settings.save(s));}
 private ReaderSettings defaults(AppUser u){ReaderSettings s=new ReaderSettings();s.user=u;s.fontScale=BigDecimal.ONE;s.lineHeightStep=1;s.theme="LIGHT";s.defaultHighlightColor="#FFF59D";return s;}
}

@RestController @RequestMapping("/api/books") class ReaderFeatureController {
 private final ReaderFeatureService service; ReaderFeatureController(ReaderFeatureService s){service=s;}
 @GetMapping("/{bookId}/chapters") List<ChapterResponse> chapters(@PathVariable Long bookId){return service.chapters(bookId);}
 @GetMapping("/{bookId}/reading-notes") List<ReadingNoteResponse> notes(@PathVariable Long bookId,@RequestParam(required=false) ReadingNoteType type,org.springframework.security.core.Authentication a){return service.notes(a.getName(),bookId,type);}
 @PostMapping("/{bookId}/reading-notes") ReadingNoteResponse create(@PathVariable Long bookId,@Valid @RequestBody ReadingNoteRequest r,org.springframework.security.core.Authentication a){return service.create(a.getName(),bookId,r);}
 @PatchMapping("/{bookId}/reading-notes/{noteId}") ReadingNoteResponse update(@PathVariable Long bookId,@PathVariable Long noteId,@Valid @RequestBody ReadingNoteUpdateRequest r,org.springframework.security.core.Authentication a){return service.update(a.getName(),bookId,noteId,r);}
 @DeleteMapping("/{bookId}/reading-notes/{noteId}") @ResponseStatus(HttpStatus.NO_CONTENT) void delete(@PathVariable Long bookId,@PathVariable Long noteId,org.springframework.security.core.Authentication a){service.delete(a.getName(),bookId,noteId);}
 @DeleteMapping("/{bookId}/reading-notes") ReadingNoteBulkDeleteResponse deleteAll(@PathVariable Long bookId,@RequestParam(required=false) ReadingNoteType type,org.springframework.security.core.Authentication a){return service.deleteAll(a.getName(),bookId,type);}
}
@RestController @RequestMapping("/api/reader-settings") class ReaderSettingsController {
 private final ReaderFeatureService service; ReaderSettingsController(ReaderFeatureService s){service=s;}
 @GetMapping ReaderSettingsResponse get(org.springframework.security.core.Authentication a){return service.settings(a.getName());}
 @PatchMapping ReaderSettingsResponse save(@Valid @RequestBody ReaderSettingsRequest r,org.springframework.security.core.Authentication a){return service.saveSettings(a.getName(),r);}
}
