class DailyReading {
  const DailyReading({required this.date, required this.dayLabel, required this.paragraphsRead});
  final DateTime date; final String dayLabel; final int paragraphsRead;
  factory DailyReading.fromJson(Map<String,dynamic> json) => DailyReading(date:DateTime.parse(json['date'] as String),dayLabel:json['dayLabel'] as String,paragraphsRead:(json['paragraphsRead'] as num?)?.toInt()??0);
}
class ReadingStats {
  const ReadingStats({required this.startDate,required this.endDate,required this.dailyReading,required this.currentStreakDays,required this.completedBooksCount,required this.memoCount,required this.periodMemoCount,required this.periodParagraphsRead});
  final DateTime startDate,endDate; final List<DailyReading> dailyReading; final int currentStreakDays,completedBooksCount,periodParagraphsRead; final int memoCount,periodMemoCount;
  factory ReadingStats.fromJson(Map<String,dynamic> json)=>ReadingStats(startDate:DateTime.parse(json['startDate'] as String),endDate:DateTime.parse(json['endDate'] as String),dailyReading:(json['dailyReading'] as List).map((e)=>DailyReading.fromJson(e as Map<String,dynamic>)).toList(),currentStreakDays:(json['currentStreakDays'] as num?)?.toInt()??0,completedBooksCount:(json['completedBooksCount'] as num?)?.toInt()??0,memoCount:(json['memoCount'] as num?)?.toInt()??0,periodMemoCount:(json['periodMemoCount'] as num?)?.toInt()??0,periodParagraphsRead:(json['periodParagraphsRead'] as num?)?.toInt()??0);
}
