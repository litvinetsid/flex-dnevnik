import 'dart:io';

import 'package:drift/drift.dart' hide Column;
import 'package:flex/database/daily_log_repository.dart';
import 'package:flex/database/database.dart';
import 'package:flex/l10n/generated/app_localizations.dart';
import 'package:flex/l10n/l10n.dart';
import 'package:flex/logging.dart';
import 'package:flex/main.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:timezone/timezone.dart' as tz;

const _firstReminderId = 7100;
const _daysAhead = 14;

bool get journalRemindersSupported => !kIsWeb && Platform.isAndroid;

FlutterLocalNotificationsPlugin? _plugin;

Future<FlutterLocalNotificationsPlugin> _notifications() async {
  if (_plugin != null) return _plugin!;
  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('ic_launcher'),
    ),
  );
  return _plugin = plugin;
}

/// The device's current UTC offset as a fixed zone, which is enough for a
/// wall-clock reminder without bundling the time zone database.
tz.Location _localZone() {
  final offset = DateTime.now().timeZoneOffset;
  return tz.Location('Local', [tz.minTime], [0], [
    tz.TimeZone(offset, isDst: false, abbreviation: 'LOCAL'),
  ]);
}

/// Days (offset from today) and local times that still need a reminder.
List<(int, DateTime)> journalReminderTimes({
  required DateTime now,
  required Set<DateTime> filledDays,
  required int minutes,
  required int days,
}) {
  return [
    for (var offset = 0; offset < days; offset++)
      if (DateTime(now.year, now.month, now.day + offset) case final day
          when !filledDays.contains(day))
        if (day.add(Duration(minutes: minutes)) case final at
            when at.isAfter(now))
          (offset, at),
  ];
}

/// Schedules one reminder per upcoming day that has no journal entry yet.
///
/// Reminders are planned [_daysAhead] days out so they keep coming even if
/// the app is not opened, and are recalculated whenever the journal changes.
Future<void> refreshJournalReminders(AppLocalizations l10n) async {
  if (!journalRemindersSupported) return;
  try {
    final plugin = await _notifications();
    for (var i = 0; i < _daysAhead; i++) {
      await plugin.cancel(id: _firstReminderId + i);
    }
    final settings = await (db.settings.select()..limit(1)).getSingle();
    if (!settings.journalReminder) return;

    final filled = {
      for (final log in await db.dailyLogs.select().get()) localDay(log.date),
    };
    final zone = _localZone();
    final now = DateTime.now();
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        'journal-reminder',
        l10n.journalReminderChannel,
        channelDescription: l10n.journalReminderChannelDescription,
      ),
    );
    final upcoming = journalReminderTimes(
      now: now,
      filledDays: filled,
      minutes: settings.journalReminderMinutes,
      days: _daysAhead,
    );
    for (final (offset, wallClock) in upcoming) {
      await plugin.zonedSchedule(
        id: _firstReminderId + offset,
        title: l10n.journalReminderTitle,
        body: l10n.journalReminderBody,
        scheduledDate: tz.TZDateTime.from(wallClock, zone),
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  } catch (error, stack) {
    talker.handle(error, stack, 'Could not schedule journal reminders');
  }
}

class JournalReminderButton extends StatelessWidget {
  const JournalReminderButton({super.key});

  Future<void> _open(BuildContext context) async {
    final l10n = context.l10n;
    final settings = context.read<Setting>();
    var enabled = settings.journalReminder;
    var minutes = settings.journalReminderMinutes;

    final result = await showDialog<(bool, int)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(l10n.journalReminder),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.journalReminderDaily),
                value: enabled,
                onChanged: (value) => setState(() => enabled = value),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                enabled: enabled,
                leading: const Icon(Icons.schedule_rounded),
                title: Text(l10n.journalReminderTime),
                trailing: Text(
                  TimeOfDay(
                    hour: minutes ~/ 60,
                    minute: minutes % 60,
                  ).format(context),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                onTap: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay(
                      hour: minutes ~/ 60,
                      minute: minutes % 60,
                    ),
                  );
                  if (picked != null) {
                    setState(() => minutes = picked.hour * 60 + picked.minute);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.actionCancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, (enabled, minutes)),
              child: Text(l10n.actionSave),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;

    final (wantEnabled, wantMinutes) = result;
    var saveEnabled = wantEnabled;
    if (wantEnabled && !(await Permission.notification.request()).isGranted) {
      saveEnabled = false;
      messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text(l10n.journalReminderNoPermission)),
      );
    }
    await db.settings.update().write(
      SettingsCompanion(
        journalReminder: Value(saveEnabled),
        journalReminderMinutes: Value(wantMinutes),
      ),
    );
    await refreshJournalReminders(l10n);
  }

  @override
  Widget build(BuildContext context) {
    if (!journalRemindersSupported) return const SizedBox.shrink();
    final enabled = context.select<Setting, bool>(
      (settings) => settings.journalReminder,
    );
    return IconButton(
      tooltip: context.l10n.journalReminder,
      onPressed: () => _open(context),
      icon: Icon(
        enabled
            ? Icons.notifications_active_rounded
            : Icons.notifications_none_rounded,
      ),
    );
  }
}
