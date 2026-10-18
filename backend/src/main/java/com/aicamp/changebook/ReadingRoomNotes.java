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
  @Column(name="selection_ranges", columnDefinition="TEXT") String selectionRanges;
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
  @Size(max=30000) String selectedText, @Size(max=4000) String content, @Size(max=20) String highlightColor,
  Long bookId, @Valid @Size(max=200) List<NoteRange> ranges) {
  RoomNoteRequest(String type,Integer order,Integer start,Integer end,String text,String content,String color,Long bookId) {
    this(type,order,start,end,text,content,color,bookId,null);
  }
}
record RoomMemberColorRequest(@NotBlank String highlightColor) {}
record RoomNoteResponse(Long id, Long userId, String nickname, String profileImageUrl, String type, int paragraphOrder,
  Integer startOffset, Integer endOffset, String selectedText, String content, String highlightColor,
  boolean isSpoilerLocked, boolean mine, long commentCount, Instant createdAt, Instant updatedAt, long version, List<NoteRange> ranges, boolean canDelete) {}
record RoomNoteCommentRequest(@NotBlank @Size(max=1000) String content) {}
record RoomNoteUpdateRequest(@Size(max=4000) String content, @Size(max=20) String highlightColor) {}
record RoomNoteCommentResponse(Long id,Long userId,String nickname,String profileImageUrl,String content,Instant createdAt,Instant updatedAt,boolean mine,long version,boolean canDelete) {}

