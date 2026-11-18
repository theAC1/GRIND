import 'package:material_ui/material_ui.dart';

import '../format.dart';
import '../models.dart';
import '../screens/session_detail_screen.dart';
import '../store.dart';
import '../theme.dart';

class CategoryAvatar extends StatelessWidget {
  const CategoryAvatar(this.category, {super.key, this.size = 40});

  final ExerciseCategory category;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.of(context).category(category);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: Icon(category.icon, size: size * 0.5, color: color),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Abschnittstitel in Versalien.
class SectionHeader extends StatelessWidget {
  const SectionHeader(
    this.text, {
    super.key,
    this.padding = const EdgeInsets.fromLTRB(16, 20, 16, 8),
  });

  final String text;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding,
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontFamily: headingFont,
          fontWeight: FontWeight.w700,
          fontSize: 15,
          letterSpacing: 1.1,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Schlagworte als kompakte, nicht klickbare Marken.
class TagWrap extends StatelessWidget {
  const TagWrap(this.tags, {super.key, this.color});

  final List<String> tags;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = color ?? scheme.onSurfaceVariant;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final t in tags)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: c.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              t,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: c,
              ),
            ),
          ),
      ],
    );
  }
}

/// Listeneintrag für eine Einheit; öffnet die Detailansicht.
/// Der farbige Streifen zeigt die überwiegende Trainingsart.
class SessionTile extends StatelessWidget {
  const SessionTile({
    super.key,
    required this.session,
    this.showAthlete = true,
    this.showDate = false,
  });

  final TrainingSession session;
  final bool showAthlete;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final colors = AppColors.of(context);
    final athlete = store.athleteById(session.athleteId);
    final n = session.entries.length;
    final category = session.dominantCategory;
    final subtitle = [
      if (showDate) formatDate(session.date),
      if (showAthlete) athlete?.name ?? 'Unbekannter Athlet',
      '$n ${n == 1 ? 'Übung' : 'Übungen'}',
    ].join(' · ');

    final Widget trailing;
    if (session.done) {
      trailing = Icon(Icons.check_circle, color: colors.success);
    } else if (session.started) {
      trailing = Text(
        '${session.doneSets}/${session.totalSets}',
        style: TextStyle(
          fontFamily: headingFont,
          fontWeight: FontWeight.w700,
          fontSize: 20,
          color: scheme.primary,
        ),
      );
    } else {
      trailing = const Icon(Icons.chevron_right);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                width: 5,
                color: category == null
                    ? scheme.outlineVariant
                    : colors.category(category),
              ),
            ),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.only(left: 14, right: 16),
            title: Text(
              session.title,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(subtitle),
            trailing: trailing,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => SessionDetailScreen(sessionId: session.id),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<bool> confirmDelete(
  BuildContext context, {
  required String title,
  required String message,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Löschen'),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Baukasten-Auswahl: Schlagworte an-/abwählen und eigene ergänzen.
class TagPicker extends StatelessWidget {
  const TagPicker({
    super.key,
    required this.label,
    required this.vocabulary,
    required this.selected,
    required this.onChanged,
  });

  final String label;
  final List<String> vocabulary;
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;

  Future<void> _addCustom(BuildContext context) async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$label ergänzen'),
        content: TextField(
          key: const Key('custom_tag'),
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Eigenes Schlagwort'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Hinzufügen'),
          ),
        ],
      ),
    );
    final tag = value?.trim() ?? '';
    if (tag.isEmpty || selected.contains(tag)) return;
    onChanged([...selected, tag]);
  }

  @override
  Widget build(BuildContext context) {
    final all = [
      ...vocabulary,
      for (final s in selected)
        if (!vocabulary.contains(s)) s,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(label, padding: const EdgeInsets.only(bottom: 8)),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final t in all)
              FilterChip(
                label: Text(t),
                selected: selected.contains(t),
                onSelected: (on) => onChanged(
                  on
                      ? [...selected, t]
                      : selected.where((s) => s != t).toList(),
                ),
              ),
            ActionChip(
              avatar: const Icon(Icons.add, size: 18),
              label: const Text('Eigenes'),
              onPressed: () => _addCustom(context),
            ),
          ],
        ),
      ],
    );
  }
}
