import 'package:material_ui/material_ui.dart';

import '../models.dart';
import '../store.dart';
import '../widgets/common.dart';
import '../widgets/media_widgets.dart';

/// Legt eine Übung an oder bearbeitet sie. Mit [fromClip] wird eine neue
/// Übung aus einem Clip abgeleitet (Link und Screenshots sind vorbelegt).
///
/// Schließt mit `true`, wenn die Übung gelöscht wurde.
class ExerciseEditScreen extends StatefulWidget {
  const ExerciseEditScreen({super.key, this.exercise, this.fromClip});

  final Exercise? exercise;
  final VideoClip? fromClip;

  @override
  State<ExerciseEditScreen> createState() => _ExerciseEditScreenState();
}

class _ExerciseEditScreenState extends State<ExerciseEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final AppStore _store;
  bool _storeReady = false;

  late final _name = TextEditingController(text: widget.exercise?.name);
  late final _region = TextEditingController(text: widget.exercise?.bodyRegion);
  late final _description = TextEditingController(
    text: widget.exercise?.description,
  );
  late final _whenToUse = TextEditingController(
    text: widget.exercise?.whenToUse,
  );
  late ExerciseCategory _category =
      widget.exercise?.category ?? ExerciseCategory.kraft;
  late List<String> _goals = [...?widget.exercise?.goals];
  late List<String> _equipment = [...?widget.exercise?.equipment];
  late List<String> _links = [
    ...?widget.exercise?.videoLinks,
    if (widget.exercise == null && widget.fromClip != null)
      widget.fromClip!.url,
  ];
  late List<String> _imageIds = [
    ...?widget.exercise?.imageIds,
    if (widget.exercise == null) ...?widget.fromClip?.imageIds,
  ];

  /// In dieser Sitzung neu gespeicherte Bilder (für das Aufräumen).
  final List<String> _addedImageIds = [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_storeReady) {
      _store = StoreScope.read(context);
      _storeReady = true;
    }
  }

  @override
  void dispose() {
    // Verworfene oder wieder entfernte Bilder nicht liegen lassen.
    _store.releaseMedia(_addedImageIds);
    _name.dispose();
    _region.dispose();
    _description.dispose();
    _whenToUse.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    _store.upsertExercise(
      Exercise(
        id: widget.exercise?.id ?? newId(),
        name: _name.text.trim(),
        category: _category,
        bodyRegion: _region.text.trim(),
        description: _description.text.trim(),
        whenToUse: _whenToUse.text.trim(),
        goals: _goals,
        equipment: _equipment,
        videoLinks: _links,
        imageIds: _imageIds,
        sourceClipId: widget.exercise?.sourceClipId ?? widget.fromClip?.id,
      ),
    );
    Navigator.pop(context);
  }

  Future<void> _delete() async {
    final ok = await confirmDelete(
      context,
      title: 'Übung löschen?',
      message:
          '„${widget.exercise!.name}“ wird aus der Bibliothek entfernt. '
          'Bereits geplante Einheiten behalten die Übung.',
    );
    if (ok && mounted) {
      _store.deleteExercise(widget.exercise!.id);
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final theme = Theme.of(context);
    final isNew = widget.exercise == null;
    final clipNotes = widget.fromClip?.notes.trim() ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Text(isNew ? 'Neue Übung' : 'Bearbeiten'),
        actions: [
          if (!isNew)
            IconButton(
              tooltip: 'Löschen',
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              onPressed: _save,
              child: const Text('Speichern'),
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
          children: [
            if (clipNotes.isNotEmpty) ...[
              Card(
                color: theme.colorScheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Notizen aus dem Clip',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(height: 6),
                      SelectableText(
                        clipNotes,
                        style: TextStyle(
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            TextFormField(
              key: const Key('exercise_name'),
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Name'),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Bitte einen Namen eingeben'
                  : null,
            ),
            const SizedBox(height: 16),
            SegmentedButton<ExerciseCategory>(
              showSelectedIcon: false,
              segments: [
                for (final c in ExerciseCategory.values)
                  ButtonSegment(
                    value: c,
                    label: Text(c.label),
                    icon: Icon(c.icon),
                  ),
              ],
              selected: {_category},
              onSelectionChanged: (v) => setState(() => _category = v.first),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _region,
              decoration: const InputDecoration(
                labelText: 'Körperregion / Muskelgruppe',
              ),
            ),
            const SizedBox(height: 24),
            TagPicker(
              label: 'Ziel',
              vocabulary: store.goalVocabulary,
              selected: _goals,
              onChanged: (v) => setState(() => _goals = v),
            ),
            const SizedBox(height: 24),
            const SectionHeader('Videos', padding: EdgeInsets.only(bottom: 8)),
            LinkListEditor(
              links: _links,
              onChanged: (v) => setState(() => _links = v),
            ),
            const SizedBox(height: 24),
            const SectionHeader('Bilder', padding: EdgeInsets.only(bottom: 8)),
            ImageStripEditor(
              ids: _imageIds,
              onAdded: _addedImageIds.addAll,
              onChanged: (v) => setState(() => _imageIds = v),
            ),
            const SizedBox(height: 24),
            TextFormField(
              key: const Key('exercise_description'),
              controller: _description,
              minLines: 3,
              maxLines: 8,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Coach-Hinweise / Ausführung',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _whenToUse,
              minLines: 2,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Wann einsetzen',
                hintText: 'z. B. Warm-up vor Sprints, frühe Reha-Phase',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 24),
            TagPicker(
              label: 'Equipment',
              vocabulary: store.equipmentVocabulary,
              selected: _equipment,
              onChanged: (v) => setState(() => _equipment = v),
            ),
          ],
        ),
      ),
    );
  }
}
