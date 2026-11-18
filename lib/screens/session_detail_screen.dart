import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

import '../format.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'exercise_detail_screen.dart';
import 'session_edit_screen.dart';
import 'workout_screen.dart';

/// Trainer-Sicht auf eine Einheit: Vorgaben, protokollierte Sätze und
/// Rückmeldung des Athleten. Von hier startet der Trainingsmodus.
class SessionDetailScreen extends StatelessWidget {
  const SessionDetailScreen({super.key, required this.sessionId});

  final String sessionId;

  Future<void> _copy(BuildContext context, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Plan in die Zwischenablage kopiert.')),
    );
  }

  Future<void> _share(
    BuildContext context,
    TrainingSession session,
    String text,
  ) async {
    try {
      await SharePlus.instance.share(
        ShareParams(text: text, subject: session.title),
      );
    } catch (_) {
      // Kein Teilen-Dialog verfügbar (z. B. manche Browser): kopieren.
      if (context.mounted) await _copy(context, text);
    }
  }

  Future<void> _duplicate(BuildContext context, TrainingSession session) async {
    final store = StoreScope.read(context);
    final result = await showDialog<({String athleteId, DateTime date})>(
      context: context,
      builder: (_) => _DuplicateDialog(session: session),
    );
    if (result == null || !context.mounted) return;
    final copy = store.duplicateSession(
      session,
      athleteId: result.athleteId,
      date: result.date,
    );
    final name = store.athleteById(copy.athleteId)?.name ?? '';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Kopiert für $name am ${formatDate(copy.date)}.'),
        action: SnackBarAction(
          label: 'Öffnen',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => SessionDetailScreen(sessionId: copy.id),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final session = store.sessionById(sessionId);
    if (session == null) {
      // Wurde gerade gelöscht; die Route wird im selben Zug geschlossen.
      return const Scaffold();
    }
    final theme = Theme.of(context);
    // Athleten sehen ihre Einheit, ändern aber nur das Protokoll.
    final readOnly = store.isAthlete;
    final athlete = store.athleteById(session.athleteId);
    final text = sessionAsText(
      session,
      athlete,
      exerciseOf: store.exerciseById,
    );
    final hasFeedback = session.rpe != null || session.feedback.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(session.title),
        actions: [
          IconButton(
            tooltip: 'Teilen',
            icon: const Icon(Icons.share_outlined),
            onPressed: () => _share(context, session, text),
          ),
          if (!readOnly)
            IconButton(
              tooltip: 'Bearbeiten',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SessionEditScreen(session: session),
                ),
              ),
            ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              switch (v) {
                case 'copy':
                  await _copy(context, text);
                case 'duplicate':
                  await _duplicate(context, session);
                case 'delete':
                  final ok = await confirmDelete(
                    context,
                    title: 'Einheit löschen?',
                    message: '„${session.title}“ wird endgültig entfernt.',
                  );
                  if (ok && context.mounted) {
                    Navigator.pop(context);
                    store.deleteSession(sessionId);
                  }
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'copy',
                child: Text('Als Text kopieren'),
              ),
              if (!readOnly) ...const [
                PopupMenuItem(
                  value: 'duplicate',
                  child: Text('Duplizieren / zuweisen'),
                ),
                PopupMenuItem(value: 'delete', child: Text('Löschen')),
              ],
            ],
          ),
        ],
      ),
      bottomNavigationBar: session.entries.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => WorkoutScreen(sessionId: sessionId),
                    ),
                  ),
                  icon: const Icon(Icons.play_arrow),
                  label: Text(
                    session.done
                        ? 'Protokoll öffnen'
                        : session.started
                        ? 'Training fortsetzen'
                        : 'Training starten',
                  ),
                ),
              ),
            ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.person_outline, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(athlete?.name ?? 'Unbekannter Athlet'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.calendar_today, size: 18),
                      const SizedBox(width: 8),
                      Text(relativeDate(session.date)),
                    ],
                  ),
                  if (session.notes.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(session.notes),
                  ],
                  if (session.totalSets > 0) ...[
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              minHeight: 8,
                              value: session.doneSets / session.totalSets,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '${session.doneSets}/${session.totalSets} Sätze',
                          style: theme.textTheme.labelLarge,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            title: const Text('Einheit erledigt'),
            value: session.done,
            onChanged: (v) => store.setDone(sessionId, v),
          ),
          if (hasFeedback) ...[
            _FeedbackCard(session: session),
            const SizedBox(height: 8),
          ],
          if (session.entries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Text(
                'Diese Einheit enthält noch keine Übungen.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          for (var i = 0; i < session.entries.length; i++)
            _EntryCard(index: i, entry: session.entries[i], readOnly: readOnly),
        ],
      ),
    );
  }
}

