import 'package:material_ui/material_ui.dart';

import '../format.dart';
import '../links.dart';
import '../models.dart';
import '../store.dart';
import '../sync/backend.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/exercise_browser.dart';
import '../widgets/media_widgets.dart';
import 'account_screen.dart';
import 'athlete_screens.dart';
import 'clip_edit_screen.dart';
import 'exercise_detail_screen.dart';
import 'exercise_edit_screen.dart';
import 'session_edit_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  static const _titles = ['Trainingsplan', 'Athleten', 'Übungen', 'Clips'];

  void _push(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  void _planSession() {
    final store = StoreScope.read(context);
    if (store.athletes.isEmpty) {
      setState(() => _tab = 1);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lege zuerst einen Athleten an.')),
      );
      return;
    }
    _push(const SessionEditScreen());
  }

  Future<void> _addAthlete() async {
    final athlete = await showAthleteDialog(context);
    if (athlete != null && mounted) {
      StoreScope.read(context).upsertAthlete(athlete);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (StoreScope.of(context).isAthlete) return const _AthleteHome();
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_tab]),
        actions: const [SyncButton(), SizedBox(width: 4)],
      ),
      body: switch (_tab) {
        0 => const _PlanTab(),
        1 => const _AthletesTab(),
        2 => ExerciseBrowser(
          onTap: (e) => _push(ExerciseDetailScreen(exerciseId: e.id)),
        ),
        _ => const _ClipsTab(),
      },
      floatingActionButton: switch (_tab) {
        0 => FloatingActionButton.extended(
          onPressed: _planSession,
          icon: const Icon(Icons.add),
          label: const Text('Einheit planen'),
        ),
        1 => FloatingActionButton.extended(
          onPressed: _addAthlete,
          icon: const Icon(Icons.person_add),
          label: const Text('Athlet hinzufügen'),
        ),
        2 => FloatingActionButton.extended(
          onPressed: () => _push(const ExerciseEditScreen()),
          icon: const Icon(Icons.add),
          label: const Text('Neue Übung'),
        ),
        _ => FloatingActionButton.extended(
          onPressed: () => _push(const ClipEditScreen()),
          icon: const Icon(Icons.add_link),
          label: const Text('Clip hinzufügen'),
        ),
      },
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Plan',
          ),
          NavigationDestination(
            icon: Icon(Icons.groups_outlined),
            selectedIcon: Icon(Icons.groups),
            label: 'Athleten',
          ),
          NavigationDestination(
            icon: Icon(Icons.fitness_center_outlined),
            selectedIcon: Icon(Icons.fitness_center),
            label: 'Übungen',
          ),
          NavigationDestination(
            icon: Icon(Icons.video_library_outlined),
            selectedIcon: Icon(Icons.video_library),
            label: 'Clips',
          ),
        ],
      ),
    );
  }
}

/// Ansicht für angemeldete Athleten: nur die eigenen Einheiten.
class _AthleteHome extends StatelessWidget {
  const _AthleteHome();

  @override
  Widget build(BuildContext context) {
    final backend = BackendScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mein Training'),
        actions: const [SyncButton(), SizedBox(width: 4)],
      ),
      body: backend.linked
          ? const _PlanTab(showAthlete: false)
          : Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const EmptyState(
                    icon: Icons.link,
                    title: 'Noch mit keinem Trainer verknüpft',
                    message:
                        'Gib den Einladungscode deines Trainers ein, um '
                        'deine Einheiten zu sehen.',
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AccountScreen()),
                    ),
                    child: const Text('Einladungscode eingeben'),
                  ),
                ],
              ),
            ),
    );
  }
}

class _PlanTab extends StatefulWidget {
  const _PlanTab({this.showAthlete = true});

  /// Athletenname je Einheit anzeigen (Trainer-Sicht).
  final bool showAthlete;

  @override
  State<_PlanTab> createState() => _PlanTabState();
}

class _PlanTabState extends State<_PlanTab> {
  bool _showPast = false;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final sessions = _showPast ? store.past() : store.upcoming();

    final children = <Widget>[];
    DateTime? currentDay;
    for (final s in sessions) {
      final day = dateOnly(s.date);
      if (day != currentDay) {
        currentDay = day;
        children.add(SectionHeader(relativeDate(day)));
      }
      children.add(SessionTile(session: s, showAthlete: widget.showAthlete));
    }

