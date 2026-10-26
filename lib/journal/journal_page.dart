import 'package:flex/app_fab.dart';
import 'package:flex/database/daily_log_repository.dart';
import 'package:flex/database/database.dart';
import 'package:flex/empty_state.dart';
import 'package:flex/journal/edit_day_page.dart';
import 'package:flex/journal/journal_reminder.dart';
import 'package:flex/l10n/l10n.dart';
import 'package:flex/main.dart';
import 'package:flex/platform_page_route.dart';
import 'package:flex/utils.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

const wellbeingIcons = [
  Icons.sentiment_very_dissatisfied_rounded,
  Icons.sentiment_dissatisfied_rounded,
  Icons.sentiment_neutral_rounded,
  Icons.sentiment_satisfied_rounded,
  Icons.sentiment_very_satisfied_rounded,
];

const journalDateFormat = 'EEE, d MMMM yyyy';

class JournalPage extends StatefulWidget {
  final TabController tabController;

  const JournalPage({super.key, required this.tabController});

  @override
  State<JournalPage> createState() => _JournalPageState();
}

class _JournalPageState extends State<JournalPage>
    with AutomaticKeepAliveClientMixin {
  final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return NavigatorPopHandler(
      onPopWithResult: (result) {
        if (_navKey.currentState!.canPop() == false) return;
        final settings = context.read<Setting>();
        final index = settings.tabs.split(',').indexOf('JournalPage');
        if (widget.tabController.index == index) _navKey.currentState!.pop();
      },
      child: Navigator(
        key: _navKey,
        onGenerateRoute: (settings) => FlexPageRoute(
          builder: (context) => const _JournalList(),
          settings: settings,
        ),
      ),
    );
  }
}

typedef _JournalDay = ({DateTime day, DailyLog? log, double? weightKg});

class _JournalList extends StatefulWidget {
  const _JournalList();

  @override
  State<_JournalList> createState() => _JournalListState();
}

class _JournalListState extends State<_JournalList> {
  late final Stream<List<DailyLog>> _logs = watchDailyLogs(db);
  late final Stream<Map<DateTime, double>> _weights = watchDailyBodyWeights(db);
  final _scroll = ScrollController();

  void _open({DateTime? day, DailyLog? log, double? weightKg}) {
    Navigator.of(context).push(
      FlexPageRoute(
        builder: (context) =>
            EditDayPage(day: day, log: log, weightKg: weightKg),
      ),
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  List<_JournalDay> _merge(List<DailyLog> logs, Map<DateTime, double> weights) {
    final byDay = {for (final log in logs) localDay(log.date): log};
    final days = {...byDay.keys, ...weights.keys}.toList()
      ..sort((a, b) => b.compareTo(a));
    return [
      for (final day in days)
        (day: day, log: byDay[day], weightKg: weights[day]),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.navJournal),
        actions: const [JournalReminderButton()],
      ),
      body: StreamBuilder<List<DailyLog>>(
        stream: _logs,
        builder: (context, logs) => StreamBuilder<Map<DateTime, double>>(
          stream: _weights,
          builder: (context, weights) {
            if (logs.data == null || weights.data == null) {
              return const Center(child: CircularProgressIndicator());
            }
            final days = _merge(logs.data!, weights.data!);
            if (days.isEmpty) {
              return AppEmptyState(
                icon: Icons.book_outlined,
                title: l10n.journalEmptyTitle,
                message: l10n.journalEmptyMessage,
                actionLabel: l10n.addJournalDay,
                actionIcon: Icons.add_rounded,
                onAction: _open,
              );
            }

            return ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.only(bottom: 116),
              itemCount: days.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) return _SummaryCard(days: days);
                final entry = days[index - 1];
                return _DayTile(
                  entry: entry,
                  onTap: () => _open(
                    day: entry.day,
                    log: entry.log,
                    weightKg: entry.weightKg,
                  ),
                );
              },
            );
          },
        ),
      ),
      floatingActionButton: AppFab(
        onPressed: _open,
        label: Text(l10n.addJournalDay),
        icon: const Icon(Icons.add),
        scroll: _scroll,
      ),
    );
  }
}

String _number(BuildContext context, num value, [int digits = 1]) =>
    formatDisplayNumber(context, value, maxDigits: digits);

String? macrosText(
  BuildContext context,
  double? protein,
  double? fat,
  double? carbs,
) {
  if (protein == null && fat == null && carbs == null) return null;
  String format(double? value) =>
      value == null ? '–' : _number(context, value, 0);
  return context.l10n.macrosShort(format(protein), format(fat), format(carbs));
}

class _DayTile extends StatelessWidget {
  final _JournalDay entry;
  final VoidCallback onTap;

  const _DayTile({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final log = entry.log;
    final facts = <String>[
      if (log?.kcal != null) l10n.kcalValue(_number(context, log!.kcal!, 0)),
      if (entry.weightKg != null)
        l10n.weightKgValue(_number(context, entry.weightKg!)),
      if (log?.sleepHours != null)
        l10n.sleepHoursValue(_number(context, log!.sleepHours!)),
    ];
    final macros = log == null
        ? null
        : macrosText(context, log.proteinG, log.fatG, log.carbsG);
    final wellbeing = log?.wellbeing;

    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.secondaryContainer,
        foregroundColor: theme.colorScheme.onSecondaryContainer,
        child: Icon(
          wellbeing == null
              ? Icons.today_outlined
              : wellbeingIcons[wellbeing - 1],
        ),
      ),
      title: Text(formatDisplayDate(context, entry.day, journalDateFormat)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (facts.isNotEmpty) Text(facts.join(' · ')),
          if (macros != null) Text(macros),
          if (log?.notes != null)
            Text(
              log!.notes!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final List<_JournalDay> days;

  const _SummaryCard({required this.days});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final since = localDay(DateTime.now()).subtract(const Duration(days: 6));
    final recent = days.where((entry) => !entry.day.isBefore(since)).toList();
    final logs = recent.map((entry) => entry.log).whereType<DailyLog>();
    final kcal = average(logs.map((log) => log.kcal));
    final sleep = average(logs.map((log) => log.sleepHours));
    final wellbeing = average(logs.map((log) => log.wellbeing));
    final latestWeight = days
        .map((entry) => entry.weightKg)
        .whereType<double>()
        .firstOrNull;

    Widget stat(IconData icon, String label, String? value) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(height: 4),
          Text(
            value ?? '–',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.journalAverage7Days, style: theme.textTheme.labelLarge),
            const SizedBox(height: 12),
            Row(
              children: [
                stat(
                  Icons.local_fire_department_outlined,
                  l10n.kcalShort,
                  kcal == null ? null : _number(context, kcal, 0),
                ),
                stat(
                  Icons.bedtime_outlined,
                  l10n.sleepShort,
                  sleep == null ? null : _number(context, sleep),
                ),
                stat(
                  Icons.monitor_weight_outlined,
                  l10n.weightShort,
                  latestWeight == null ? null : _number(context, latestWeight),
                ),
                stat(
                  Icons.mood_outlined,
                  l10n.wellbeingShort,
                  wellbeing == null ? null : _number(context, wellbeing),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