class _FeedbackCard extends StatelessWidget {
  const _FeedbackCard({required this.session});

  final TrainingSession session;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (session.rpe != null) ...[
              Column(
                children: [
                  Text(
                    '${session.rpe}',
                    style: TextStyle(
                      fontFamily: headingFont,
                      fontWeight: FontWeight.w700,
                      fontSize: 34,
                      height: 1,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                  Text(
                    'RPE',
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 16),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Rückmeldung des Athleten',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    session.feedback.isEmpty
                        ? 'Kein Kommentar.'
                        : session.feedback,
                    style: TextStyle(color: scheme.onPrimaryContainer),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.index,
    required this.entry,
    required this.readOnly,
  });

  final int index;
  final SessionEntry entry;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final exercise = StoreScope.of(context).exerciseById(entry.exerciseId);
    final done = doneSetTexts(entry);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: exercise == null
              ? null
              : () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ExerciseDetailScreen(
                      exerciseId: exercise.id,
                      readOnly: readOnly,
                    ),
                  ),
                ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CategoryAvatar(entry.category),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${index + 1}. ${entry.name}',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        entrySummary(entry),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (entry.note.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(entry.note),
                      ],
                      if (done.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        TagWrap(done, color: colors.success),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (entry.isComplete)
                  Icon(Icons.check_circle, color: colors.success)
                else if (exercise != null && exercise.videoLinks.isNotEmpty)
                  Icon(
                    Icons.play_circle_outline,
                    color: theme.colorScheme.onSurfaceVariant,
                    semanticLabel: 'mit Video',
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DuplicateDialog extends StatefulWidget {
  const _DuplicateDialog({required this.session});

  final TrainingSession session;

  @override
  State<_DuplicateDialog> createState() => _DuplicateDialogState();
}

class _DuplicateDialogState extends State<_DuplicateDialog> {
  late String _athleteId = widget.session.athleteId;
  late DateTime _date = _initialDate();

  DateTime _initialDate() {
    final next = dateOnly(widget.session.date).add(const Duration(days: 7));
    final today = dateOnly(DateTime.now());
    return next.isBefore(today) ? today : next;
  }

  @override
  Widget build(BuildContext context) {
    final athletes = StoreScope.of(context).athletes;
    final value = athletes.any((a) => a.id == _athleteId) ? _athleteId : null;
    return AlertDialog(
      title: const Text('Einheit duplizieren'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            initialValue: value,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Für Athlet'),
            items: [
              for (final a in athletes)
                DropdownMenuItem(value: a.id, child: Text(a.name)),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _athleteId = v);
            },
          ),
          const SizedBox(height: 16),
          InkWell(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime(_date.year - 2),
                lastDate: DateTime(_date.year + 3),
              );
              if (picked != null) setState(() => _date = dateOnly(picked));
            },
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Datum',
                suffixIcon: Icon(Icons.calendar_today),
              ),
              child: Text(formatDate(_date)),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: value == null
              ? null
              : () => Navigator.pop(context, (
                  athleteId: _athleteId,
                  date: _date,
                )),
          child: const Text('Duplizieren'),
        ),
      ],
    );
  }
}
