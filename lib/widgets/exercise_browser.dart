import 'package:material_ui/material_ui.dart';

import '../models.dart';
import '../store.dart';
import 'common.dart';
import 'media_widgets.dart';

/// Durchsuch- und filterbare Übungsliste. Wird für die Bibliothek und
/// (mit [selectedIds]) für die Mehrfachauswahl beim Planen verwendet.
class ExerciseBrowser extends StatefulWidget {
  const ExerciseBrowser({super.key, required this.onTap, this.selectedIds});

  final ValueChanged<Exercise> onTap;
  final Set<String>? selectedIds;

  @override
  State<ExerciseBrowser> createState() => _ExerciseBrowserState();
}

class _ExerciseBrowserState extends State<ExerciseBrowser> {
  String _query = '';
  ExerciseCategory? _category;
  String? _goal;
  bool _onlyReview = false;

  Future<void> _pickGoal() async {
    final store = StoreScope.read(context);
    final counts = <String, int>{};
    for (final e in store.exercises) {
      for (final g in e.goals) {
        counts[g] = (counts[g] ?? 0) + 1;
      }
    }
    final goals = store.goalVocabulary
        .where((g) => (counts[g] ?? 0) > 0)
        .toList();
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.7,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              const SectionHeader(
                'Nach Ziel filtern',
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              ),
              ListTile(
                title: const Text('Alle Ziele'),
                trailing: _goal == null ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(context, ''),
              ),
              for (final g in goals)
                ListTile(
                  title: Text(g),
                  subtitle: Text(
                    '${counts[g]} ${counts[g] == 1 ? 'Übung' : 'Übungen'}',
                  ),
                  trailing: _goal == g ? const Icon(Icons.check) : null,
                  onTap: () => Navigator.pop(context, g),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null) return;
    setState(() => _goal = picked.isEmpty ? null : picked);
  }

  bool _matches(Exercise e, String q) {
    if (_category != null && e.category != _category) return false;
    if (_goal != null && !e.goals.contains(_goal)) return false;
    if (_onlyReview && !e.needsReview) return false;
    if (q.isEmpty) return true;
    return [
      e.name,
      e.bodyRegion,
      ...e.goals,
      ...e.equipment,
    ].any((s) => s.toLowerCase().contains(q));
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final q = _query.trim().toLowerCase();
    final toReview = store.exercises.where((e) => e.needsReview).length;
    if (toReview == 0) _onlyReview = false;
    final items = store.exercises.where((e) => _matches(e, q)).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            key: const Key('exercise_search'),
            decoration: const InputDecoration(
              hintText: 'Name, Region, Ziel oder Equipment',
              prefixIcon: Icon(Icons.search),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SizedBox(
            width: double.infinity,
            child: Wrap(
              spacing: 8,
              children: [
                FilterChip(
                  label: const Text('Alle'),
                  selected: _category == null,
                  onSelected: (_) => setState(() => _category = null),
                ),
                for (final c in ExerciseCategory.values)
                  FilterChip(
                    label: Text(c.label),
                    selected: _category == c,
                    onSelected: (_) => setState(() => _category = c),
                  ),
                if (toReview > 0)
                  FilterChip(
                    key: const Key('review_filter'),
                    avatar: Icon(
                      Icons.rate_review_outlined,
                      size: 18,
                      color: _onlyReview ? scheme.onSecondaryContainer : null,
                    ),
                    label: Text('Zu prüfen ($toReview)'),
                    selected: _onlyReview,
                    onSelected: (v) => setState(() => _onlyReview = v),
                  ),
                FilterChip(
                  key: const Key('goal_filter'),
                  avatar: Icon(
                    Icons.flag_outlined,
                    size: 18,
                    color: _goal == null ? null : scheme.onSecondaryContainer,
                  ),
                  label: Text(_goal ?? 'Ziel'),
                  selected: _goal != null,
                  onSelected: (_) => _pickGoal(),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: items.isEmpty
              ? const EmptyState(
                  icon: Icons.search_off,
                  title: 'Keine Übung gefunden',
                  message: 'Passe Suche oder Filter an.',
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 96),
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final e = items[i];
                    final selected = widget.selectedIds?.contains(e.id);
                    return ListTile(
                      leading: e.imageIds.isEmpty
                          ? CategoryAvatar(e.category)
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(11),
                              child: SizedBox(
                                width: 40,
                                height: 40,
                                child: StoredImage(e.imageIds.first),
                              ),
                            ),
                      title: Text(e.name),
                      subtitle: Text(
                        [
                          e.category.label,
                          if (e.bodyRegion.isNotEmpty) e.bodyRegion,
                          if (e.goals.isNotEmpty) e.goals.join(', '),
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (e.needsReview)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: TagWrap(const [
                                'Prüfen',
                              ], color: scheme.primary),
                            ),
                          if (e.videoLinks.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Icon(
                                Icons.play_circle_outline,
                                size: 20,
                                color: scheme.onSurfaceVariant,
                                semanticLabel: 'mit Video',
                              ),
                            ),
                          if (selected == null)
                            const Icon(Icons.chevron_right)
                          else
                            Icon(
                              selected
                                  ? Icons.check_circle
                                  : Icons.radio_button_unchecked,
                              color: selected ? scheme.primary : null,
                            ),
                        ],
                      ),
                      onTap: () => widget.onTap(e),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
