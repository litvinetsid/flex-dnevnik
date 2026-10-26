import 'dart:math' as math;

import 'package:csv/csv.dart';
import 'package:drift/drift.dart';
import 'package:flex/database/daily_log_repository.dart';
import 'package:flex/database/database.dart';
import 'package:intl/intl.dart';

final _date = DateFormat('yyyy-MM-dd');
final _time = DateFormat('HH:mm:ss');

String _encode(List<List<Object?>> rows) =>
    CsvEncoder(lineDelimiter: '\n').convert(rows);

double? _round(double? value, [int digits = 2]) {
  if (value == null) return null;
  final factor = math.pow(10, digits);
  return (value * factor).roundToDouble() / factor;
}

/// Epley estimate of the one-repetition maximum.
double? estimatedOneRepMax(double? loadKg, double? reps) {
  if (loadKg == null || reps == null || loadKg <= 0 || reps <= 0) return null;
  if (reps == 1) return loadKg;
  return loadKg * (1 + reps / 30);
}

Future<String> exportWorkoutAnalysisCsv(AppDatabase database) async {
  final rows = await database
      .customSelect(
        '''
        SELECT
          exercise_sets.id AS id,
          exercise_sets.timestamp AS timestamp,
          exercise_sets.workout_id AS workout_id,
          plans.title AS plan_title,
          plans.days AS plan_days,
          exercises.name AS exercise,
          exercises.kind AS kind,
          categories.name AS category,
          exercise_sets.reps AS reps,
          exercise_sets.load_kg AS load_kg,
          exercise_sets.duration_ms AS duration_ms,
          exercise_sets.distance_metres AS distance_metres,
          exercise_sets.incline AS incline,
          exercise_sets.body_weight_kg AS body_weight_kg,
          exercise_sets.notes AS notes,
          workouts.notes AS workout_notes
        FROM exercise_sets
        INNER JOIN exercises ON exercises.id = exercise_sets.exercise_id
        LEFT JOIN categories ON categories.id = exercises.category_id
        LEFT JOIN workouts ON workouts.id = exercise_sets.workout_id
        LEFT JOIN plans ON plans.id = workouts.plan_id
        ORDER BY exercise_sets.timestamp, exercise_sets.id
        ''',
        readsFrom: {
          database.exerciseSets,
          database.exercises,
          database.categories,
          database.workouts,
          database.plans,
        },
      )
      .get();

  final out = <List<Object?>>[
    [
      'date',
      'time',
      'workout_id',
      'plan',
      'exercise',
      'category',
      'kind',
      'set_number',
      'reps',
      'weight_kg',
      'volume_kg',
      'est_1rm_kg',
      'duration_min',
      'distance_km',
      'incline',
      'body_weight_kg',
      'notes',
      'workout_notes',
    ],
  ];

  final setCounters = <String, int>{};
  for (final row in rows) {
    final timestamp = row.read<DateTime>('timestamp').toLocal();
    final workoutId = row.readNullable<int>('workout_id');
    final exercise = row.read<String>('exercise');
    final reps = row.readNullable<double>('reps');
    final load = row.readNullable<double>('load_kg');
    final durationMs = row.readNullable<int>('duration_ms');
    final distance = row.readNullable<double>('distance_metres');
    final day = _date.format(timestamp);

    final sessionKey = '${workoutId ?? day}|$exercise';
    final setNumber = setCounters[sessionKey] =
        (setCounters[sessionKey] ?? 0) + 1;

    out.add([
      day,
      _time.format(timestamp),
      workoutId,
      row.readNullable<String>('plan_title') ??
          row.readNullable<String>('plan_days'),
      exercise,
      row.readNullable<String>('category'),
      row.read<String>('kind'),
      setNumber,
      reps,
      _round(load),
      load != null && reps != null ? _round(load * reps) : null,
      _round(estimatedOneRepMax(load, reps)),
      durationMs == null ? null : _round(durationMs / 60000),
      distance == null ? null : _round(distance / 1000, 3),
      row.readNullable<double>('incline'),
      _round(row.readNullable<double>('body_weight_kg')),
      row.readNullable<String>('notes'),
      row.readNullable<String>('workout_notes'),
    ]);
  }

  return _encode(out);
}

class _Day {
  DailyLog? log;
  double? bodyWeightKg;
  final workoutIds = <int>{};
  final workoutNotes = <String>[];
  int sets = 0;
  double volumeKg = 0;
}

Future<String> exportDailyAnalysisCsv(AppDatabase database) async {
  final days = <DateTime, _Day>{};
  _Day dayFor(DateTime value) =>
      days.putIfAbsent(localDay(value), () => _Day());

  for (final log in await database.dailyLogs.select().get()) {
    dayFor(log.date).log = log;
  }

  final weights =
      await (database.bodyWeights.select()..orderBy([
            (row) => OrderingTerm.asc(row.timestamp),
            (row) => OrderingTerm.asc(row.id),
          ]))
          .get();
  for (final weight in weights) {
    dayFor(weight.timestamp).bodyWeightKg = weight.weightKg;
  }

  for (final set in await database.exerciseSets.select().get()) {
    final day = dayFor(set.timestamp);
    day.sets++;
    if (set.workoutId != null) day.workoutIds.add(set.workoutId!);
    if (set.loadKg != null && set.reps != null) {
      day.volumeKg += set.loadKg! * set.reps!;
    }
  }

  final workouts =
      await (database.workouts.select()
            ..orderBy([(row) => OrderingTerm.asc(row.startedAt)]))
          .get();
  for (final workout in workouts) {
    final notes = workout.notes?.trim();
    if (notes == null || notes.isEmpty) continue;
    dayFor(workout.startedAt).workoutNotes.add(notes);
  }

  final out = <List<Object?>>[
    [
      'date',
      'body_weight_kg',
      'sleep_hours',
      'wellbeing_1_5',
      'kcal',
      'protein_g',
      'fat_g',
      'carbs_g',
      'workouts',
      'workout_sets',
      'workout_volume_kg',
      'day_notes',
      'workout_notes',
    ],
  ];
  final sortedDays = days.keys.toList()..sort();
  for (final date in sortedDays) {
    final day = days[date]!;
    out.add([
      _date.format(date),
      _round(day.bodyWeightKg),
      day.log?.sleepHours,
      day.log?.wellbeing,
      day.log?.kcal,
      day.log?.proteinG,
      day.log?.fatG,
      day.log?.carbsG,
      day.workoutIds.length,
      day.sets,
      _round(day.volumeKg),
      day.log?.notes,
      day.workoutNotes.isEmpty ? null : day.workoutNotes.join(' | '),
    ]);
  }

  return _encode(out);
}