    return Column(
      children: [
        const _TodayCard(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: false, label: Text('Anstehend')),
                ButtonSegment(value: true, label: Text('Vergangen')),
              ],
              selected: {_showPast},
              onSelectionChanged: (v) => setState(() => _showPast = v.first),
            ),
          ),
        ),
        Expanded(
          child: sessions.isEmpty
              ? EmptyState(
                  icon: Icons.event_available,
                  title: _showPast
                      ? 'Keine vergangenen Einheiten'
                      : 'Noch keine Einheiten geplant',
                  message: _showPast
                      ? 'Einheiten vor dem heutigen Tag erscheinen hier.'
                      : widget.showAthlete
                      ? 'Lege Athleten an und plane ihre erste Einheit.'
                      : 'Sobald dein Trainer etwas plant, erscheint es hier.',
                )
              : RefreshIndicator(
                  onRefresh: () => BackendScope.read(context).sync(),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 96),
                    children: children,
                  ),
                ),
        ),
      ],
    );
  }
}

/// Tagesübersicht: Datum, Einheiten heute, davon offen.
class _TodayCard extends StatelessWidget {
  const _TodayCard();

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final colors = AppColors.of(context);
    final now = DateTime.now();
    final today = store
        .upcoming(now: now)
        .where((s) => dateOnly(s.date) == dateOnly(now))
        .toList();
    final open = today.where((s) => !s.done).length;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      decoration: BoxDecoration(
        color: colors.hero,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'HEUTE',
                  style: TextStyle(
                    fontFamily: headingFont,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    letterSpacing: 1.4,
                    color: colors.heroAccent,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  formatDate(now),
                  style: TextStyle(
                    fontFamily: headingFont,
                    fontWeight: FontWeight.w600,
                    fontSize: 26,
                    color: colors.onHero,
                  ),
                ),
              ],
            ),
          ),
          _Stat(value: '${today.length}', label: 'Einheiten'),
          const SizedBox(width: 20),
          _Stat(value: '$open', label: 'offen', highlight: open > 0),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.value,
    required this.label,
    this.highlight = false,
  });

  final String value;
  final String label;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontFamily: headingFont,
            fontWeight: FontWeight.w700,
            fontSize: 32,
            height: 1,
            color: highlight ? colors.heroAccent : colors.onHero,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: colors.onHero.withValues(alpha: 0.72),
          ),
        ),
      ],
    );
  }
}

class _AthletesTab extends StatelessWidget {
  const _AthletesTab();

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final athletes = store.athletes;
    if (athletes.isEmpty) {
      return const EmptyState(
        icon: Icons.groups_outlined,
        title: 'Noch keine Athleten',
        message: 'Füge deine Athleten hinzu, um Einheiten für sie zu planen.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 96),
      itemCount: athletes.length,
      itemBuilder: (context, i) {
        final a = athletes[i];
        final n = store.upcoming(athleteId: a.id).length;
        return ListTile(
          leading: CircleAvatar(child: Text(initials(a.name))),
          title: Text(a.name),
          subtitle: Text(
            [
              if (a.sport.isNotEmpty) a.sport,
              '$n anstehende ${n == 1 ? 'Einheit' : 'Einheiten'}',
            ].join(' · '),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => AthleteDetailScreen(athleteId: a.id),
            ),
          ),
        );
      },
    );
  }
}

/// Sammlung gespeicherter Video-Links als Rohmaterial für Übungen.
class _ClipsTab extends StatelessWidget {
  const _ClipsTab();

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final clips = store.clips;
    if (clips.isEmpty) {
      return const EmptyState(
        icon: Icons.video_library_outlined,
        title: 'Noch keine Clips',
        message:
            'Sammle hier Links zu Reels, Shorts und Videos und leite '
            'daraus Übungen für deine Bibliothek ab.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 96),
      itemCount: clips.length,
      itemBuilder: (context, i) => _ClipTile(clip: clips[i]),
    );
  }
}

class _ClipTile extends StatelessWidget {
  const _ClipTile({required this.clip});

  final VideoClip clip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final n = StoreScope.of(context).exercisesFromClip(clip.id).length;
    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 72,
          height: 48,
          child: clip.imageIds.isNotEmpty
              ? StoredImage(clip.imageIds.first)
              : VideoThumb(clip.url, compact: true),
        ),
      ),
      title: Text(
        clip.title.isNotEmpty ? clip.title : hostOf(clip.url),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${platformOf(clip.url).label} · '
        '${n == 0 ? 'noch keine Übung' : '$n ${n == 1 ? 'Übung' : 'Übungen'}'}',
      ),
      trailing: n == 0
          ? TagWrap(const ['Offen'], color: scheme.primary)
          : const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => ClipEditScreen(clip: clip))),
    );
  }
}