@org.springframework.stereotype.Service
class ReadingRoomNoteService {
  @org.springframework.beans.factory.annotation.Autowired private UserBookProgressRepository globalProgress;
  @org.springframework.beans.factory.annotation.Autowired private BookParagraphRepository paragraphs;
  private final ReadingRoomNoteRepository notes; private final ReadingRoomNoteCommentRepository comments;
  private final RoomRepo rooms; private final RoomMemberRepo members; private final UserFeatureService users;
  private final UserRepository userRepository; private final RoomMemberProgressRepo progress; private final RoomBookRepo roomBooks; private final ReadingRoomSyncService sync;
  ReadingRoomNoteService(ReadingRoomNoteRepository n,ReadingRoomNoteCommentRepository c,RoomRepo r,RoomMemberRepo m,UserFeatureService u,UserRepository ur,RoomMemberProgressRepo p,RoomBookRepo rb,ReadingRoomSyncService s){notes=n;comments=c;rooms=r;members=m;users=u;userRepository=ur;progress=p;roomBooks=rb;sync=s;}
  @org.springframework.transaction.annotation.Transactional
  void deleteAsAuthorOrOwner(String username,Long roomId,Long noteId) {
    AppUser current=member(username,roomId);
    ReadingRoom room=room(roomId);
    ReadingRoomNote n=note(roomId,noteId);
    boolean owner=java.util.Objects.equals(room.ownerId,current.id)||members.findByRoomIdAndUserId(roomId,current.id)
        .map(member->"OWNER".equals(member.role)||"HOST".equals(member.role)).orElse(false);
    if(!n.userId.equals(current.id)&&!owner)
      throw new ApiException(HttpStatus.FORBIDDEN,"SHARED_NOTE_DELETE_FORBIDDEN","Only the author or room owner can delete a shared note.");
    deleteMemoHighlights(n);
    notes.delete(n);
    if("MEMO".equals(n.type)) notifyOwnerDeletion(room,current,n.userId,n.bookId,false);
    sync.publish(roomId,n.bookId,"HIGHLIGHT".equals(n.type)?"shared_highlight.deleted":"shared_note.deleted",noteId);
  }
  private AppUser member(String username,Long roomId){AppUser user=users.me(username);if(!members.existsByRoomIdAndUserId(roomId,user.id))throw new ApiException(HttpStatus.FORBIDDEN,"ROOM_MEMBER_REQUIRED","Join this room first.");return user;}
  private ReadingRoom room(Long roomId){return rooms.findById(roomId).orElseThrow(()->new ApiException(HttpStatus.NOT_FOUND,"ROOM_NOT_FOUND","Room not found."));}
  private ReadingRoomNote note(Long roomId,Long noteId){return notes.findById(noteId).filter(n->n.roomId.equals(roomId)).orElseThrow(()->new ApiException(HttpStatus.NOT_FOUND,"SHARED_NOTE_NOT_FOUND","Shared note not found."));}
  @org.springframework.beans.factory.annotation.Autowired private UserSpoilerSettingRepository spoilerSettings;
  private boolean spoiler(ReadingRoom room,AppUser current,ReadingRoomNote note){
    if(!"MEMO".equals(note.type))return false;
    // Only another member's memo can be a spoiler.
    int position=globalProgress.findByUserIdAndBookId(current.id,note.bookId).map(p->Math.max(p.maxReadPosition,p.lastReadPosition)).orElse(0);
    boolean enabled=spoilerSettings.findById(current.id).map(setting->setting.enabled).orElse(true);
    var ranges=NoteRangeSupport.decode(note.selectionRanges);
    int last=ranges.isEmpty()?note.paragraphOrder:ranges.get(ranges.size()-1).paragraphOrder();
    return enabled&&!note.userId.equals(current.id)&&last>position;
  }
  private void readable(ReadingRoom room,AppUser user,ReadingRoomNote note){if(spoiler(room,user,note))throw new ApiException(HttpStatus.FORBIDDEN,"SPOILER_LOCKED","Read further to view this shared note.");}
  private Long scopedBook(ReadingRoom room, Long requestedBookId) {
    Long bookId = requestedBookId != null ? requestedBookId : (room.currentBookId != null ? room.currentBookId : room.bookId);
    if (bookId == null) throw new ApiException(HttpStatus.BAD_REQUEST,"ROOM_BOOK_REQUIRED","방에 읽을 책이 없습니다.");
    if (!roomBooks.existsByRoomIdAndBookId(room.id, bookId)) throw new ApiException(HttpStatus.BAD_REQUEST,"ROOM_BOOK_REQUIRED","방에 등록된 책만 선택할 수 있습니다.");
    return bookId;
  }
  List<RoomNoteResponse> list(String username,Long roomId,Long bookId){return list(username,roomId,bookId,false);}
  List<RoomNoteResponse> list(String username,Long roomId,Long bookId,boolean reader){
    AppUser current=member(username,roomId);ReadingRoom room=room(roomId);Long scopedBook=scopedBook(room,bookId);
    return notes.findByRoomIdAndBookIdOrderByParagraphOrderAscCreatedAtAsc(roomId,scopedBook).stream()
      .filter(n->!"BOOKMARK".equals(n.type)||n.userId.equals(current.id))
      .map(n->response(room,current,n,!reader)).toList();
  }
@org.springframework.transaction.annotation.Transactional RoomNoteResponse create(String username,Long roomId,RoomNoteRequest request){
    if(request.ranges()!=null && !request.ranges().isEmpty()) return createRange(username,roomId,request);
    // Serialize note creation with room book removal before membership/book checks.
    ReadingRoom room=rooms.findByIdForUpdate(roomId).orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND,"ROOM_NOT_FOUND","Room not found."));
    AppUser current=member(username,roomId);Long bookId=scopedBook(room,request.bookId());if("MEMO".equals(request.type())&&(request.content()==null||request.content().trim().isEmpty()))throw new ApiException(HttpStatus.BAD_REQUEST,"INVALID_SHARED_NOTE","메모 내용을 입력해 주세요.");if("HIGHLIGHT".equals(request.type())&&(request.startOffset()==null||request.endOffset()==null||request.endOffset()<=request.startOffset()))throw new ApiException(HttpStatus.BAD_REQUEST,"INVALID_SHARED_NOTE","하이라이트 범위를 확인해 주세요.");if(("HIGHLIGHT".equals(request.type())||"BOOKMARK".equals(request.type()))&&("BOOKMARK".equals(request.type())?notes.findByRoomIdAndBookIdOrderByParagraphOrderAscCreatedAtAsc(roomId,bookId).stream().anyMatch(existing->existing.userId.equals(current.id)&&"BOOKMARK".equals(existing.type)&&existing.paragraphOrder==request.paragraphOrder()&&java.util.Objects.equals(existing.startOffset,request.startOffset())&&java.util.Objects.equals(existing.endOffset,request.endOffset())):notes.existsByRoomIdAndUserIdAndParagraphOrderAndStartOffsetAndEndOffsetAndType(roomId,current.id,request.paragraphOrder(),request.startOffset(),request.endOffset(),request.type())))throw new ApiException(HttpStatus.CONFLICT,"DUPLICATE_SHARED_NOTE","이미 공유한 노트입니다.");ReadingRoomNote n=new ReadingRoomNote();n.roomId=roomId;n.userId=current.id;n.bookId=bookId;n.type=request.type();n.paragraphOrder=request.paragraphOrder();n.startOffset=request.startOffset();n.endOffset=request.endOffset();n.selectedText=blank(request.selectedText());n.content=blank(request.content());n.highlightColor="MEMO".equals(n.type)?memberMemoColor(roomId,current.id):HighlightColorSupport.normalize(request.highlightColor());n=notes.save(n);ensureMemoHighlights(n);sync.publish(roomId,bookId,"HIGHLIGHT".equals(n.type)?"shared_highlight.created":"shared_note.created",n.id);notifyNewMemo(room,n);return response(room,current,n);}
  private RoomNoteResponse createRange(String username,Long roomId,RoomNoteRequest request) {
    ReadingRoom room=rooms.findByIdForUpdate(roomId).orElseThrow(()->new ApiException(HttpStatus.NOT_FOUND,"ROOM_NOT_FOUND","방을 찾을 수 없습니다."));
    AppUser current=member(username,roomId); Long bookId=scopedBook(room,request.bookId());
    if("BOOKMARK".equals(request.type())) throw new ApiException(HttpStatus.BAD_REQUEST,"INVALID_NOTE_RANGE","책갈피는 한 위치에 저장합니다.");
    var selected=NoteRangeSupport.validate(paragraphs,bookId,request.ranges());
    if("MEMO".equals(request.type()) && (request.content()==null || request.content().trim().isEmpty())) throw new ApiException(HttpStatus.BAD_REQUEST,"INVALID_SHARED_NOTE","메모 내용을 입력해 주세요.");
    if("HIGHLIGHT".equals(request.type())) {
      ReadingRoomNote firstNote=null;
      for(int i=0;i<selected.ranges().size();i++) {
        var range=selected.ranges().get(i);
        if(range.endOffset()==range.startOffset()) continue;
        var existing=notes.findByRoomIdAndBookIdOrderByParagraphOrderAscCreatedAtAsc(roomId,bookId).stream().filter(n->n.userId.equals(current.id) && "HIGHLIGHT".equals(n.type) && n.paragraphOrder==range.paragraphOrder() && java.util.Objects.equals(n.startOffset,range.startOffset()) && java.util.Objects.equals(n.endOffset,range.endOffset())).findFirst();
        ReadingRoomNote note=existing.orElseGet(ReadingRoomNote::new);
        note.roomId=roomId;note.bookId=bookId;note.userId=current.id;note.type="HIGHLIGHT";
        note.paragraphOrder=range.paragraphOrder();note.startOffset=range.startOffset();note.endOffset=range.endOffset();
        note.selectedText=selected.parts().get(i);note.highlightColor=HighlightColorSupport.normalize(request.highlightColor());note=notes.saveAndFlush(note);
        if(firstNote==null)firstNote=note;
        sync.publish(roomId,bookId,"shared_highlight.created",note.id);
      }
      return response(room,current,firstNote);
    }
    String encoded=NoteRangeSupport.encode(selected.ranges());
    var duplicate=notes.findByRoomIdAndBookIdOrderByParagraphOrderAscCreatedAtAsc(roomId,bookId).stream().filter(n->n.userId.equals(current.id) && "MEMO".equals(n.type) && encoded.equals(n.selectionRanges) && request.content().trim().equals(n.content)).findFirst();
    if(duplicate.isPresent())return response(room,current,duplicate.get());
    var first=selected.ranges().get(0);
    ReadingRoomNote note=new ReadingRoomNote();note.roomId=roomId;note.bookId=bookId;note.userId=current.id;note.type="MEMO";
    note.paragraphOrder=first.paragraphOrder();note.startOffset=first.startOffset();note.endOffset=first.endOffset();
    note.selectedText=selected.text();note.content=request.content().trim();note.highlightColor=memberMemoColor(roomId,current.id);note.selectionRanges=encoded;
    note=notes.saveAndFlush(note);ensureMemoHighlights(note);sync.publish(roomId,bookId,"shared_note.created",note.id);
    notifyNewMemo(room,note);
    return response(room,current,note);
  }
  private void notifyNewMemo(ReadingRoom room,ReadingRoomNote memo){
    if(!"MEMO".equals(memo.type))return;
    // Do not include memo text or its quotation, which may contain spoilers.
    users.notifyRoomMemo(room.id,"새 메모",
        name(room.id,memo.userId)+"님이 "+room.name+" 방에 새 메모를 남겼습니다.",memo.userId,memo.bookId,memo.id);
  }
  private void notifyOwnerDeletion(ReadingRoom room,AppUser actor,Long authorId,Long bookId,boolean comment) {
    // Authorization was checked by the deletion endpoint. A different actor
    // therefore means the owner moderated another member's content.
    if(java.util.Objects.equals(authorId,actor.id)) return;
    String subject=comment?"댓글":"메모";
    // Do not target a deleted note or expose its contents in notification text.
    users.notify(authorId,comment?"ROOM_COMMENT_DELETED":"ROOM_MEMO_DELETED",
        subject+" 삭제",room.name+" 방의 방장이 회원님의 "+(comment?"댓글을":"메모를")+" 삭제했습니다.",
        room.id,actor.id,false,bookId,null);
  }
  private String memberMemoColor(Long roomId,Long userId) {
    return members.findByRoomIdAndUserId(roomId,userId).map(m->m.memoHighlightColor)
      .filter(c->c!=null&&!c.isBlank()).orElse("#FFF59D");
  }

  @org.springframework.transaction.annotation.Transactional
  String updateMyMemoColor(String username,Long roomId,String requestedColor) {
    ReadingRoom lockedRoom=rooms.findByIdForUpdate(roomId).orElseThrow(()->new ApiException(HttpStatus.NOT_FOUND,"ROOM_NOT_FOUND","방을 찾을 수 없습니다."));
    AppUser current=member(username,roomId);
    String color=HighlightColorSupport.normalize(requestedColor);
    if(color==null)throw new ApiException(HttpStatus.BAD_REQUEST,"INVALID_HIGHLIGHT_COLOR","색상을 선택해 주세요.");
    RoomMember membership=members.findByRoomIdAndUserId(roomId,current.id).orElseThrow();
    membership.memoHighlightColor=color;members.save(membership);
    for(var memo:notes.findByRoomIdOrderByParagraphOrderAscCreatedAtAsc(roomId)) {
      if(!memo.userId.equals(current.id)||!"MEMO".equals(memo.type))continue;
      memo.highlightColor=color;notes.save(memo);ensureMemoHighlights(memo);
      var ranges=NoteRangeSupport.decode(memo.selectionRanges);
      for(var h:notes.findByRoomIdAndBookIdOrderByParagraphOrderAscCreatedAtAsc(roomId,memo.bookId)) {
        if(!h.userId.equals(current.id)||!"HIGHLIGHT".equals(h.type)||h.startOffset==null||h.endOffset==null)continue;
        boolean covered=ranges.isEmpty()
          ? h.paragraphOrder==memo.paragraphOrder && memo.startOffset!=null && memo.endOffset!=null
            && memo.startOffset<=h.startOffset && memo.endOffset>=h.endOffset
          : ranges.stream().anyMatch(r->r.paragraphOrder()==h.paragraphOrder && r.startOffset()<=h.startOffset && r.endOffset()>=h.endOffset);
        if(covered){h.highlightColor=color;notes.save(h);sync.publish(roomId,memo.bookId,"shared_highlight.updated",h.id);}
      }
      sync.publish(roomId,memo.bookId,"shared_note.updated",memo.id);
    }
    Long eventBook=lockedRoom.currentBookId!=null?lockedRoom.currentBookId:lockedRoom.bookId;
    if(eventBook!=null)sync.publish(roomId,eventBook,"member_color.updated",current.id);
    return color;
  }

  // Like personal notes, a memo owns a persistent highlight of its selection.
  // Delete matching highlights with the last memo that needs them.
  private void deleteMemoHighlights(ReadingRoomNote memo){
    if(!"MEMO".equals(memo.type))return;
    var all=notes.findByRoomIdAndBookIdOrderByParagraphOrderAscCreatedAtAsc(memo.roomId,memo.bookId);
    for(var h:all){
      if(!"HIGHLIGHT".equals(h.type)||!h.userId.equals(memo.userId)||!memoMatchesHighlight(memo,h,false))continue;
      boolean needed=all.stream().anyMatch(other->"MEMO".equals(other.type)&&other.userId.equals(memo.userId)
        &&!other.id.equals(memo.id)&&memoMatchesHighlight(other,h,true));
      if(!needed){notes.delete(h);sync.publish(memo.roomId,memo.bookId,"shared_highlight.deleted",h.id);}
    }
  }
  private boolean memoMatchesHighlight(ReadingRoomNote memo,ReadingRoomNote h,boolean overlap){
    if(h.startOffset==null||h.endOffset==null)return false;
    var ranges=NoteRangeSupport.decode(memo.selectionRanges);
    if(ranges.isEmpty()){
      if(memo.startOffset==null||memo.endOffset==null)return false;
      ranges=List.of(new NoteRange(memo.paragraphOrder,memo.startOffset,memo.endOffset));
    }
    return ranges.stream().anyMatch(r->r.paragraphOrder()==h.paragraphOrder&&(overlap
      ?r.startOffset()<h.endOffset&&r.endOffset()>h.startOffset
      :r.startOffset()==h.startOffset&&r.endOffset()==h.endOffset));
  }

  private void ensureMemoHighlights(ReadingRoomNote memo) {
    if(!"MEMO".equals(memo.type))return;
    if(memo.highlightColor==null)memo.highlightColor="#FFF59D";
    var ranges=NoteRangeSupport.decode(memo.selectionRanges);
    if(ranges.isEmpty()) {
      if(memo.startOffset==null||memo.endOffset==null)return;
      ranges=List.of(new NoteRange(memo.paragraphOrder,memo.startOffset,memo.endOffset));
    }
    var existing=notes.findByRoomIdAndBookIdOrderByParagraphOrderAscCreatedAtAsc(memo.roomId,memo.bookId);
    for(var range:ranges) {
      if(range.endOffset()<=range.startOffset())continue;
      var found=existing.stream().filter(h->h.userId.equals(memo.userId)&&"HIGHLIGHT".equals(h.type)
        && h.paragraphOrder==range.paragraphOrder()
        && java.util.Objects.equals(h.startOffset,range.startOffset())
        && java.util.Objects.equals(h.endOffset,range.endOffset())).findFirst();
      ReadingRoomNote h=found.orElseGet(ReadingRoomNote::new);
      h.roomId=memo.roomId;h.bookId=memo.bookId;h.userId=memo.userId;h.type="HIGHLIGHT";
      h.paragraphOrder=range.paragraphOrder();h.startOffset=range.startOffset();h.endOffset=range.endOffset();
      h.highlightColor=memo.highlightColor;
      var paragraph=paragraphs.findByBookIdOrderByParagraphOrderAsc(memo.bookId).stream()
        .filter(v->v.paragraphOrder==range.paragraphOrder()).findFirst();
      if(paragraph.isPresent() && paragraph.get().content!=null
        && range.startOffset()>=0 && range.endOffset()<=paragraph.get().content.length())
        h.selectedText=paragraph.get().content.substring(range.startOffset(),range.endOffset());
      h=notes.save(h);sync.publish(memo.roomId,memo.bookId,"shared_highlight.updated",h.id);
    }
    notes.save(memo);
  }

  @org.springframework.transaction.annotation.Transactional void delete(String username,Long roomId,Long noteId){AppUser current=member(username,roomId);ReadingRoomNote n=note(roomId,noteId);if(!n.userId.equals(current.id))throw new ApiException(HttpStatus.FORBIDDEN,"SHARED_NOTE_DELETE_FORBIDDEN","작성자만 공유 메모를 삭제할 수 있습니다.");deleteMemoHighlights(n);notes.delete(n);sync.publish(roomId,n.bookId,"HIGHLIGHT".equals(n.type)?"shared_highlight.deleted":"shared_note.deleted",noteId);}
  @org.springframework.transaction.annotation.Transactional
  RoomNoteResponse update(String username,Long roomId,Long noteId,RoomNoteUpdateRequest request){
    ReadingRoom room=rooms.findByIdForUpdate(roomId).orElseThrow(()->new ApiException(HttpStatus.NOT_FOUND,"ROOM_NOT_FOUND","방을 찾을 수 없습니다."));
    AppUser current=member(username,roomId);ReadingRoomNote n=note(roomId,noteId);
    if(!n.userId.equals(current.id))throw new ApiException(HttpStatus.FORBIDDEN,"SHARED_NOTE_UPDATE_FORBIDDEN","작성자만 수정할 수 있습니다.");
    if(request.content()!=null){
      if(!"MEMO".equals(n.type)||request.content().trim().isEmpty())throw new ApiException(HttpStatus.BAD_REQUEST,"INVALID_SHARED_NOTE","메모 내용을 확인해 주세요.");
      n.content=request.content().trim();
    }
    if(request.highlightColor()!=null){
      if(!"HIGHLIGHT".equals(n.type)&&!"MEMO".equals(n.type))throw new ApiException(HttpStatus.BAD_REQUEST,"INVALID_HIGHLIGHT_COLOR","하이라이트 색상을 확인해 주세요.");
      n.highlightColor="MEMO".equals(n.type)
        ? updateMyMemoColor(username,roomId,request.highlightColor())
        : HighlightColorSupport.normalize(request.highlightColor());
      if("MEMO".equals(n.type)){
        var ranges=NoteRangeSupport.decode(n.selectionRanges);
        for(var h:notes.findByRoomIdAndBookIdOrderByParagraphOrderAscCreatedAtAsc(roomId,n.bookId)){
          if(!h.userId.equals(current.id)||!"HIGHLIGHT".equals(h.type)||h.startOffset==null||h.endOffset==null)continue;
          boolean covered=ranges.isEmpty()
            ? h.paragraphOrder==n.paragraphOrder && n.startOffset!=null && n.endOffset!=null && n.startOffset<=h.startOffset && n.endOffset>=h.endOffset
            : ranges.stream().anyMatch(r->r.paragraphOrder()==h.paragraphOrder && r.startOffset()<=h.startOffset && r.endOffset()>=h.endOffset);
          if(covered){h.highlightColor=n.highlightColor;notes.save(h);sync.publish(roomId,n.bookId,"shared_highlight.updated",h.id);}
        }
      }
    }
    if(request.content()==null&&request.highlightColor()==null)throw new ApiException(HttpStatus.BAD_REQUEST,"INVALID_SHARED_NOTE","수정할 내용을 입력해 주세요.");
    n=notes.save(n);
    if("MEMO".equals(n.type))ensureMemoHighlights(n);
    sync.publish(roomId,n.bookId,"HIGHLIGHT".equals(n.type)?"shared_highlight.updated":"shared_note.updated",n.id);
    return response(room,current,n);
  }
  List<RoomNoteCommentResponse> comments(String username,Long roomId,Long noteId){return comments(username,roomId,noteId,false);}
  List<RoomNoteCommentResponse> comments(String username,Long roomId,Long noteId,boolean revealed){AppUser current=member(username,roomId);ReadingRoom room=room(roomId);ReadingRoomNote n=note(roomId,noteId);if(!"MEMO".equals(n.type))throw new ApiException(HttpStatus.BAD_REQUEST,"COMMENTS_ONLY_FOR_MEMO","Comments are available only for memos.");if(!revealed)readable(room,current,n);return comments.findByRoomNoteIdOrderByCreatedAtAsc(noteId).stream().map(c->commentResponse(roomId,current,c)).toList();}
  @org.springframework.transaction.annotation.Transactional RoomNoteCommentResponse addComment(String username,Long roomId,Long noteId,RoomNoteCommentRequest request){return addComment(username,roomId,noteId,request,false);}
  @org.springframework.transaction.annotation.Transactional RoomNoteCommentResponse addComment(String username,Long roomId,Long noteId,RoomNoteCommentRequest request,boolean revealed){AppUser current=member(username,roomId);ReadingRoom room=room(roomId);ReadingRoomNote n=note(roomId,noteId);if(!"MEMO".equals(n.type))throw new ApiException(HttpStatus.BAD_REQUEST,"COMMENTS_ONLY_FOR_MEMO","Comments are available only for memos.");if(!revealed)readable(room,current,n);ReadingRoomNoteComment c=new ReadingRoomNoteComment();c.roomNoteId=noteId;c.userId=current.id;c.content=request.content().trim();c=comments.save(c);sync.publish(roomId,n.bookId,"shared_comment.created",c.id);if(members.existsByRoomIdAndUserId(roomId,n.userId))users.notify(n.userId,"ROOM_MEMO_COMMENT","내 메모에 새 댓글",name(roomId,current.id)+"님이 "+room.name+" 방의 내 메모에 댓글을 남겼습니다.",roomId,current.id,false,n.bookId,n.id);return commentResponse(roomId,current,c);}
  @org.springframework.transaction.annotation.Transactional RoomNoteCommentResponse updateComment(String username,Long roomId,Long noteId,Long commentId,RoomNoteCommentRequest request){return updateComment(username,roomId,noteId,commentId,request,false);}
  @org.springframework.transaction.annotation.Transactional RoomNoteCommentResponse updateComment(String username,Long roomId,Long noteId,Long commentId,RoomNoteCommentRequest request,boolean revealed){AppUser current=member(username,roomId);ReadingRoom room=room(roomId);ReadingRoomNote n=note(roomId,noteId);if(!revealed)readable(room,current,n);ReadingRoomNoteComment c=comments.findById(commentId).filter(v->v.roomNoteId.equals(noteId)).orElseThrow(()->new ApiException(HttpStatus.NOT_FOUND,"SHARED_NOTE_COMMENT_NOT_FOUND","Comment not found."));if(!c.userId.equals(current.id))throw new ApiException(HttpStatus.FORBIDDEN,"COMMENT_EDIT_FORBIDDEN","Only the author can edit this comment.");c.content=request.content().trim();c=comments.save(c);sync.publish(roomId,n.bookId,"shared_comment.updated",c.id);return commentResponse(roomId,current,c);}
  @org.springframework.transaction.annotation.Transactional void deleteComment(String username,Long roomId,Long noteId,Long commentId){deleteComment(username,roomId,noteId,commentId,false);}
  @org.springframework.transaction.annotation.Transactional
  void deleteComment(String username,Long roomId,Long noteId,Long commentId,boolean revealed) {
    AppUser current=member(username,roomId);
    ReadingRoom room=room(roomId);
    ReadingRoomNote n=note(roomId,noteId);
    if(!revealed) readable(room,current,n);
    ReadingRoomNoteComment c=comments.findById(commentId).filter(v->v.roomNoteId.equals(noteId))
        .orElseThrow(()->new ApiException(HttpStatus.NOT_FOUND,"SHARED_NOTE_COMMENT_NOT_FOUND","Comment not found."));
    if(!canDeleteComment(room,current,c))
      throw new ApiException(HttpStatus.FORBIDDEN,"COMMENT_DELETE_FORBIDDEN","댓글 작성자 또는 방장만 댓글을 삭제할 수 있습니다.");
    comments.delete(c);
    notifyOwnerDeletion(room,current,c.userId,n.bookId,true);
    sync.publish(roomId,n.bookId,"shared_comment.deleted",commentId);
  }
  private boolean canDelete(ReadingRoom room,AppUser current,ReadingRoomNote n){return n.userId.equals(current.id)||("MEMO".equals(n.type)&&(java.util.Objects.equals(room.ownerId,current.id)||members.findByRoomIdAndUserId(room.id,current.id).map(member->"OWNER".equals(member.role)||"HOST".equals(member.role)).orElse(false)));}
  private RoomNoteResponse response(ReadingRoom room,AppUser current,ReadingRoomNote n){return response(room,current,n,true);}
  private RoomNoteResponse response(ReadingRoom room,AppUser current,ReadingRoomNote n,boolean maskSpoilers){boolean locked=maskSpoilers&&spoiler(room,current,n);return new RoomNoteResponse(n.id,n.userId,name(room.id,n.userId),profileImage(room.id,n.userId),n.type,n.paragraphOrder,n.startOffset,n.endOffset,locked?null:n.selectedText,locked?null:n.content,locked?null:n.highlightColor,locked,n.userId.equals(current.id),locked?0:comments.countByRoomNoteId(n.id),n.createdAt,n.updatedAt,n.version,locked?List.of():NoteRangeSupport.decode(n.selectionRanges),canDelete(room,current,n));}
  /** Explicit, item-only reveal. It is never persisted, so snapshots and a
   * new app session revert to the redacted representation. */
  RoomNoteResponse reveal(String username,Long roomId,Long noteId){AppUser current=member(username,roomId);ReadingRoom room=room(roomId);ReadingRoomNote n=note(roomId,noteId);if(!"MEMO".equals(n.type)&&!n.userId.equals(current.id))throw new ApiException(HttpStatus.FORBIDDEN,"PRIVATE_ROOM_NOTE","다른 멤버의 개인 기록은 볼 수 없습니다.");return new RoomNoteResponse(n.id,n.userId,name(room.id,n.userId),profileImage(room.id,n.userId),n.type,n.paragraphOrder,n.startOffset,n.endOffset,n.selectedText,n.content,n.highlightColor,false,n.userId.equals(current.id),comments.countByRoomNoteId(n.id),n.createdAt,n.updatedAt,n.version,NoteRangeSupport.decode(n.selectionRanges),canDelete(room,current,n));}
  private boolean canDeleteComment(ReadingRoom room,AppUser current,ReadingRoomNoteComment c){return c.userId.equals(current.id)||java.util.Objects.equals(room.ownerId,current.id)||members.findByRoomIdAndUserId(room.id,current.id).map(member->"OWNER".equals(member.role)||"HOST".equals(member.role)).orElse(false);}
  private RoomNoteCommentResponse commentResponse(Long roomId,AppUser current,ReadingRoomNoteComment c){return new RoomNoteCommentResponse(c.id,c.userId,name(roomId,c.userId),profileImage(roomId,c.userId),c.content,c.createdAt,c.updatedAt,c.userId.equals(current.id),c.version,canDeleteComment(room(roomId),current,c));}
  private String name(Long roomId,Long id){return members.findByRoomIdAndUserId(roomId,id).map(m->m.roomNickname).filter(n->n!=null&&!n.isBlank()).orElseGet(()->userRepository.findById(id).map(u->u.nickname).orElse("알 수 없음"));}
  private String profileImage(Long roomId,Long id){return members.findByRoomIdAndUserId(roomId,id).map(m->m.roomProfileImageUrl).filter(v->v!=null&&!v.isBlank()).orElseGet(()->userRepository.findById(id).map(users::profileFor).map(ProfileResponse::profileImageUrl).orElse(null));}
  private String blank(String value){return value==null||value.trim().isEmpty()?null:value.trim();}
}

