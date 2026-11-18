import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../format.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/common.dart';
import '../widgets/media_widgets.dart';
import '../workout.dart';
import 'exercise_detail_screen.dart';

/// Trainingsmodus für den Athleten: Übung für Übung durchgehen, Sätze mit
/// einem Tipp wie vorgegeben abhaken oder Gewicht/Wiederholungen anpassen.
/// Jeder Tipp wird sofort gespeichert; das Training lässt sich jederzeit
/// unterbrechen und fortsetzen.
class WorkoutScreen extends StatefulWidget {
  const WorkoutScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  State<WorkoutScreen> createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen> {
  PageController? _pages;
  int _page = 0;

  /// Übungen ohne Gewichtsvorgabe, für die der Athlet Gewicht erfassen will.
  final Set<String> _weightEnabled = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_pages == null) {
      // Beim Fortsetzen bei der ersten unvollständigen Übung einsteigen.
      final session = StoreScope.read(context).sessionById(widget.sessionId);
      final firstOpen = session?.entries.indexWhere((e) => !e.isComplete) ?? -1;
      _page = firstOpen < 0 ? 0 : firstOpen;
      _pages = PageController(initialPage: _page);
    }
  }

  @override
  void dispose() {
    _pages?.dispose();
    super.dispose();
  }

  void _go(int page) {
    _pages!.animateToPage(
      page,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  Future<void> _finish(TrainingSession session) async {
    final store = StoreScope.read(context);
    final result = await showModalBottomSheet<({int? rpe, String feedback})>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _FinishSheet(session: session),
    );
    if (result == null || !mounted) return;
    final current = store.sessionById(widget.sessionId);
    if (current != null) {
      store.upsertSession(
        current.copyWith(
          done: true,
          rpe: () => result.rpe,
          feedback: result.feedback,
        ),
      );
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final session = store.sessionById(widget.sessionId);
    if (session == null || session.entries.isEmpty) {
      return Scaffold(appBar: AppBar());
    }
    final n = session.entries.length;
    final page = _page.clamp(0, n - 1);
    final last = page == n - 1;
    final total = session.totalSets;

    return Scaffold(
      appBar: AppBar(
        title: Text('Übung ${page + 1} von $n'),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text(
                '${session.doneSets}/$total Sätze',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(5),
          child: LinearProgressIndicator(
            minHeight: 5,
            value: total == 0 ? 0 : session.doneSets / total,
            backgroundColor: Colors.white24,
          ),
        ),
      ),
      body: PageView.builder(
        controller: _pages,
        itemCount: n,
        onPageChanged: (p) => setState(() => _page = p),
        itemBuilder: (context, i) {
          final entry = session.entries[i];
          return _EntryPage(
            sessionId: session.id,
            entry: entry,
            weightEnabled: _weightEnabled.contains(entry.id),
            onEnableWeight: () => setState(() => _weightEnabled.add(entry.id)),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              if (page > 0) ...[
                OutlinedButton(
                  onPressed: () => _go(page - 1),
                  child: const Text('Zurück'),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: FilledButton(
                  key: const Key('workout_next'),
                  onPressed: last
                      ? () => _finish(session)
                      : () => _go(page + 1),
                  child: Text(last ? 'Abschließen' : 'Weiter'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EntryPage extends StatelessWidget {
  const _EntryPage({
    required this.sessionId,
    required this.entry,
    required this.weightEnabled,
    required this.onEnableWeight,
  });

  final String sessionId;
  final SessionEntry entry;
  final bool weightEnabled;
  final VoidCallback onEnableWeight;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final exercise = store.exerciseById(entry.exerciseId);
    final target = parseRepsTarget(entry.reps);
    final logs = workingLogs(entry);
    final showWeight =
        weightEnabled ||
        entry.weightKg != null ||
        logs.any((l) => l.weightKg != null);
    final anyOpen = logs.any((l) => !l.done);
    final hasDetails =
        exercise != null &&
        (exercise.hasMedia ||
            exercise.description.isNotEmpty ||
            exercise.whenToUse.isNotEmpty);

    void update(SessionEntry e) => store.updateEntry(sessionId, e);

    Future<void> openDetails() => Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            ExerciseDetailScreen(exerciseId: exercise!.id, readOnly: true),
      ),
    );

    final labelStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: scheme.onSurfaceVariant,
    );

    return ListView(
      padding: const EdgeInsets.only(top: 16, bottom: 24),
      children: [
        if (exercise != null && exercise.hasMedia) ...[
          MediaGallery(
            videoLinks: exercise.videoLinks,
            imageIds: exercise.imageIds,
            height: 160,
          ),
          const SizedBox(height: 16),
        ],
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CategoryAvatar(entry.category, size: 46),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.name, style: theme.textTheme.headlineMedium),
                    const SizedBox(height: 4),
                    Text(
                      'Vorgabe: ${entrySummary(entry)}',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (entry.note.isNotEmpty)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.sports, size: 20, color: scheme.onPrimaryContainer),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    entry.note,
                    style: TextStyle(color: scheme.onPrimaryContainer),
                  ),
                ),
              ],
            ),
          ),
        if (hasDetails)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 8, top: 4),
              child: TextButton.icon(
                onPressed: openDetails,
                icon: const Icon(Icons.info_outline),
                label: const Text('Ausführung ansehen'),
              ),
            ),
          ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              SizedBox(width: 30, child: Text('Satz', style: labelStyle)),
              if (showWeight) ...[
                Expanded(
                  flex: 5,
                  child: Center(child: Text('kg', style: labelStyle)),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                flex: 4,
                child: Center(child: Text(target.unit, style: labelStyle)),
              ),
              const SizedBox(width: 60),
            ],
          ),
        ),
        for (var i = 0; i < logs.length; i++)
          _SetRow(
            index: i,
            log: logs[i],
            unit: target.unit,
            showWeight: showWeight,
            onToggle: () {
              HapticFeedback.selectionClick();
              update(toggleSet(entry, i));
            },
            onWeight: (v) => update(changeSet(entry, i, weightKg: () => v)),
            onReps: (v) => update(changeSet(entry, i, reps: () => v)),
            repsStep: target.step,
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton.icon(
                    onPressed: () => update(addSet(entry)),
                    icon: const Icon(Icons.add),
                    label: const Text('Satz'),
                  ),
                  if (canRemoveLastSet(entry))
                    TextButton.icon(
                      onPressed: () => update(removeLastSet(entry)),
                      icon: const Icon(Icons.remove),
                      label: const Text('Satz'),
                    ),
                  if (!showWeight)
                    TextButton(
                      onPressed: onEnableWeight,
                      child: const Text('Gewicht erfassen'),
                    ),
                ],
              ),
              if (anyOpen)
                FilledButton.tonalIcon(
                  key: const Key('complete_all'),
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    update(completeAll(entry));
                  },
                  icon: const Icon(Icons.done_all),
                  label: const Text('Alle wie geplant'),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SetRow extends StatelessWidget {
  const _SetRow({
    required this.index,
    required this.log,
    required this.unit,
    required this.showWeight,
    required this.onToggle,
    required this.onWeight,
    required this.onReps,
    required this.repsStep,
  });

  final int index;
  final SetLog log;
  final String unit;
  final bool showWeight;
  final VoidCallback onToggle;
  final ValueChanged<double?> onWeight;
  final ValueChanged<int?> onReps;
  final int repsStep;

  Future<void> _typeWeight(BuildContext context) async {
    final text = await _askNumber(
      context,
      title: 'Gewicht (kg)',
      initial: log.weightKg == null ? '' : fmtNum(log.weightKg!),
      decimal: true,
    );
    if (text == null) return;
    final v = parseNum(text);
    onWeight(v == null || v < 0 ? null : v);
  }

  Future<void> _typeReps(BuildContext context) async {
    final text = await _askNumber(
      context,
      title: unit == 'Wdh.' ? 'Wiederholungen' : 'Dauer ($unit)',
      initial: log.reps?.toString() ?? '',
      decimal: false,
    );
    if (text == null) return;
    final v = int.tryParse(text.trim());
    onReps(v == null || v < 0 ? null : v);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = AppColors.of(context);
    final weight = log.weightKg;
    final reps = log.reps;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Text(
              '${index + 1}',
              style: TextStyle(
                fontFamily: headingFont,
                fontWeight: FontWeight.w700,
                fontSize: 24,
                color: log.done ? colors.success : scheme.onSurface,
              ),
            ),
          ),
          if (showWeight) ...[
            Expanded(
              flex: 5,
              child: _Stepper(
                keyPrefix: 'w$index',
                text: weight == null ? '–' : fmtNum(weight),
                done: log.done,
                onMinus: weight == null || weight <= 0
                    ? null
                    : () => onWeight(weight - 2.5 < 0 ? 0 : weight - 2.5),
                onPlus: () => onWeight((weight ?? 0) + 2.5),
                onTapValue: () => _typeWeight(context),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            flex: 4,
            child: _Stepper(
              keyPrefix: 'r$index',
              text: reps == null ? '–' : '$reps',
              done: log.done,
              onMinus: reps == null || reps <= 0
                  ? null
                  : () => onReps(reps - repsStep < 0 ? 0 : reps - repsStep),
              onPlus: () => onReps((reps ?? 0) + repsStep),
              onTapValue: () => _typeReps(context),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 48,
            height: 48,
            child: Material(
              key: Key('check$index'),
              color: log.done ? colors.success : Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  width: 2,
                  color: log.done ? colors.success : scheme.outline,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onToggle,
                child: Icon(
                  Icons.check,
                  size: 28,
                  color: log.done ? scheme.surface : scheme.outline,
                  semanticLabel: log.done
                      ? 'Satz ${index + 1} erledigt'
                      : 'Satz ${index + 1} abhaken',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Wert mit Minus/Plus; Tipp auf die Zahl öffnet die direkte Eingabe.
class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.keyPrefix,
    required this.text,
    required this.done,
    required this.onMinus,
    required this.onPlus,
    required this.onTapValue,
  });

  final String keyPrefix;
  final String text;
  final bool done;
  final VoidCallback? onMinus;
  final VoidCallback onPlus;
  final VoidCallback onTapValue;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = AppColors.of(context);

    Widget button(String suffix, IconData icon, VoidCallback? onTap) => InkWell(
      key: Key('${keyPrefix}_$suffix'),
      onTap: onTap,
      child: SizedBox(
        width: 34,
        height: 48,
        child: Icon(
          icon,
          size: 20,
          color: onTap == null ? scheme.outlineVariant : scheme.onSurface,
        ),
      ),
    );

    return Material(
      color: done
          ? colors.success.withValues(alpha: 0.12)
          : scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: done ? colors.success : scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          button('minus', Icons.remove, onMinus),
          Expanded(
            child: InkWell(
              key: Key('${keyPrefix}_value'),
              onTap: onTapValue,
              child: SizedBox(
                height: 48,
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      text,
                      style: const TextStyle(
                        fontFamily: headingFont,
                        fontWeight: FontWeight.w700,
                        fontSize: 24,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          button('plus', Icons.add, onPlus),
        ],
      ),
    );
  }
}

Future<String?> _askNumber(
  BuildContext context, {
  required String title,
  required String initial,
  required bool decimal,
}) {
  final controller = TextEditingController(text: initial);
  controller.selection = TextSelection(
    baseOffset: 0,
    extentOffset: initial.length,
  );
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        key: const Key('number_input'),
        controller: controller,
        autofocus: true,
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        inputFormatters: [
          FilteringTextInputFormatter.allow(
            RegExp(decimal ? r'[0-9.,]' : r'[0-9]'),
          ),
        ],
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

/// Abschluss: Belastung (RPE) und Rückmeldung an den Trainer.
class _FinishSheet extends StatefulWidget {
  const _FinishSheet({required this.session});

  final TrainingSession session;

  @override
  State<_FinishSheet> createState() => _FinishSheetState();
}

class _FinishSheetState extends State<_FinishSheet> {
  late int? _rpe = widget.session.rpe;
  late final _feedback = TextEditingController(text: widget.session.feedback);

  @override
  void dispose() {
    _feedback.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = widget.session;
    final open = s.totalSets - s.doneSets;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Einheit abschließen', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(
              open == 0
                  ? 'Alle ${s.totalSets} Sätze abgehakt.'
                  : '${s.doneSets} von ${s.totalSets} Sätzen abgehakt – '
                        '$open noch offen.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SectionHeader(
              'Wie anstrengend war es? (1 leicht – 10 maximal)',
              padding: EdgeInsets.only(top: 20, bottom: 8),
            ),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var i = 1; i <= 10; i++)
                  ChoiceChip(
                    key: Key('rpe_$i'),
                    label: SizedBox(
                      width: 22,
                      child: Text('$i', textAlign: TextAlign.center),
                    ),
                    selected: _rpe == i,
                    onSelected: (on) => setState(() => _rpe = on ? i : null),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('feedback'),
              controller: _feedback,
              minLines: 2,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Rückmeldung an den Coach (optional)',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('finish_confirm'),
              onPressed: () => Navigator.pop(context, (
                rpe: _rpe,
                feedback: _feedback.text.trim(),
              )),
              child: const Text('Einheit abschließen'),
            ),
          ],
        ),
      ),
    );
  }
}
