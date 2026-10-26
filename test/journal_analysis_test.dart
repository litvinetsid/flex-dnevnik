import 'package:csv/csv.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flex/data_portability/analysis_csv.dart';
import 'package:flex/database/daily_log_repository.dart';
import 'package:flex/database/database.dart';
import 'package:flex/journal/journal_reminder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<AppDatabase> openDatabase() async {
    final database = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    addTearDown(database.close);
    return database;
  }

  List<Map<String, String>> parse(String csv) {
    final rows = CsvDecoder().convert(csv);
    final header = rows.first.cast<String>();
    return [
      for (final row in rows.skip(1))
        {for (var i = 0; i < header.length; i++) header[i]: '${row[i]}'},
    ];
  }

  test('saving a day twice keeps one row with the latest values', () async {
    final database = await openDatabase();
    final day = DateTime(2026, 10, 20, 21, 30);

    await saveDailyLog(database, day: day, kcal: 2100, sleepHours: 6);
    await saveDailyLog(
      database,
      day: day.add(const Duration(hours: 1)),
      kcal: 2300,
      wellbeing: 4,
    );

    final logs = await database.dailyLogs.select().get();
    expect(logs, hasLength(1));
    expect(logs.single.date, DateTime(2026, 10, 20));
    expect(logs.single.kcal, 2300);
    expect(logs.single.sleepHours, isNull);
    expect(logs.single.wellbeing, 4);
  });

  test(
    'body weight for a day is updated in place and can be cleared',
    () async {
      final database = await openDatabase();
      final day = DateTime(2026, 10, 20);

      await setBodyWeightForDay(database, day, 80);
      await setBodyWeightForDay(database, day, 79.4);
      var weights = await database.bodyWeights.select().get();
      expect(weights.map((row) => row.weightKg), [79.4]);
      expect(localDay(weights.single.timestamp), day);

      await setBodyWeightForDay(database, day, null);
      weights = await database.bodyWeights.select().get();
      expect(weights, isEmpty);
    },
  );

  test('daily CSV joins journal, weight, training and comments', () async {
    final database = await openDatabase();
    final day = DateTime(2026, 10, 21);
    final exerciseId = (await database.exercises.select().get()).first.id;
    final workout = await database.workouts.insertReturning(
      WorkoutsCompanion.insert(
        planId: const Value(1),
        startedAt: day.add(const Duration(hours: 18)),
      ),
    );
    await setWorkoutNotes(database, workout.id, 'Не выспался');
    for (final load in [60.0, 70.0]) {
      await database.exerciseSets.insertOne(
        ExerciseSetsCompanion.insert(
          exerciseId: exerciseId,
          workoutId: Value(workout.id),
          timestamp: day.add(const Duration(hours: 18, minutes: 5)),
          reps: const Value(5),
          loadKg: Value(load),
        ),
      );
    }
    await saveDailyLog(
      database,
      day: day,
      kcal: 2400,
      proteinG: 140,
      sleepHours: 5.5,
      wellbeing: 2,
      notes: 'Тяжёлый день',
    );
    await setBodyWeightForDay(database, day, 81.2);

    final rows = parse(await exportDailyAnalysisCsv(database));
    expect(rows, hasLength(1));
    expect(rows.single, {
      'date': '2026-10-21',
      'body_weight_kg': '81.2',
      'sleep_hours': '5.5',
      'wellbeing_1_5': '2',
      'kcal': '2400',
      'protein_g': '140.0',
      'fat_g': '',
      'carbs_g': '',
      'workouts': '1',
      'workout_sets': '2',
      'workout_volume_kg': '650.0',
      'day_notes': 'Тяжёлый день',
      'workout_notes': 'Не выспался',
    });

    final sets = parse(await exportWorkoutAnalysisCsv(database));
    expect(sets.map((row) => row['set_number']), ['1', '2']);
    expect(sets.last['volume_kg'], '350.0');
    expect(sets.last['est_1rm_kg'], '81.67');
    expect(sets.last['workout_notes'], 'Не выспался');
  });

  test('estimated one rep max uses Epley and ignores empty sets', () {
    expect(estimatedOneRepMax(100, 1), 100);
    expect(estimatedOneRepMax(100, 10), closeTo(133.33, 0.01));
    expect(estimatedOneRepMax(null, 5), isNull);
    expect(estimatedOneRepMax(100, 0), isNull);
  });

  test('reminders skip filled days and times already passed', () {
    final times = journalReminderTimes(
      now: DateTime(2026, 10, 26, 22, 0),
      filledDays: {DateTime(2026, 10, 27)},
      minutes: 23 * 60,
      days: 4,
    );
    expect(times, [
      (0, DateTime(2026, 10, 26, 23)),
      (2, DateTime(2026, 10, 28, 23)),
      (3, DateTime(2026, 10, 29, 23)),
    ]);

    final late = journalReminderTimes(
      now: DateTime(2026, 10, 26, 23, 30),
      filledDays: {},
      minutes: 23 * 60,
      days: 2,
    );
    expect(late, [(1, DateTime(2026, 10, 27, 23))]);
  });

  test('CSV text that looks like a formula is neutralised', () {
    expect(safeCsvText('=HYPERLINK("x")'), "'=HYPERLINK(\"x\")");
    expect(safeCsvText('-5 кг'), "'-5 кг");
    expect(safeCsvText('@sum'), "'@sum");
    expect(safeCsvText('Не выспался'), 'Не выспался');
    expect(safeCsvText(null), isNull);
  });
}
