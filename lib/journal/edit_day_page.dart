import 'package:flex/app_fab.dart';
import 'package:flex/database/daily_log_repository.dart';
import 'package:flex/database/database.dart';
import 'package:flex/journal/journal_page.dart';
import 'package:flex/journal/journal_reminder.dart';
import 'package:flex/l10n/l10n.dart';
import 'package:flex/main.dart';
import 'package:flex/utils.dart';
import 'package:flutter/material.dart';

class EditDayPage extends StatefulWidget {
  final DateTime? day;
  final DailyLog? log;
  final double? weightKg;

  const EditDayPage({super.key, this.day, this.log, this.weightKg});

  @override
  State<EditDayPage> createState() => _EditDayPageState();
}

class _EditDayPageState extends State<EditDayPage> {
  final _key = GlobalKey<FormState>();
  final _weight = TextEditingController();
  final _sleep = TextEditingController();
  final _kcal = TextEditingController();
  final _protein = TextEditingController();
  final _fat = TextEditingController();
  final _carbs = TextEditingController();
  final _notes = TextEditingController();
  late DateTime _day = widget.day ?? localDay(DateTime.now());
  int? _wellbeing;
  bool _initialized = false;

  bool get _isNew => widget.day == null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    void fill(TextEditingController controller, num? value) {
      if (value != null) controller.text = formatEditableNumber(context, value);
    }

    final log = widget.log;
    fill(_weight, widget.weightKg);
    fill(_sleep, log?.sleepHours);
    fill(_kcal, log?.kcal);
    fill(_protein, log?.proteinG);
    fill(_fat, log?.fatG);
    fill(_carbs, log?.carbsG);
    _notes.text = log?.notes ?? '';
    _wellbeing = log?.wellbeing;
  }

  @override
  void dispose() {
    for (final controller in [
      _weight,
      _sleep,
      _kcal,
      _protein,
      _fat,
      _carbs,
      _notes,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  String? _validate(String? value, {double max = double.infinity}) {
    if (value == null || value.trim().isEmpty) return null;
    final parsed = parseDisplayNumber(context, value);
    if (parsed == null || parsed < 0 || parsed > max) {
      return context.l10n.invalidNumber;
    }
    return null;
  }

  double? _value(TextEditingController controller) =>
      parseDisplayNumber(context, controller.text);

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) setState(() => _day = localDay(picked));
  }

  Future<void> _save() async {
    if (!_key.currentState!.validate()) return;
    final previousDay = widget.day;
    final weight = _value(_weight);
    final notes = _notes.text.trim();
    final kcal = _value(_kcal)?.round();
    final protein = _value(_protein);
    final fat = _value(_fat);
    final carbs = _value(_carbs);
    final sleep = _value(_sleep);
    final hasLog =
        kcal != null ||
        protein != null ||
        fat != null ||
        carbs != null ||
        sleep != null ||
        _wellbeing != null ||
        notes.isNotEmpty;

    if (widget.log != null && (previousDay != _day || !hasLog)) {
      await deleteDailyLog(db, widget.log!.id);
    }
    if (previousDay != null && previousDay != _day && widget.weightKg != null) {
      await setBodyWeightForDay(db, previousDay, null);
    }
    if (hasLog) {
      await saveDailyLog(
        db,
        day: _day,
        kcal: kcal,
        proteinG: protein,
        fatG: fat,
        carbsG: carbs,
        sleepHours: sleep,
        wellbeing: _wellbeing,
        notes: notes.isEmpty ? null : notes,
      );
    }
    final weightChanged = weight != widget.weightKg || previousDay != _day;
    if (weightChanged && (weight != null || previousDay == _day)) {
      await setBodyWeightForDay(db, _day, weight);
    }
    if (!mounted) return;
    refreshJournalReminders(context.l10n);
    Navigator.pop(context);
  }

  Future<void> _delete() async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.confirmDelete),
        content: Text(l10n.deleteRecordsConfirmation(1)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.actionCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.actionDelete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (widget.log != null) await deleteDailyLog(db, widget.log!.id);
    if (widget.weightKg != null) {
      await setBodyWeightForDay(db, widget.day!, null);
    }
    if (!mounted) return;
    refreshJournalReminders(context.l10n);
    Navigator.pop(context);
  }

  Widget _numberField(
    TextEditingController controller,
    String label, {
    IconData? icon,
    double max = double.infinity,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: icon == null ? null : Icon(icon),
      ),
      validator: (value) => _validate(value, max: max),
      onTap: () => selectAll(controller),
    );
  }

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 8),
    child: Text(
      title,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Text(_isNew ? l10n.addJournalDay : l10n.editJournalDay),
        actions: [
          if (!_isNew)
            IconButton(
              tooltip: l10n.actionDelete,
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: Form(
        key: _key,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 116),
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today_outlined),
              title: Text(l10n.journalDate),
              subtitle: Text(
                formatDisplayDate(context, _day, journalDateFormat),
              ),
              onTap: _pickDay,
            ),
            _section(l10n.journalBodySection),
            Row(
              children: [
                Expanded(
                  child: _numberField(
                    _weight,
                    l10n.bodyWeightKgLabel,
                    icon: Icons.monitor_weight_outlined,
                    max: 400,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _numberField(
                    _sleep,
                    l10n.sleepHoursLabel,
                    icon: Icons.bedtime_outlined,
                    max: 24,
                  ),
                ),
              ],
            ),
            _section(l10n.wellbeingLabel),
            SegmentedButton<int>(
              emptySelectionAllowed: true,
              showSelectedIcon: false,
              segments: [
                for (var score = 1; score <= 5; score++)
                  ButtonSegment(
                    value: score,
                    icon: Icon(wellbeingIcons[score - 1]),
                  ),
              ],
              selected: {?_wellbeing},
              onSelectionChanged: (selection) =>
                  setState(() => _wellbeing = selection.firstOrNull),
            ),
            _section(l10n.journalNutritionSection),
            _numberField(
              _kcal,
              l10n.kcalLabel,
              icon: Icons.local_fire_department_outlined,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _numberField(_protein, l10n.proteinLabel)),
                const SizedBox(width: 12),
                Expanded(child: _numberField(_fat, l10n.fatLabel)),
                const SizedBox(width: 12),
                Expanded(child: _numberField(_carbs, l10n.carbsLabel)),
              ],
            ),
            _section(l10n.notesLabel),
            TextFormField(
              controller: _notes,
              decoration: InputDecoration(hintText: l10n.journalNotesHint),
              minLines: 2,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
            ),
          ],
        ),
      ),
      floatingActionButton: AppFab(
        onPressed: _save,
        label: Text(l10n.actionSave),
        icon: const Icon(Icons.save),
      ),
    );
  }
}
