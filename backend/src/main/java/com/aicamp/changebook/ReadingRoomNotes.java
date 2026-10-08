package com.aicamp.changebook;

import jakarta.persistence.*;
import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import java.time.Instant;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;

/** Room notes are immutable snapshots; deleting a private source note never deletes its shared copy. */
@Entity @Table(name = "change_book_reading_room_notes")
class ReadingRoomNote {
  @Id @GeneratedValue(strategy = GenerationType.IDENTITY) Long id;
  @Column(name="room_id", nullable=false) Long roomId;
  @Column(name="user_id", nullable=false) Long userId;
  @Column(name="book_id", nullable=false) Long bookId;
  @Column(name="paragraph_order", nullable=false) int paragraphOrder;
  @Column(name="start_offset") Integer startOffset;
  @Column(name="end_offset") Integer endOffset;
  @Column(nullable=false, length=12) String type;
  @Column(name="selected_text") String selectedText;
  @Column String content;
  @Column(name="highlight_color", length=20) String highlightColor;
  @Column(name="created_at", nullable=false) Instant createdAt;
  @Column(name="updated_at", nullable=false) Instant updatedAt;
  @Version @Column(nullable=false) long version;
  @PrePersist void created(){ createdAt=updatedAt=Instant.now(); }
  @PreUpdate void updated(){ updatedAt=Instant.now(); }
}

@Entity @Table(name = "change_book_reading_room_note_comments")
class ReadingRoomNoteComment {
  @Id @GeneratedValue(strategy = GenerationType.IDENTITY) Long id;
  @Column(name="room_note_id", nullable=false) Long roomNoteId;
  @Column(name="user_id", nullable=false) Long userId;
  @Column(nullable=false, length=1000) String content;
  @Column(name="created_at", nullable=false) Instant createdAt;
  @Column(name="updated_at", nullable=false) Instant updatedAt;
  @Version @Column(nullable=false) long version;
  @PrePersist void created(){ createdAt=updatedAt=Instant.now(); }
  @PreUpdate void updated(){ updatedAt=Instant.now(); }
}

interface ReadingRoomNoteRepository extends JpaRepository<ReadingRoomNote,Long> {
  List<ReadingRoomNote> findByRoomIdOrderByParagraphOrderAscCreatedAtAsc(Long roomId);
  List<ReadingRoomNote> findByRoomIdAndBookIdOrderByParagraphOrderAscCreatedAtAsc(Long roomId, Long bookId);
  boolean existsByRoomIdAndUserIdAndParagraphOrderAndStartOffsetAndEndOffsetAndType(Long roomId,Long userId,int paragraphOrder,Integer start,Integer end,String type);
}
interface ReadingRoomNoteCommentRepository extends JpaRepository<ReadingRoomNoteComment,Long> {
  List<ReadingRoomNoteComment> findByRoomNoteIdOrderByCreatedAtAsc(Long roomNoteId);
  long countByRoomNoteId(Long roomNoteId);
}

record RoomNoteRequest(@NotBlank @Pattern(regexp="MEMO|HIGHLIGHT|BOOKMARK") String type,
  @NotNull @Min(1) Integer paragraphOrder, @Min(0) Integer startOffset, @Min(0) Integer endOffset,
  @Size(max=4000) String selectedText, @Size(max=4000) String content, @Size(max=20) String highlightColor,
  Long bookId) {}
record RoomNoteResponse(Long id, Long userId, String nickname, String profileImageUrl, String type, int paragraphOrder,
  Integer startOffset, Integer endOffset, String selectedText, String content, String highlightColor,
  boolean isSpoilerLocked, long commentCount, Instant createdAt, Instant updatedAt, long version) {}
record RoomNoteCommentRequest(@NotBlank @Size(max=1000) String content) {}
record RoomNoteCommentResponse(Long id,Long userId,String nickname,String profileImageUrl,String content,Instant createdAt,Instant updatedAt,boolean mine,long version) {}

