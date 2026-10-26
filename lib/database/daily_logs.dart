import 'package:drift/drift.dart';

/// One journal row per local day: nutrition totals, sleep and how the day felt.
///
/// [date] is local midnight. Body weight lives in body_weights.
@TableIndex.sql('CREATE UNIQUE INDEX daily_logs_date ON daily_logs (date)')
class DailyLogs extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get date => dateTime()();
  IntColumn get kcal => integer().nullable()();
  RealColumn get proteinG => real().nullable()();
  RealColumn get fatG => real().nullable()();
  RealColumn get carbsG => real().nullable()();
  RealColumn get sleepHours => real().nullable()();
  IntColumn get wellbeing => integer().nullable()();
  TextColumn get notes => text().nullable()();
}