@RestController @RequestMapping({"/api/reading-rooms/{roomId}/shared-notes", "/api/reading-rooms/{roomId}/notes"})
class ReadingRoomNoteController {
  private final ReadingRoomNoteService service; ReadingRoomNoteController(ReadingRoomNoteService s){service=s;}
  @PatchMapping("/my-color") java.util.Map<String,String> myColor(@PathVariable Long roomId,@Valid @RequestBody RoomMemberColorRequest request,org.springframework.security.core.Authentication a){return java.util.Map.of("highlightColor",service.updateMyMemoColor(a.getName(),roomId,request.highlightColor()));}
  @GetMapping List<RoomNoteResponse> list(@PathVariable Long roomId,@RequestParam(required=false) Long bookId,@RequestParam(defaultValue="false") boolean reader,org.springframework.security.core.Authentication a){return service.list(a.getName(),roomId,bookId,reader);}
  @PostMapping @ResponseStatus(HttpStatus.CREATED) RoomNoteResponse create(@PathVariable Long roomId,@Valid @RequestBody RoomNoteRequest r,org.springframework.security.core.Authentication a){return service.create(a.getName(),roomId,r);}
  @DeleteMapping("/{noteId}") @ResponseStatus(HttpStatus.NO_CONTENT) void delete(@PathVariable Long roomId,@PathVariable Long noteId,org.springframework.security.core.Authentication a){service.deleteAsAuthorOrOwner(a.getName(),roomId,noteId);}
  @PatchMapping("/{noteId}") RoomNoteResponse update(@PathVariable Long roomId,@PathVariable Long noteId,@Valid @RequestBody RoomNoteUpdateRequest r,org.springframework.security.core.Authentication a){return service.update(a.getName(),roomId,noteId,r);}
  @PostMapping("/{noteId}/reveal") RoomNoteResponse reveal(@PathVariable Long roomId,@PathVariable Long noteId,org.springframework.security.core.Authentication a){return service.reveal(a.getName(),roomId,noteId);}
  @GetMapping("/{noteId}/comments") List<RoomNoteCommentResponse> comments(@PathVariable Long roomId,@PathVariable Long noteId,@RequestParam(defaultValue="false") boolean revealed,org.springframework.security.core.Authentication a){return service.comments(a.getName(),roomId,noteId,revealed);}
  @PostMapping("/{noteId}/comments") @ResponseStatus(HttpStatus.CREATED) RoomNoteCommentResponse addComment(@PathVariable Long roomId,@PathVariable Long noteId,@Valid @RequestBody RoomNoteCommentRequest r,@RequestParam(defaultValue="false") boolean revealed,org.springframework.security.core.Authentication a){return service.addComment(a.getName(),roomId,noteId,r,revealed);}
  @PatchMapping("/{noteId}/comments/{commentId}") RoomNoteCommentResponse updateComment(@PathVariable Long roomId,@PathVariable Long noteId,@PathVariable Long commentId,@Valid @RequestBody RoomNoteCommentRequest r,@RequestParam(defaultValue="false") boolean revealed,org.springframework.security.core.Authentication a){return service.updateComment(a.getName(),roomId,noteId,commentId,r,revealed);}
  @DeleteMapping("/{noteId}/comments/{commentId}") @ResponseStatus(HttpStatus.NO_CONTENT) void deleteComment(@PathVariable Long roomId,@PathVariable Long noteId,@PathVariable Long commentId,@RequestParam(defaultValue="false") boolean revealed,org.springframework.security.core.Authentication a){service.deleteComment(a.getName(),roomId,noteId,commentId,revealed);}
}
