import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../links.dart';
import '../models.dart';
import '../store.dart';
import '../widgets/common.dart';
import '../widgets/media_widgets.dart';
import 'exercise_detail_screen.dart';
import 'exercise_edit_screen.dart';

/// Ein Clip: Link zu einem Reel/Short/Video plus Notizen und Screenshots.
/// Aus einem Clip lassen sich beliebig viele Übungen ableiten.
class ClipEditScreen extends StatefulWidget {
  const ClipEditScreen({super.key, this.clip});

  final VideoClip? clip;

  @override
  State<ClipEditScreen> createState() => _ClipEditScreenState();
}

class _ClipEditScreenState extends State<ClipEditScreen> {
  late final AppStore _store;
  bool _storeReady = false;

  late final String _id = widget.clip?.id ?? newId();
  late final DateTime _createdAt = widget.clip?.createdAt ?? DateTime.now();
  late final _url = TextEditingController(text: widget.clip?.url);
  late final _title = TextEditingController(text: widget.clip?.title);
  late final _notes = TextEditingController(text: widget.clip?.notes);
  late List<String> _imageIds = [...?widget.clip?.imageIds];
  final List<String> _addedImageIds = [];
  String? _urlError;

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
    _store.releaseMedia(_addedImageIds);
    _url.dispose();
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isNotEmpty) {
      setState(() {
        _url.text = text;
        _urlError = null;
      });
    }
  }

  /// Speichert den Clip; `null`, wenn der Link ungültig ist.
  VideoClip? _persist() {
    final uri = parseHttpUrl(_url.text);
    if (uri == null) {
      setState(() => _urlError = 'Bitte einen gültigen Link eingeben');
      return null;
    }
    final clip = VideoClip(
      id: _id,
      url: uri.toString(),
      title: _title.text.trim(),
      notes: _notes.text.trim(),
      imageIds: _imageIds,
      createdAt: _createdAt,
    );
    _store.upsertClip(clip);
    return clip;
  }

  void _save() {
    if (_persist() != null) Navigator.pop(context);
  }

  Future<void> _deriveExercise() async {
    final clip = _persist();
    if (clip == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ExerciseEditScreen(fromClip: clip)),
    );
  }

  Future<void> _delete() async {
    final n = _store.exercisesFromClip(_id).length;
    final ok = await confirmDelete(
      context,
      title: 'Clip löschen?',
      message: n == 0
          ? 'Der Clip wird aus der Sammlung entfernt.'
          : 'Der Clip wird entfernt. Die $n daraus angelegten '
                '${n == 1 ? 'Übung bleibt' : 'Übungen bleiben'} erhalten.',
    );
    if (ok && mounted) {
      _store.deleteClip(_id);
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final exists = store.clipById(_id) != null;
    final derived = store.exercisesFromClip(_id);
    final validUrl = parseHttpUrl(_url.text) != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(exists ? 'Clip' : 'Clip hinzufügen'),
        actions: [
          if (exists)
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
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          TextField(
            key: const Key('clip_url'),
            controller: _url,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: 'Link',
              hintText: 'Instagram-Reel, YouTube-Short, TikTok …',
              errorText: _urlError,
              suffixIcon: IconButton(
                tooltip: 'Aus Zwischenablage einfügen',
                icon: const Icon(Icons.content_paste),
                onPressed: _paste,
              ),
            ),
            onChanged: (_) => setState(() => _urlError = null),
          ),
          if (validUrl) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    VideoThumb(_url.text, posterImageId: _imageIds.firstOrNull),
                    Material(
                      type: MaterialType.transparency,
                      child: InkWell(
                        onTap: () => openVideo(context, _url.text),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            key: const Key('clip_title'),
            controller: _title,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Titel (optional)',
              hintText: 'z. B. Hüft-Mobility-Flow von …',
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('clip_notes'),
            controller: _notes,
            minLines: 4,
            maxLines: 12,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Notizen / Transkript',
              hintText:
                  'Bildunterschrift oder gesprochenen Text einfügen, '
                  'eigene Beobachtungen ergänzen',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 24),
          const SectionHeader(
            'Screenshots',
            padding: EdgeInsets.only(bottom: 8),
          ),
          ImageStripEditor(
            ids: _imageIds,
            addLabel: 'Screenshot',
            onAdded: _addedImageIds.addAll,
            onChanged: (v) => setState(() => _imageIds = v),
          ),
          const SizedBox(height: 24),
          SectionHeader(
            'Übungen aus diesem Clip (${derived.length})',
            padding: const EdgeInsets.only(bottom: 8),
          ),
          for (final e in derived)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  leading: CategoryAvatar(e.category),
                  title: Text(e.name),
                  subtitle: Text(
                    [
                      e.category.label,
                      if (e.goals.isNotEmpty) e.goals.join(', '),
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ExerciseDetailScreen(exerciseId: e.id),
                    ),
                  ),
                ),
              ),
            ),
          FilledButton.tonalIcon(
            onPressed: _deriveExercise,
            icon: const Icon(Icons.add),
            label: const Text('Übung daraus anlegen'),
          ),
        ],
      ),
    );
  }
}
