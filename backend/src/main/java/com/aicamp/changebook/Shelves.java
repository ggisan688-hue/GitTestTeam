package com.aicamp.changebook;

import jakarta.persistence.*;
import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;

@Entity @Table(name="change_book_shelves")
class Shelf {
 @Id @GeneratedValue(strategy=GenerationType.IDENTITY) Long id;
 @ManyToOne(fetch=FetchType.LAZY) @JoinColumn(name="user_id",nullable=false) AppUser user;
 @Column(nullable=false,length=80) String name;
 @Column(length=300) String description;
 @Column(name="is_public",nullable=false) boolean isPublic;
 @Column(name="created_at",nullable=false) Instant createdAt;
 @Column(name="updated_at",nullable=false) Instant updatedAt;
 @PrePersist void create(){createdAt=updatedAt=Instant.now();}
 @PreUpdate void update(){updatedAt=Instant.now();}
}
@Entity @Table(name="change_book_shelf_books") @IdClass(ShelfBookId.class)
class ShelfBook {
 @Id @Column(name="shelf_id") Long shelfId;
 @Id @Column(name="book_id") Long bookId;
 @Column(name="created_at",nullable=false) Instant createdAt;
 @PrePersist void create(){createdAt=Instant.now();}
}
class ShelfBookId implements java.io.Serializable { Long shelfId; Long bookId; public ShelfBookId(){} public boolean equals(Object o){if(!(o instanceof ShelfBookId x))return false;return java.util.Objects.equals(shelfId,x.shelfId)&&java.util.Objects.equals(bookId,x.bookId);} public int hashCode(){return java.util.Objects.hash(shelfId,bookId);} }
interface ShelfRepository extends JpaRepository<Shelf,Long>{List<Shelf> findByUserIdOrderByUpdatedAtDesc(Long userId); Optional<Shelf> findByIdAndUserId(Long id,Long userId); boolean existsByUserIdAndNameIgnoreCase(Long userId,String name); @Modifying(flushAutomatically=true,clearAutomatically=true) @Query("delete from Shelf s where s.user.id = :userId") int deleteAllByUserId(@Param("userId") Long userId);}
interface ShelfBookRepository extends JpaRepository<ShelfBook,ShelfBookId>{List<ShelfBook> findByShelfIdOrderByCreatedAtDesc(Long shelfId); boolean existsByShelfIdAndBookId(Long shelfId,Long bookId); void deleteByShelfIdAndBookId(Long shelfId,Long bookId); long countByShelfId(Long shelfId);}
record ShelfRequest(@NotBlank @Size(max=80) String name,@Size(max=300) String description,Boolean isPublic,List<Long> bookIds){}
record ShelfResponse(Long id,String name,String description,boolean isPublic,long bookCount,Instant createdAt,Instant updatedAt){}
record ShelfDetailResponse(Long id,String name,String description,boolean isPublic,long bookCount,List<BookResponse> books,Instant createdAt,Instant updatedAt){}
record ShelfBulkDeleteResponse(int deletedCount){}

