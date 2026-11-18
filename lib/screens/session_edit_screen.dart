import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../format.dart';
import '../models.dart';
import '../store.dart';
import '../util.dart';
import '../widgets/common.dart';
import '../widgets/exercise_browser.dart';

/// Plant eine neue Einheit oder bearbeitet eine bestehende.
class SessionEditScreen extends StatefulWidget {
  const SessionEditScreen({super.key, this.session, this.athleteId});

  final TrainingSession? session;

  /// Vorauswahl des Athleten bei einer neuen Einheit.
  final String? athleteId;

  @override
  State<SessionEditScreen> createState() => _SessionEditScreenState();
}

class _SessionEditScreenState extends State<SessionEditScreen> {
  late final _title = TextEditingController(text: widget.session?.title);
  late final _notes = TextEditingController(text: widget.session?.notes);
  late String? _athleteId = widget.session?.athleteId ?? widget.athleteId;
  late DateTime _date = dateOnly(widget.session?.date ?? DateTime.now());
  late final List<SessionEntry> _entries = [...?widget.session?.entries];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Bei nur einem Athleten diesen direkt vorbelegen.
      final athletes = StoreScope.read(context).athletes;
      if (_athleteId == null && athletes.length == 1) {
        setState(() => _athleteId = athletes.first.id);
      }
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(_date.year - 2),
      lastDate: DateTime(_date.year + 3),
    );
    if (picked != null) setState(() => _date = dateOnly(picked));
  }

  Future<void> _addExercises() async {
    final picked = await Navigator.of(context).push<List<Exercise>>(
      MaterialPageRoute(builder: (_) => const ExercisePickerScreen()),
    );
    if (picked == null || picked.isEmpty) return;
    setState(() {
      for (final e in picked) {
        _entries.add(
          SessionEntry(
            id: newId(),
            exerciseId: e.id,
            name: e.name,
            category: e.category,
            sets: e.category == ExerciseCategory.mobility ? 2 : 3,
            reps: e.category == ExerciseCategory.kraft ? '10' : '12',
          ),
        );
      }
    });
  }

  Future<void> _editEntry(int index) async {
    final updated = await showEntrySheet(context, _entries[index]);
    if (updated != null) setState(() => _entries[index] = updated);
  }

  void _save() {
    if (_athleteId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte einen Athleten auswählen.')),
      );
      return;
    }
    final title = _title.text.trim();
    final base = widget.session;
    final session =
        (base ??
                TrainingSession(
                  id: newId(),
                  athleteId: _athleteId!,
                  title: '',
                  date: _date,
                ))
            .copyWith(
              athleteId: _athleteId!,
              title: title.isEmpty ? 'Training' : title,
              date: _date,
              notes: _notes.text.trim(),
              entries: List.of(_entries),
            );
    StoreScope.read(context).upsertSession(session);
    Navigator.pop(context, session);
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final theme = Theme.of(context);
    final athletes = store.athletes;
    final athleteValue = athletes.any((a) => a.id == _athleteId)
        ? _athleteId
        : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.session == null ? 'Einheit planen' : 'Einheit bearbeiten',
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              onPressed: _save,
              child: const Text('Speichern'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          DropdownButtonFormField<String>(
            key: ValueKey('athlete_$athleteValue'),
            initialValue: athleteValue,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Athlet'),
            items: [
              for (final a in athletes)
                DropdownMenuItem(value: a.id, child: Text(a.name)),
            ],
            onChanged: (v) => setState(() => _athleteId = v),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('session_title'),
            controller: _title,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Titel',
              hintText: 'z. B. Kraft Unterkörper, Reha Schulter',
            ),
          ),
          const SizedBox(height: 16),
          InkWell(
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(10),
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Datum',
                suffixIcon: Icon(Icons.calendar_today),
              ),
              child: Text(formatDate(_date)),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _notes,
            minLines: 2,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Hinweise für den Athleten (optional)',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Übungen (${_entries.length})',
                  style: theme.textTheme.titleLarge,
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: _addExercises,
                icon: const Icon(Icons.add),
                label: const Text('Übung hinzufügen'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_entries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Noch keine Übungen. Füge Kraft-, Physio- oder '
                'Mobility-Übungen aus der Bibliothek hinzu.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: _entries.length,
              onReorderItem: (oldIndex, newIndex) {
                setState(() {
                  _entries.insert(newIndex, _entries.removeAt(oldIndex));
                });
              },
              itemBuilder: (context, i) {
                final e = _entries[i];
                return Padding(
                  key: ValueKey(e.id),
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Card(
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      contentPadding: const EdgeInsets.only(left: 4, right: 4),
                      leading: ReorderableDragStartListener(
                        index: i,
                        child: const Padding(
                          padding: EdgeInsets.all(12),
                          child: Icon(Icons.drag_indicator),
                        ),
                      ),
                      title: Text(e.name),
                      subtitle: Text(
                        [
                          entrySummary(e),
                          if (e.note.isNotEmpty) e.note,
                        ].join('\n'),
                      ),
                      trailing: IconButton(
                        tooltip: 'Entfernen',
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => _entries.removeAt(i)),
                      ),
                      onTap: () => _editEntry(i),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

/// Mehrfachauswahl aus der Übungsbibliothek.
class ExercisePickerScreen extends StatefulWidget {
  const ExercisePickerScreen({super.key});

  @override
  State<ExercisePickerScreen> createState() => _ExercisePickerScreenState();
}

class _ExercisePickerScreenState extends State<ExercisePickerScreen> {
  // Reihenfolge der Auswahl bleibt erhalten.
  final List<Exercise> _selected = [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Übungen auswählen')),
      body: ExerciseBrowser(
        selectedIds: {for (final e in _selected) e.id},
        onTap: (e) => setState(() {
          final i = _selected.indexWhere((s) => s.id == e.id);
          if (i >= 0) {
            _selected.removeAt(i);
          } else {
            _selected.add(e);
          }
        }),
      ),
      floatingActionButton: _selected.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => Navigator.pop(context, _selected),
              icon: const Icon(Icons.check),
              label: Text('Hinzufügen (${_selected.length})'),
            ),
    );
  }
}

/// Bottom-Sheet für die Vorgabe einer Übung (Sätze, Wdh., Gewicht …).
Future<SessionEntry?> showEntrySheet(BuildContext context, SessionEntry entry) {
  return showModalBottomSheet<SessionEntry>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _EntrySheet(entry: entry),
  );
}

