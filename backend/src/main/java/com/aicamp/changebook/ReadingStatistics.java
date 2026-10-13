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
 @Query("select distinct a.activityDate from ReadingActivityLog a where a.user.id=:userId order by a.activityDate desc") List<LocalDate> activeDates(@Param("userId") Long userId);
}
record DailyReadingResponse(LocalDate date,String dayLabel,int paragraphsRead){}
record ReadingStatsResponse(LocalDate startDate,LocalDate endDate,List<DailyReadingResponse> dailyReading,int currentStreakDays,int completedBooksCount,long memoCount,long periodMemoCount,int periodParagraphsRead){}

@Service class ReadingStatisticsService {
 final UserRepository users; final ReadingActivityLogRepository activities; final UserBookProgressRepository progress; final ReadingNoteRepository notes;
 static final ZoneId ZONE=ZoneId.of("Asia/Seoul");
 ReadingStatisticsService(UserRepository u,ReadingActivityLogRepository a,UserBookProgressRepository p,ReadingNoteRepository n){users=u;activities=a;progress=p;notes=n;}
 AppUser user(String username){return users.findByUsername(username).orElseThrow(()->new ApiException(HttpStatus.UNAUTHORIZED,"UNAUTHORIZED","인증이 필요합니다."));}
 ReadingStatsResponse stats(String username,String period){AppUser u=user(username);LocalDate today=LocalDate.now(ZONE);LocalDate start;LocalDate end;
  if("month".equalsIgnoreCase(period)){start=today.withDayOfMonth(1);end=today.withDayOfMonth(today.lengthOfMonth());}else if(period==null||"week".equalsIgnoreCase(period)){start=today.minusDays(today.getDayOfWeek().getValue()-1);end=start.plusDays(6);}else throw new ApiException(HttpStatus.BAD_REQUEST,"INVALID_PERIOD","기간을 확인해 주세요.");
  Map<LocalDate,Integer> sums=new HashMap<>();for(var a:activities.findByUserIdAndActivityDateBetween(u.id,start,end))sums.merge(a.activityDate,a.paragraphsRead,Integer::sum);
  var daily=new ArrayList<DailyReadingResponse>();int total=0;for(var d=start;!d.isAfter(end);d=d.plusDays(1)){int value=sums.getOrDefault(d,0);total+=value;daily.add(new DailyReadingResponse(d,switch(d.getDayOfWeek()){case MONDAY->"월";case TUESDAY->"화";case WEDNESDAY->"수";case THURSDAY->"목";case FRIDAY->"금";case SATURDAY->"토";case SUNDAY->"일";},value));}
  var dates=new HashSet<>(activities.activeDates(u.id));LocalDate cursor=dates.contains(today)?today:today.minusDays(1);int streak=0;while(dates.contains(cursor)){streak++;cursor=cursor.minusDays(1);}Instant from=start.atStartOfDay(ZONE).toInstant(),to=end.plusDays(1).atStartOfDay(ZONE).toInstant();
  return new ReadingStatsResponse(start,end,daily,streak,progress.countByUserIdAndProgressPercentGreaterThanEqual(u.id,100),notes.countByUserIdAndNoteType(u.id,ReadingNoteType.MEMO),notes.countByUserIdAndNoteTypeAndCreatedAtBetween(u.id,ReadingNoteType.MEMO,from,to),total);
 }
}
@RestController @RequestMapping("/api/reading-stats") class ReadingStatisticsController{
 final ReadingStatisticsService service;ReadingStatisticsController(ReadingStatisticsService s){service=s;}
 @GetMapping ReadingStatsResponse get(@RequestParam(required=false,defaultValue="week") String period,org.springframework.security.core.Authentication a){return service.stats(a.getName(),period);}
}