@org.springframework.stereotype.Service class ShelfService {
 final ShelfRepository shelves; final ShelfBookRepository shelfBooks; final UserRepository users; final BookRepository books;
 ShelfService(ShelfRepository s,ShelfBookRepository sb,UserRepository u,BookRepository b){shelves=s;shelfBooks=sb;users=u;books=b;}
 AppUser user(String username){return users.findByUsername(username).orElseThrow(()->new ApiException(HttpStatus.UNAUTHORIZED,"UNAUTHORIZED","인증이 필요합니다."));}
 Shelf owned(String username,Long id){AppUser u=user(username);return shelves.findByIdAndUserId(id,u.id).orElseThrow(()->new ApiException(HttpStatus.NOT_FOUND,"SHELF_NOT_FOUND","책장을 찾을 수 없습니다."));}
 ShelfResponse response(Shelf s){return new ShelfResponse(s.id,s.name,s.description,s.isPublic,shelfBooks.countByShelfId(s.id),s.createdAt,s.updatedAt);}
 List<ShelfResponse> list(String username){AppUser u=user(username);return shelves.findByUserIdOrderByUpdatedAtDesc(u.id).stream().map(this::response).toList();}
 @org.springframework.transaction.annotation.Transactional ShelfResponse create(String username,ShelfRequest r){AppUser u=user(username);String name=r.name().trim();if(shelves.existsByUserIdAndNameIgnoreCase(u.id,name))throw new ApiException(HttpStatus.CONFLICT,"DUPLICATE_SHELF_NAME","같은 이름의 책장이 이미 있습니다.");var ids=new java.util.LinkedHashSet<Long>();if(r.bookIds()!=null)ids.addAll(r.bookIds());if(ids.stream().anyMatch(java.util.Objects::isNull))throw new ApiException(HttpStatus.BAD_REQUEST,"INVALID_BOOK_IDS","도서 선택을 확인해 주세요.");var selected=books.findAllById(ids);if(selected.size()!=ids.size())throw new ApiException(HttpStatus.NOT_FOUND,"BOOK_NOT_FOUND","선택한 도서 중 찾을 수 없는 항목이 있습니다.");Shelf s=new Shelf();s.user=u;s.name=name;s.description=blank(r.description());s.isPublic=Boolean.TRUE.equals(r.isPublic());s=shelves.save(s);for(var book:selected){ShelfBook link=new ShelfBook();link.shelfId=s.id;link.bookId=book.id;shelfBooks.save(link);}return response(s);}
 ShelfResponse update(String username,Long id,ShelfRequest r){Shelf s=owned(username,id);String name=r.name().trim();if(!s.name.equalsIgnoreCase(name)&&shelves.existsByUserIdAndNameIgnoreCase(s.user.id,name))throw new ApiException(HttpStatus.CONFLICT,"DUPLICATE_SHELF_NAME","같은 이름의 책장이 이미 있습니다.");s.name=name;s.description=blank(r.description());s.isPublic=Boolean.TRUE.equals(r.isPublic());return response(shelves.save(s));}
 ShelfDetailResponse detail(String username,Long id){Shelf s=owned(username,id);List<BookResponse> list=shelfBooks.findByShelfIdOrderByCreatedAtDesc(id).stream().map(x->books.findById(x.bookId).map(BookResponse::from).orElse(null)).filter(java.util.Objects::nonNull).toList();return new ShelfDetailResponse(s.id,s.name,s.description,s.isPublic,list.size(),list,s.createdAt,s.updatedAt);}
 void delete(String username,Long id){shelves.delete(owned(username,id));}
 @org.springframework.transaction.annotation.Transactional int deleteAll(String username){return shelves.deleteAllByUserId(user(username).id);}
 void add(String username,Long shelfId,Long bookId){Shelf s=owned(username,shelfId);if(!books.existsById(bookId))throw new ApiException(HttpStatus.NOT_FOUND,"BOOK_NOT_FOUND","책을 찾을 수 없습니다.");if(shelfBooks.existsByShelfIdAndBookId(s.id,bookId))throw new ApiException(HttpStatus.CONFLICT,"DUPLICATE_SHELF_BOOK","이미 책장에 담긴 도서입니다.");ShelfBook b=new ShelfBook();b.shelfId=s.id;b.bookId=bookId;shelfBooks.save(b);}
 void remove(String username,Long shelfId,Long bookId){Shelf s=owned(username,shelfId);if(!shelfBooks.existsByShelfIdAndBookId(s.id,bookId))throw new ApiException(HttpStatus.NOT_FOUND,"SHELF_BOOK_NOT_FOUND","책장에 없는 도서입니다.");shelfBooks.deleteByShelfIdAndBookId(s.id,bookId);}
 String blank(String x){return x==null||x.trim().isEmpty()?null:x.trim();}
}
@RestController @RequestMapping("/api/shelves") class ShelfController {
 final ShelfService service; ShelfController(ShelfService s){service=s;}
 @GetMapping List<ShelfResponse> list(org.springframework.security.core.Authentication a){return service.list(a.getName());}
 @PostMapping @ResponseStatus(HttpStatus.CREATED) ShelfResponse create(@Valid @RequestBody ShelfRequest r,org.springframework.security.core.Authentication a){return service.create(a.getName(),r);}
 @GetMapping("/{shelfId}") ShelfDetailResponse detail(@PathVariable Long shelfId,org.springframework.security.core.Authentication a){return service.detail(a.getName(),shelfId);}
 @PatchMapping("/{shelfId}") ShelfResponse update(@PathVariable Long shelfId,@Valid @RequestBody ShelfRequest r,org.springframework.security.core.Authentication a){return service.update(a.getName(),shelfId,r);}
 @DeleteMapping ShelfBulkDeleteResponse deleteAll(org.springframework.security.core.Authentication a){return new ShelfBulkDeleteResponse(service.deleteAll(a.getName()));}
 @DeleteMapping("/{shelfId}") @ResponseStatus(HttpStatus.NO_CONTENT) void delete(@PathVariable Long shelfId,org.springframework.security.core.Authentication a){service.delete(a.getName(),shelfId);}
 @PostMapping("/{shelfId}/books/{bookId}") @ResponseStatus(HttpStatus.NO_CONTENT) void add(@PathVariable Long shelfId,@PathVariable Long bookId,org.springframework.security.core.Authentication a){service.add(a.getName(),shelfId,bookId);}
 @DeleteMapping("/{shelfId}/books/{bookId}") @ResponseStatus(HttpStatus.NO_CONTENT) void remove(@PathVariable Long shelfId,@PathVariable Long bookId,org.springframework.security.core.Authentication a){service.remove(a.getName(),shelfId,bookId);}
}
