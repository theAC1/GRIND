import 'package:material_ui/material_ui.dart';

import '../models.dart';

import 'package:flutter/services.dart';

import '../format.dart';
import '../store.dart';
import '../sync/backend.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'session_edit_screen.dart';

String initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
  if (parts.isEmpty) return '?';
  return parts.take(2).map((p) => p.substring(0, 1).toUpperCase()).join();
}

/// Dialog zum Anlegen/Bearbeiten. Liefert den Athleten oder `null` bei Abbruch.
Future<Athlete?> showAthleteDialog(BuildContext context, {Athlete? athlete}) {
  return showDialog<Athlete>(
    context: context,
    builder: (_) => _AthleteDialog(athlete: athlete),
  );
}

class _AthleteDialog extends StatefulWidget {
  const _AthleteDialog({this.athlete});

  final Athlete? athlete;

  @override
  State<_AthleteDialog> createState() => _AthleteDialogState();
}

class _AthleteDialogState extends State<_AthleteDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.athlete?.name);
  late final _sport = TextEditingController(text: widget.athlete?.sport);
  late final _notes = TextEditingController(text: widget.athlete?.notes);

  @override
  void dispose() {
    _name.dispose();
    _sport.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      Athlete(
        id: widget.athlete?.id ?? newId(),
        name: _name.text.trim(),
        sport: _sport.text.trim(),
        notes: _notes.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.athlete == null ? 'Athlet hinzufügen' : 'Athlet bearbeiten',
      ),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const Key('athlete_name'),
                controller: _name,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Bitte einen Namen eingeben'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _sport,
                decoration: const InputDecoration(
                  labelText: 'Sportart / Disziplin',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notes,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Notizen (z. B. Verletzungen, Ziele)',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton(onPressed: _save, child: const Text('Speichern')),
      ],
    );
  }
}

class AthleteDetailScreen extends StatelessWidget {
  const AthleteDetailScreen({super.key, required this.athleteId});

  final String athleteId;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final athlete = store.athleteById(athleteId);
    if (athlete == null) {
      // Wurde gerade gelöscht; die Route wird im selben Zug geschlossen.
      return const Scaffold();
    }
    final theme = Theme.of(context);
    final upcoming = store.upcoming(athleteId: athleteId);
    final past = store.past(athleteId: athleteId);

    return Scaffold(
      appBar: AppBar(
        title: Text(athlete.name),
        actions: [
          IconButton(
            tooltip: 'Bearbeiten',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              final updated = await showAthleteDialog(
                context,
                athlete: athlete,
              );
              if (updated != null) store.upsertAthlete(updated);
            },
          ),
          IconButton(
            tooltip: 'Löschen',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              final total = upcoming.length + past.length;
              final ok = await confirmDelete(
                context,
                title: 'Athlet löschen?',
                message: total == 0
                    ? '${athlete.name} wird entfernt.'
                    : '${athlete.name} und $total geplante/vergangene '
                          '${total == 1 ? 'Einheit' : 'Einheiten'} werden '
                          'endgültig entfernt.',
              );
              if (ok && context.mounted) {
                Navigator.pop(context);
                store.deleteAthlete(athleteId);
              }
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Einheit planen'),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SessionEditScreen(athleteId: athleteId),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          if (athlete.sport.isNotEmpty || athlete.notes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (athlete.sport.isNotEmpty)
                        Text(athlete.sport, style: theme.textTheme.titleSmall),
                      if (athlete.sport.isNotEmpty && athlete.notes.isNotEmpty)
                        const SizedBox(height: 6),
                      if (athlete.notes.isNotEmpty) Text(athlete.notes),
                    ],
                  ),
                ),
              ),
            ),
          if (BackendScope.of(context).signedIn &&
              BackendScope.of(context).role == 'coach')
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _AccessCard(athleteId: athleteId),
            ),
          if (upcoming.isEmpty && past.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 48),
              child: EmptyState(
                icon: Icons.event_available,
                title: 'Noch keine Einheiten',
                message: 'Plane die erste Einheit für diesen Athleten.',
              ),
            ),
          if (upcoming.isNotEmpty) ...[
            const SectionHeader('Anstehend'),
            for (final s in upcoming)
              SessionTile(session: s, showAthlete: false, showDate: true),
          ],
          if (past.isNotEmpty) ...[
            const SectionHeader('Vergangen'),
            for (final s in past)
              SessionTile(session: s, showAthlete: false, showDate: true),
          ],
        ],
      ),
    );
  }
}

/// App-Zugang des Athleten: Einladungscode erzeugen, Status, entziehen.
class _AccessCard extends StatefulWidget {
  const _AccessCard({required this.athleteId});

  final String athleteId;

  @override
  State<_AccessCard> createState() => _AccessCardState();
}

class _AccessCardState extends State<_AccessCard> {
  AthleteAccess? _access;
  String? _error;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _run(Future<void> Function(Backend b) action) async {
    final backend = BackendScope.read(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action(backend);
      final access = await backend.athleteAccess(widget.athleteId);
      if (mounted) setState(() => _access = access);
    } on BackendException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load() => _run((_) async {});

  Future<void> _createCode() =>
      _run((b) async => b.createInvite(widget.athleteId));

  Future<void> _unlink() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Zugang entziehen?'),
        content: const Text(
          'Der Athlet sieht seine Einheiten danach nicht mehr in der App. '
          'Die Einheiten und Protokolle bleiben bei dir erhalten.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Entziehen'),
          ),
        ],
      ),
    );
    if (ok == true) await _run((b) => b.unlinkAthlete(widget.athleteId));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final access = _access;

    final List<Widget> body;
    if (access == null) {
      body = [
        if (_error != null)
          Text(_error!, style: TextStyle(color: theme.colorScheme.error))
        else
          const Text('Lade Status …'),
        if (_error != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _busy ? null : _load,
              child: const Text('Erneut versuchen'),
            ),
          ),
      ];
    } else if (access.linked) {
      body = [
        Row(
          children: [
            Icon(Icons.check_circle, color: colors.success, size: 20),
            const SizedBox(width: 8),
            const Expanded(child: Text('Der Athlet nutzt die App.')),
          ],
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: _busy ? null : _unlink,
            child: const Text('Zugang entziehen'),
          ),
        ),
      ];
    } else {
      body = [
        const Text(
          'Der Athlet installiert die App, registriert sich als „Athlet“ '
          'und gibt den Einladungscode ein.',
        ),
        if (access.hasValidCode) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  access.code!,
                  key: const Key('invite_code_value'),
                  style: const TextStyle(
                    fontFamily: headingFont,
                    fontWeight: FontWeight.w700,
                    fontSize: 30,
                    letterSpacing: 3,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Code kopieren',
                icon: const Icon(Icons.copy),
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  await Clipboard.setData(ClipboardData(text: access.code!));
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Code kopiert.')),
                  );
                },
              ),
            ],
          ),
          Text(
            'Gültig bis ${formatDate(access.expiresAt!)}.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
        ],
        const SizedBox(height: 12),
        FilledButton.tonal(
          key: const Key('invite_create'),
          onPressed: _busy ? null : _createCode,
          child: Text(
            access.hasValidCode
                ? 'Neuen Code erzeugen'
                : 'Einladungscode erzeugen',
          ),
        ),
      ];
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionHeader(
              'App-Zugang',
              padding: EdgeInsets.only(bottom: 8),
            ),
            ...body,
          ],
        ),
      ),
    );
  }
}
