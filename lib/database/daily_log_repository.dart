import 'package:drift/drift.dart';
import 'package:flex/database/database.dart';

DateTime localDay(DateTime value) {
  final local = value.toLocal();
  return DateTime(local.year, local.month, local.day);
}

Stream<List<DailyLog>> watchDailyLogs(AppDatabase database) {
  return (database.dailyLogs.select()..orderBy([
        (row) => OrderingTerm(expression: row.date, mode: OrderingMode.desc),
      ]))
      .watch();
}

/// Latest body weight per local day, keyed by local midnight.
Stream<Map<DateTime, double>> watchDailyBodyWeights(AppDatabase database) {
  return (database.bodyWeights.select()..orderBy([
        (row) => OrderingTerm.asc(row.timestamp),
        (row) => OrderingTerm.asc(row.id),
      ]))
      .watch()
      .map(
        (rows) => {
          for (final row in rows) localDay(row.timestamp): row.weightKg,
        },
      );
}

/// Saves the journal for [day], replacing any row already stored for it.
Future<void> saveDailyLog(
  AppDatabase database, {
  required DateTime day,
  int? kcal,
  double? proteinG,
  double? fatG,
  double? carbsG,
  double? sleepHours,
  int? wellbeing,
  String? notes,
}) async {
  final companion = DailyLogsCompanion.insert(
    date: localDay(day),
    kcal: Value(kcal),
    proteinG: Value(proteinG),
    fatG: Value(fatG),
    carbsG: Value(carbsG),
    sleepHours: Value(sleepHours),
    wellbeing: Value(wellbeing),
    notes: Value(notes),
  );
  await database.dailyLogs.insertOne(
    companion,
    onConflict: DoUpdate((_) => companion, target: [database.dailyLogs.date]),
  );
}

Future<void> deleteDailyLog(AppDatabase database, int id) {
  return (database.dailyLogs.delete()..where((row) => row.id.equals(id))).go();
}

/// Replaces the body weight measurements recorded on [day] with [weightKg].
Future<void> setBodyWeightForDay(
  AppDatabase database,
  DateTime day,
  double? weightKg,
) {
  final start = localDay(day);
  final end = start.add(const Duration(days: 1));
  return database.transaction(() async {
    final existing =
        await (database.bodyWeights.select()
              ..where(
                (row) =>
                    row.timestamp.isBiggerOrEqualValue(start) &
                    row.timestamp.isSmallerThanValue(end),
              )
              ..orderBy([(row) => OrderingTerm.asc(row.timestamp)]))
            .get();
    if (weightKg == null) {
      for (final row in existing) {
        await database.bodyWeights.deleteOne(row);
      }
      return;
    }
    if (existing.isNotEmpty) {
      final last = existing.last;
      await database.bodyWeights.replaceOne(last.copyWith(weightKg: weightKg));
      return;
    }
    final today = localDay(DateTime.now());
    await database.bodyWeights.insertOne(
      BodyWeightsCompanion.insert(
        timestamp: start == today
            ? DateTime.now()
            : start.add(const Duration(hours: 8)),
        weightKg: weightKg,
      ),
    );
  });
}

Future<void> setWorkoutNotes(
  AppDatabase database,
  int workoutId,
  String? notes,
) {
  return (database.workouts.update()..where((row) => row.id.equals(workoutId)))
      .write(WorkoutsCompanion(notes: Value(notes)));
}

double? average(Iterable<num?> values) {
  final present = values.whereType<num>().toList();
  if (present.isEmpty) return null;
  return present.reduce((a, b) => a + b) / present.length;
}
