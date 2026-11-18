import 'package:material_ui/material_ui.dart';

import '../links.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/media_widgets.dart';
import 'exercise_edit_screen.dart';

/// Ansicht einer Übung: Videos/Bilder, Coach-Hinweise, Ziele, Equipment.
/// Mit [readOnly] (Athleten-Ansicht im Training) ohne Bearbeiten.
class ExerciseDetailScreen extends StatelessWidget {
  const ExerciseDetailScreen({
    super.key,
    required this.exerciseId,
    this.readOnly = false,
  });

  final String exerciseId;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final e = store.exerciseById(exerciseId);
    if (e == null) {
      // Wurde gerade gelöscht; die Route wird im selben Zug geschlossen.
      return const Scaffold();
    }
    final theme = Theme.of(context);
    final color = AppColors.of(context).category(e.category);
    final clip = store.clipById(e.sourceClipId);
    final empty =
        !e.hasMedia &&
        e.description.isEmpty &&
        e.whenToUse.isEmpty &&
        e.goals.isEmpty &&
        e.equipment.isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(e.name),
        actions: [
          if (!readOnly)
            IconButton(
              tooltip: 'Bearbeiten',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () async {
                final deleted = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => ExerciseEditScreen(exercise: e),
                  ),
                );
                if (deleted == true && context.mounted) {
                  Navigator.pop(context);
                }
              },
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 16, bottom: 32),
        children: [
          if (e.hasMedia) ...[
            MediaGallery(videoLinks: e.videoLinks, imageIds: e.imageIds),
            const SizedBox(height: 16),
          ],
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                CategoryAvatar(e.category, size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e.name, style: theme.textTheme.headlineSmall),
                      const SizedBox(height: 2),
                      Text(
                        [
                          e.category.label,
                          if (e.bodyRegion.isNotEmpty) e.bodyRegion,
                        ].join(' · '),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (e.goals.isNotEmpty) ...[
            const SectionHeader('Ziel'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TagWrap(e.goals, color: color),
            ),
          ],
          if (e.description.isNotEmpty) ...[
            const SectionHeader('Coach-Hinweise'),
            _TextCard(e.description),
          ],
          if (e.whenToUse.isNotEmpty) ...[
            const SectionHeader('Wann einsetzen'),
            _TextCard(e.whenToUse),
          ],
          if (e.equipment.isNotEmpty) ...[
            const SectionHeader('Equipment'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TagWrap(e.equipment),
            ),
          ],
          if (clip != null && !readOnly) ...[
            const SectionHeader('Quelle'),
            ListTile(
              leading: const Icon(Icons.video_library_outlined),
              title: Text(
                clip.title.isNotEmpty ? clip.title : hostOf(clip.url),
              ),
              subtitle: Text('Clip · ${platformOf(clip.url).label}'),
              trailing: const Icon(Icons.open_in_new, size: 18),
              onTap: () => openVideo(context, clip.url),
            ),
          ],
          if (empty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 32, 16, 0),
              child: Text(
                readOnly
                    ? 'Zu dieser Übung sind noch keine Details hinterlegt.'
                    : 'Noch keine Details. Über „Bearbeiten“ kannst du '
                          'Videos, Bilder, Coach-Hinweise und Ziele ergänzen.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TextCard extends StatelessWidget {
  const _TextCard(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: SizedBox(
            width: double.infinity,
            child: Text(text, style: const TextStyle(height: 1.4)),
          ),
        ),
      ),
    );
  }
}