@org.springframework.stereotype.Service
class ReadingRoomNoteService {
  private final ReadingRoomNoteRepository notes; private final ReadingRoomNoteCommentRepository comments;
  private final RoomRepo rooms; private final RoomMemberRepo members; private final UserFeatureService users;
  private final UserRepository userRepository; private final RoomMemberProgressRepo progress; private final RoomBookRepo roomBooks; private final ReadingRoomSyncService sync;
  ReadingRoomNoteService(ReadingRoomNoteRepository n,ReadingRoomNoteCommentRepository c,RoomRepo r,RoomMemberRepo m,UserFeatureService u,UserRepository ur,RoomMemberProgressRepo p,RoomBookRepo rb,ReadingRoomSyncService s){notes=n;comments=c;rooms=r;members=m;users=u;userRepository=ur;progress=p;roomBooks=rb;sync=s;}
  private AppUser member(String username,Long roomId){AppUser user=users.me(username);if(!members.existsByRoomIdAndUserId(roomId,user.id))throw new ApiException(HttpStatus.FORBIDDEN,"ROOM_MEMBER_REQUIRED","Join this room first.");return user;}
  private ReadingRoom room(Long roomId){return rooms.findById(roomId).orElseThrow(()->new ApiException(HttpStatus.NOT_FOUND,"ROOM_NOT_FOUND","Room not found."));}
  private ReadingRoomNote note(Long roomId,Long noteId){return notes.findById(noteId).filter(n->n.roomId.equals(roomId)).orElseThrow(()->new ApiException(HttpStatus.NOT_FOUND,"SHARED_NOTE_NOT_FOUND","Shared note not found."));}
  private boolean spoiler(ReadingRoom room,AppUser current,ReadingRoomNote note){
    // Never use personal or another member's position: absence/other-book data is locked.
    int position=progress.findByRoomIdAndUserIdAndBookId(room.id,current.id,note.bookId).map(p->p.lastReadPosition).orElse(0);
    return room.spoilerLockEnabled&&!note.userId.equals(current.id)&&note.paragraphOrder>position;
  }
  private void readable(ReadingRoom room,AppUser user,ReadingRoomNote note){if(spoiler(room,user,note))throw new ApiException(HttpStatus.FORBIDDEN,"SPOILER_LOCKED","Read further to view this shared note.");}
  private Long scopedBook(ReadingRoom room, Long requestedBookId) {
    Long bookId = requestedBookId != null ? requestedBookId : (room.currentBookId != null ? room.currentBookId : room.bookId);
    if (bookId == null) throw new ApiException(HttpStatus.BAD_REQUEST,"ROOM_BOOK_REQUIRED","방에 읽을 책이 없습니다.");
    if (!roomBooks.existsByRoomIdAndBookId(room.id, bookId)) throw new ApiException(HttpStatus.BAD_REQUEST,"ROOM_BOOK_REQUIRED","방에 등록된 책만 선택할 수 있습니다.");
    return bookId;
  }
  List<RoomNoteResponse> list(String username,Long roomId,Long bookId){AppUser current=member(username,roomId);ReadingRoom room=room(roomId);Long scopedBook=scopedBook(room,bookId);return notes.findByRoomIdAndBookIdOrderByParagraphOrderAscCreatedAtAsc(roomId,scopedBook).stream().map(n->response(room,current,n)).toList();}
@org.springframework.transaction.annotation.Transactional RoomNoteResponse create(String username,Long roomId,RoomNoteRequest request){AppUser current=member(username,roomId);ReadingRoom room=room(roomId);Long bookId=scopedBook(room,request.bookId());if("MEMO".equals(request.type())&&(request.content()==null||request.content().trim().isEmpty()))throw new ApiException(HttpStatus.BAD_REQUEST,"INVALID_SHARED_NOTE","메모 내용을 입력해 주세요.");if("HIGHLIGHT".equals(request.type())&&(request.startOffset()==null||request.endOffset()==null||request.endOffset()<=request.startOffset()))throw new ApiException(HttpStatus.BAD_REQUEST,"INVALID_SHARED_NOTE","하이라이트 범위를 확인해 주세요.");if(("HIGHLIGHT".equals(request.type())||"BOOKMARK".equals(request.type()))&&notes.existsByRoomIdAndUserIdAndParagraphOrderAndStartOffsetAndEndOffsetAndType(roomId,current.id,request.paragraphOrder(),request.startOffset(),request.endOffset(),request.type()))throw new ApiException(HttpStatus.CONFLICT,"DUPLICATE_SHARED_NOTE","이미 공유한 노트입니다.");ReadingRoomNote n=new ReadingRoomNote();n.roomId=roomId;n.userId=current.id;n.bookId=bookId;n.type=request.type();n.paragraphOrder=request.paragraphOrder();n.startOffset=request.startOffset();n.endOffset=request.endOffset();n.selectedText=blank(request.selectedText());n.content=blank(request.content());n.highlightColor=blank(request.highlightColor());n=notes.save(n);sync.publish(roomId,bookId,"HIGHLIGHT".equals(n.type)?"shared_highlight.created":"shared_note.created",n.id);return response(room,current,n);}
  @org.springframework.transaction.annotation.Transactional void delete(String username,Long roomId,Long noteId){AppUser current=member(username,roomId);ReadingRoomNote n=note(roomId,noteId);if(!n.userId.equals(current.id))throw new ApiException(HttpStatus.FORBIDDEN,"SHARED_NOTE_DELETE_FORBIDDEN","작성자만 공유 메모를 삭제할 수 있습니다.");notes.delete(n);sync.publish(roomId,n.bookId,"HIGHLIGHT".equals(n.type)?"shared_highlight.deleted":"shared_note.deleted",noteId);}
  List<RoomNoteCommentResponse> comments(String username,Long roomId,Long noteId){AppUser current=member(username,roomId);ReadingRoom room=room(roomId);ReadingRoomNote n=note(roomId,noteId);if(!"MEMO".equals(n.type))throw new ApiException(HttpStatus.BAD_REQUEST,"COMMENTS_ONLY_FOR_MEMO","Comments are available only for memos.");readable(room,current,n);return comments.findByRoomNoteIdOrderByCreatedAtAsc(noteId).stream().map(c->commentResponse(roomId,current,c)).toList();}
  @org.springframework.transaction.annotation.Transactional RoomNoteCommentResponse addComment(String username,Long roomId,Long noteId,RoomNoteCommentRequest request){AppUser current=member(username,roomId);ReadingRoom room=room(roomId);ReadingRoomNote n=note(roomId,noteId);if(!"MEMO".equals(n.type))throw new ApiException(HttpStatus.BAD_REQUEST,"COMMENTS_ONLY_FOR_MEMO","Comments are available only for memos.");readable(room,current,n);ReadingRoomNoteComment c=new ReadingRoomNoteComment();c.roomNoteId=noteId;c.userId=current.id;c.content=request.content().trim();c=comments.save(c);sync.publish(roomId,n.bookId,"shared_comment.created",c.id);return commentResponse(roomId,current,c);}
  @org.springframework.transaction.annotation.Transactional RoomNoteCommentResponse updateComment(String username,Long roomId,Long noteId,Long commentId,RoomNoteCommentRequest request){AppUser current=member(username,roomId);ReadingRoom room=room(roomId);ReadingRoomNote n=note(roomId,noteId);readable(room,current,n);ReadingRoomNoteComment c=comments.findById(commentId).filter(v->v.roomNoteId.equals(noteId)).orElseThrow(()->new ApiException(HttpStatus.NOT_FOUND,"SHARED_NOTE_COMMENT_NOT_FOUND","Comment not found."));if(!c.userId.equals(current.id))throw new ApiException(HttpStatus.FORBIDDEN,"COMMENT_EDIT_FORBIDDEN","Only the author can edit this comment.");c.content=request.content().trim();c=comments.save(c);sync.publish(roomId,n.bookId,"shared_comment.updated",c.id);return commentResponse(roomId,current,c);}
  @org.springframework.transaction.annotation.Transactional void deleteComment(String username,Long roomId,Long noteId,Long commentId){AppUser current=member(username,roomId);ReadingRoom room=room(roomId);ReadingRoomNote n=note(roomId,noteId);readable(room,current,n);ReadingRoomNoteComment c=comments.findById(commentId).filter(v->v.roomNoteId.equals(noteId)).orElseThrow(()->new ApiException(HttpStatus.NOT_FOUND,"SHARED_NOTE_COMMENT_NOT_FOUND","Comment not found."));if(!c.userId.equals(current.id))throw new ApiException(HttpStatus.FORBIDDEN,"COMMENT_DELETE_FORBIDDEN","Only the author can delete this comment.");comments.delete(c);sync.publish(roomId,n.bookId,"shared_comment.deleted",commentId);}
  private RoomNoteResponse response(ReadingRoom room,AppUser current,ReadingRoomNote n){boolean locked=spoiler(room,current,n);return new RoomNoteResponse(n.id,n.userId,name(room.id,n.userId),profileImage(room.id,n.userId),n.type,n.paragraphOrder,n.startOffset,n.endOffset,locked?null:n.selectedText,locked?null:n.content,locked?null:n.highlightColor,locked,locked?0:comments.countByRoomNoteId(n.id),n.createdAt,n.updatedAt,n.version);}
  /** Explicit, item-only reveal. It is never persisted, so snapshots and a
   * new app session revert to the redacted representation. */
  RoomNoteResponse reveal(String username,Long roomId,Long noteId){AppUser current=member(username,roomId);ReadingRoom room=room(roomId);ReadingRoomNote n=note(roomId,noteId);return new RoomNoteResponse(n.id,n.userId,name(room.id,n.userId),profileImage(room.id,n.userId),n.type,n.paragraphOrder,n.startOffset,n.endOffset,n.selectedText,n.content,n.highlightColor,false,comments.countByRoomNoteId(n.id),n.createdAt,n.updatedAt,n.version);}
  private RoomNoteCommentResponse commentResponse(Long roomId,AppUser current,ReadingRoomNoteComment c){return new RoomNoteCommentResponse(c.id,c.userId,name(roomId,c.userId),profileImage(roomId,c.userId),c.content,c.createdAt,c.updatedAt,c.userId.equals(current.id),c.version);}
  private String name(Long roomId,Long id){return members.findByRoomIdAndUserId(roomId,id).map(m->m.roomNickname).filter(n->n!=null&&!n.isBlank()).orElseGet(()->userRepository.findById(id).map(u->u.nickname).orElse("알 수 없음"));}
  private String profileImage(Long roomId,Long id){return members.findByRoomIdAndUserId(roomId,id).map(m->m.roomProfileImageUrl).filter(v->v!=null&&!v.isBlank()).orElseGet(()->userRepository.findById(id).map(users::profileFor).map(ProfileResponse::profileImageUrl).orElse(null));}
  private String blank(String value){return value==null||value.trim().isEmpty()?null:value.trim();}
}