class _EntrySheet extends StatefulWidget {
  const _EntrySheet({required this.entry});

  final SessionEntry entry;

  @override
  State<_EntrySheet> createState() => _EntrySheetState();
}

class _EntrySheetState extends State<_EntrySheet> {
  late final _sets = TextEditingController(text: '${widget.entry.sets}');
  late final _reps = TextEditingController(text: widget.entry.reps);
  late final _weight = TextEditingController(
    text: widget.entry.weightKg == null ? '' : fmtNum(widget.entry.weightKg!),
  );
  late final _load = TextEditingController(text: widget.entry.load);
  late final _rest = TextEditingController(
    text: widget.entry.restSec?.toString() ?? '',
  );
  late final _note = TextEditingController(text: widget.entry.note);

  @override
  void dispose() {
    _sets.dispose();
    _reps.dispose();
    _weight.dispose();
    _load.dispose();
    _rest.dispose();
    _note.dispose();
    super.dispose();
  }

  void _apply() {
    final sets = int.tryParse(_sets.text.trim()) ?? 1;
    final rest = int.tryParse(_rest.text.trim());
    final weight = parseNum(_weight.text);
    Navigator.pop(
      context,
      widget.entry.copyWith(
        sets: sets < 1 ? 1 : sets,
        reps: _reps.text.trim(),
        weightKg: () => (weight == null || weight <= 0) ? null : weight,
        load: _load.text.trim(),
        restSec: () => (rest == null || rest <= 0) ? null : rest,
        note: _note.text.trim(),
        // Bereits abgehakte Sätze bleiben; offene richten sich neu nach
        // der geänderten Vorgabe.
        logs: widget.entry.logs.where((l) => l.done).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final digits = [FilteringTextInputFormatter.digitsOnly];
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
            Row(
              children: [
                CategoryAvatar(widget.entry.category),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.entry.name,
                    style: theme.textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('entry_sets'),
                    controller: _sets,
                    keyboardType: TextInputType.number,
                    inputFormatters: digits,
                    decoration: const InputDecoration(labelText: 'Sätze'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    key: const Key('entry_reps'),
                    controller: _reps,
                    decoration: const InputDecoration(
                      labelText: 'Wdh. / Dauer',
                      hintText: '8, 30 s',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    key: const Key('entry_weight'),
                    controller: _weight,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Gewicht',
                      suffixText: 'kg',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    key: const Key('entry_load'),
                    controller: _load,
                    decoration: const InputDecoration(
                      labelText: 'Widerstand / Gerät',
                      hintText: 'rotes Band, Körpergewicht',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _rest,
                    keyboardType: TextInputType.number,
                    inputFormatters: digits,
                    decoration: const InputDecoration(
                      labelText: 'Pause',
                      suffixText: 's',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('entry_note'),
              controller: _note,
              minLines: 1,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Coach-Hinweis (Tempo, Schmerzgrenze …)',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: _apply, child: const Text('Übernehmen')),
          ],
        ),
      ),
    );
  }
}
