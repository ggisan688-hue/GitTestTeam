package com.aicamp.changebook;

import jakarta.persistence.*;
import java.time.*;
import java.util.*;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.web.bind.annotation.*;

@Entity @Table(name="change_book_reading_activity_logs")
class ReadingActivityLog {
 @Id @GeneratedValue(strategy=GenerationType.IDENTITY) Long id;
 @ManyToOne(fetch=FetchType.LAZY) @JoinColumn(name="user_id",nullable=false) AppUser user;
 @ManyToOne(fetch=FetchType.LAZY) @JoinColumn(name="book_id",nullable=false) Book book;
 @Column(name="activity_date",nullable=false) LocalDate activityDate;
 @Column(name="paragraphs_read",nullable=false) int paragraphsRead;
 @Column(name="pages_read",nullable=false) int pagesRead;
 @Column(name="last_position_before",nullable=false) int lastPositionBefore;
 @Column(name="last_position_after",nullable=false) int lastPositionAfter;
 @Column(name="created_at",nullable=false) Instant createdAt;
 @Column(name="updated_at",nullable=false) Instant updatedAt;
 @PrePersist void create(){createdAt=updatedAt=Instant.now();}
 @PreUpdate void update(){updatedAt=Instant.now();}
}
interface ReadingActivityLogRepository extends JpaRepository<ReadingActivityLog,Long>{
 Optional<ReadingActivityLog> findByUserIdAndBookIdAndActivityDate(Long userId,Long bookId,LocalDate date);
 List<ReadingActivityLog> findByUserIdAndActivityDateBetween(Long userId,LocalDate start,LocalDate end);
 @Query("select distinct a.activityDate from ReadingActivityLog a where a.user.id=:userId and a.pagesRead>0 order by a.activityDate desc") List<LocalDate> activeDates(@Param("userId") Long userId);
}
// One row per account/book/reference page, shared by every reading context.
@Entity @Table(name="change_book_standard_page_reads",uniqueConstraints=@UniqueConstraint(columnNames={"user_id","book_id","page_number"}))
class StandardPageRead {
 @Id @GeneratedValue(strategy=GenerationType.IDENTITY) Long id;
 @Column(name="user_id",nullable=false) Long userId;
 @Column(name="book_id",nullable=false) Long bookId;
 @Column(name="page_number",nullable=false) int pageNumber;
 @Column(name="read_date",nullable=false) LocalDate readDate;
}
interface StandardPageReadRepository extends JpaRepository<StandardPageRead,Long>{
 @Query("select p.pageNumber from StandardPageRead p where p.userId=:userId and p.bookId=:bookId and p.pageNumber<=:lastPage")
 List<Integer> recordedPagesThrough(@Param("userId") Long userId,@Param("bookId") Long bookId,@Param("lastPage") int lastPage);
}
record StandardPagesRequest(@jakarta.validation.constraints.NotNull Long bookId,
 @jakarta.validation.constraints.NotEmpty @jakarta.validation.constraints.Size(max=200)
 List<@jakarta.validation.constraints.NotNull @jakarta.validation.constraints.Min(1) @jakarta.validation.constraints.Max(100000) Integer> pages){}
record StandardPagesResponse(int addedPages){}
record DailyReadingResponse(LocalDate date,String dayLabel,int paragraphsRead,int pagesRead){}
record ReadingStatsResponse(LocalDate startDate,LocalDate endDate,List<DailyReadingResponse> dailyReading,int currentStreakDays,int completedBooksCount,long memoCount,long periodMemoCount,int periodParagraphsRead,int periodPagesRead){}