@RestController @RequestMapping({"/api/reading-rooms/{roomId}/shared-notes", "/api/reading-rooms/{roomId}/notes"})
class ReadingRoomNoteController {
  private final ReadingRoomNoteService service; ReadingRoomNoteController(ReadingRoomNoteService s){service=s;}
  @GetMapping List<RoomNoteResponse> list(@PathVariable Long roomId,@RequestParam(required=false) Long bookId,org.springframework.security.core.Authentication a){return service.list(a.getName(),roomId,bookId);}
  @PostMapping @ResponseStatus(HttpStatus.CREATED) RoomNoteResponse create(@PathVariable Long roomId,@Valid @RequestBody RoomNoteRequest r,org.springframework.security.core.Authentication a){return service.create(a.getName(),roomId,r);}
  @DeleteMapping("/{noteId}") @ResponseStatus(HttpStatus.NO_CONTENT) void delete(@PathVariable Long roomId,@PathVariable Long noteId,org.springframework.security.core.Authentication a){service.delete(a.getName(),roomId,noteId);}
  @PostMapping("/{noteId}/reveal") RoomNoteResponse reveal(@PathVariable Long roomId,@PathVariable Long noteId,org.springframework.security.core.Authentication a){return service.reveal(a.getName(),roomId,noteId);}
  @GetMapping("/{noteId}/comments") List<RoomNoteCommentResponse> comments(@PathVariable Long roomId,@PathVariable Long noteId,org.springframework.security.core.Authentication a){return service.comments(a.getName(),roomId,noteId);}
  @PostMapping("/{noteId}/comments") @ResponseStatus(HttpStatus.CREATED) RoomNoteCommentResponse addComment(@PathVariable Long roomId,@PathVariable Long noteId,@Valid @RequestBody RoomNoteCommentRequest r,org.springframework.security.core.Authentication a){return service.addComment(a.getName(),roomId,noteId,r);}
  @PatchMapping("/{noteId}/comments/{commentId}") RoomNoteCommentResponse updateComment(@PathVariable Long roomId,@PathVariable Long noteId,@PathVariable Long commentId,@Valid @RequestBody RoomNoteCommentRequest r,org.springframework.security.core.Authentication a){return service.updateComment(a.getName(),roomId,noteId,commentId,r);}
  @DeleteMapping("/{noteId}/comments/{commentId}") @ResponseStatus(HttpStatus.NO_CONTENT) void deleteComment(@PathVariable Long roomId,@PathVariable Long noteId,@PathVariable Long commentId,org.springframework.security.core.Authentication a){service.deleteComment(a.getName(),roomId,noteId,commentId);}
}