@Service class ReadingStatisticsService {
 final UserRepository users; final ReadingActivityLogRepository activities; final UserBookProgressRepository progress; final ReadingNoteRepository notes;
 @jakarta.persistence.PersistenceContext private EntityManager entityManager;
 @org.springframework.beans.factory.annotation.Autowired private StandardPageReadRepository pageReads;
 @org.springframework.beans.factory.annotation.Autowired private BookRepository books;
 static final ZoneId ZONE=ZoneId.of("Asia/Seoul");
 ReadingStatisticsService(UserRepository u,ReadingActivityLogRepository a,UserBookProgressRepository p,ReadingNoteRepository n){users=u;activities=a;progress=p;notes=n;}
 AppUser user(String username){return users.findByUsername(username).orElseThrow(()->new ApiException(HttpStatus.UNAUTHORIZED,"UNAUTHORIZED","인증이 필요합니다."));}
 @org.springframework.transaction.annotation.Transactional
 StandardPagesResponse recordPages(String username,StandardPagesRequest request){
  AppUser u=user(username);
  Book book=books.findById(request.bookId()).orElseThrow(()->new ApiException(HttpStatus.NOT_FOUND,"BOOK_NOT_FOUND","책을 찾을 수 없습니다."));
  // Serialize deduplication, including simultaneous personal/room requests.
  entityManager.lock(u,LockModeType.PESSIMISTIC_WRITE);
  // Treat every reference page up to the reached position as read.
  // Query a range instead of a large SQL IN list when a reader jumps far ahead.
  int lastPage=Collections.max(request.pages());
  var requested=new HashSet<Integer>();
  for(int page=1;page<=lastPage;page++)requested.add(page);
  requested.removeAll(pageReads.recordedPagesThrough(u.id,book.id,lastPage));
  if(requested.isEmpty())return new StandardPagesResponse(0);
  LocalDate date=LocalDate.now(ZONE);
  for(int page:requested){var r=new StandardPageRead();r.userId=u.id;r.bookId=book.id;r.pageNumber=page;r.readDate=date;pageReads.save(r);}
  var log=activities.findByUserIdAndBookIdAndActivityDate(u.id,book.id,date).orElseGet(()->{var a=new ReadingActivityLog();a.user=u;a.book=book;a.activityDate=date;return a;});
  log.pagesRead+=requested.size();activities.save(log);
  return new StandardPagesResponse(requested.size());
 }
 ReadingStatsResponse stats(String username,String period){AppUser u=user(username);LocalDate today=LocalDate.now(ZONE);LocalDate start;LocalDate end;
  if("month".equalsIgnoreCase(period)){start=today.withDayOfMonth(1);end=today.withDayOfMonth(today.lengthOfMonth());}else if("year".equalsIgnoreCase(period)){start=today.withDayOfYear(1);end=today.withMonth(12).withDayOfMonth(31);}else if(period==null||"week".equalsIgnoreCase(period)){start=today.minusDays(today.getDayOfWeek().getValue()-1);end=start.plusDays(6);}else throw new ApiException(HttpStatus.BAD_REQUEST,"INVALID_PERIOD","기간을 확인해 주세요.");
  Map<LocalDate,Integer> sums=new HashMap<>();for(var a:activities.findByUserIdAndActivityDateBetween(u.id,start,end))sums.merge(a.activityDate,a.pagesRead,Integer::sum);
  var daily=new ArrayList<DailyReadingResponse>();int total=0;for(var d=start;!d.isAfter(end);d=d.plusDays(1)){int value=sums.getOrDefault(d,0);total+=value;daily.add(new DailyReadingResponse(d,switch(d.getDayOfWeek()){case MONDAY->"월";case TUESDAY->"화";case WEDNESDAY->"수";case THURSDAY->"목";case FRIDAY->"금";case SATURDAY->"토";case SUNDAY->"일";},0,value));}
  var dates=new HashSet<>(activities.activeDates(u.id));LocalDate cursor=dates.contains(today)?today:today.minusDays(1);int streak=0;while(dates.contains(cursor)){streak++;cursor=cursor.minusDays(1);}Instant from=start.atStartOfDay(ZONE).toInstant(),to=end.plusDays(1).atStartOfDay(ZONE).toInstant();
  return new ReadingStatsResponse(start,end,daily,streak,progress.countByUserIdAndProgressPercentGreaterThanEqual(u.id,100),notes.countByUserIdAndNoteType(u.id,ReadingNoteType.MEMO),notes.countByUserIdAndNoteTypeAndCreatedAtBetween(u.id,ReadingNoteType.MEMO,from,to),0,total);
 }
}
@RestController @RequestMapping("/api/reading-stats") class ReadingStatisticsController{
 final ReadingStatisticsService service;ReadingStatisticsController(ReadingStatisticsService s){service=s;}
 @PostMapping("/pages") StandardPagesResponse recordPages(@jakarta.validation.Valid @RequestBody StandardPagesRequest request,org.springframework.security.core.Authentication a){return service.recordPages(a.getName(),request);}
 @GetMapping ReadingStatsResponse get(@RequestParam(required=false,defaultValue="week") String period,org.springframework.security.core.Authentication a){return service.stats(a.getName(),period);}
}
