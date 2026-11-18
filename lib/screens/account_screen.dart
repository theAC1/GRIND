import 'package:material_ui/material_ui.dart';

import '../store.dart';
import '../sync/backend.dart';
import '../theme.dart';
import '../widgets/common.dart';

String _two(int n) => n.toString().padLeft(2, '0');
String _clock(DateTime t) => '${_two(t.hour)}:${_two(t.minute)} Uhr';

/// Konto & Sync: Server verbinden, anmelden/registrieren, Abgleich-Status,
/// als Athlet den Einladungscode einlösen.
class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final backend = BackendScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Konto & Sync')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          if (!backend.configured)
            const _ServerForm()
          else if (!backend.signedIn)
            const _AuthForm()
          else
            const _SignedIn(),
        ],
      ),
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.message);

  final String? message;

  @override
  Widget build(BuildContext context) {
    if (message == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(
        message!,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    );
  }
}

// ---- Server verbinden -----------------------------------------------------

class _ServerForm extends StatefulWidget {
  const _ServerForm();

  @override
  State<_ServerForm> createState() => _ServerFormState();
}

class _ServerFormState extends State<_ServerForm> {
  final _url = TextEditingController();
  final _key = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await BackendScope.read(context).configure(_url.text, _key.text);
    } on BackendException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Server verbinden', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(
          'Ohne Server bleiben alle Daten nur auf diesem Gerät. Mit deinem '
          'Supabase-Server werden sie gesichert, auf mehreren Geräten '
          'abgeglichen und Athleten können ihre Einheiten in der eigenen '
          'App abhaken.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        TextField(
          key: const Key('server_url'),
          controller: _url,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Server-Adresse',
            hintText: 'https://coachplan.example.org',
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('server_key'),
          controller: _key,
          autocorrect: false,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'API-Schlüssel (anon key)',
            alignLabelWithHint: true,
          ),
        ),
        _ErrorText(_error),
        const SizedBox(height: 20),
        FilledButton(
          key: const Key('server_connect'),
          onPressed: _busy ? null : _connect,
          child: Text(_busy ? 'Prüfe Verbindung …' : 'Verbinden'),
        ),
      ],
    );
  }
}

// ---- Anmelden / Registrieren ----------------------------------------------

class _AuthForm extends StatefulWidget {
  const _AuthForm();

  @override
  State<_AuthForm> createState() => _AuthFormState();
}

class _AuthFormState extends State<_AuthForm> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  bool _register = false;
  String _role = 'coach';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final backend = BackendScope.read(context);
    if (_email.text.trim().isEmpty || _password.text.length < 8) {
      setState(
        () => _error =
            'Bitte E-Mail und ein Passwort mit mindestens '
            '8 Zeichen eingeben.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_register) {
        await backend.signUp(
          email: _email.text,
          password: _password.text,
          role: _role,
          name: _name.text,
        );
      } else {
        await backend.signIn(email: _email.text, password: _password.text);
      }
    } on BackendException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final backend = BackendScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: false, label: Text('Anmelden')),
            ButtonSegment(value: true, label: Text('Registrieren')),
          ],
          selected: {_register},
          onSelectionChanged: (v) => setState(() {
            _register = v.first;
            _error = null;
          }),
        ),
        const SizedBox(height: 20),
        if (_register) ...[
          Text('Ich bin', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: 'coach',
                label: Text('Trainer'),
                icon: Icon(Icons.sports),
              ),
              ButtonSegment(
                value: 'athlete',
                label: Text('Athlet'),
                icon: Icon(Icons.directions_run),
              ),
            ],
            selected: {_role},
            onSelectionChanged: (v) => setState(() => _role = v.first),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('auth_name'),
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          const SizedBox(height: 16),
        ],
        TextField(
          key: const Key('auth_email'),
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          decoration: const InputDecoration(labelText: 'E-Mail'),
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('auth_password'),
          controller: _password,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Passwort'),
          onSubmitted: (_) => _submit(),
        ),
        if (_register && _role == 'coach' && !backend.linked)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              'Die Daten, die schon auf diesem Gerät sind, werden in dein '
              'neues Konto übernommen.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        _ErrorText(_error),
        const SizedBox(height: 20),
        FilledButton(
          key: const Key('auth_submit'),
          onPressed: _busy ? null : _submit,
          child: Text(
            _busy
                ? 'Einen Moment …'
                : _register
                ? 'Konto anlegen'
                : 'Anmelden',
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Icon(
              Icons.dns_outlined,
              size: 18,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                backend.url ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ),
            TextButton(
              onPressed: _busy ? null : () => backend.disconnect(),
              child: const Text('Server ändern'),
            ),
          ],
        ),
      ],
    );
  }
}

// ---- Angemeldet -----------------------------------------------------------

class _SignedIn extends StatelessWidget {
  const _SignedIn();

  @override
  Widget build(BuildContext context) {
    final backend = BackendScope.of(context);
    final store = StoreScope.of(context);
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final athlete = backend.role == 'athlete';
    final pending = store.sync.pendingCount;

    final (IconData icon, Color color, String text) = switch (backend.status) {
      SyncStatus.syncing => (
        Icons.sync,
        theme.colorScheme.primary,
        'Abgleich läuft …',
      ),
      SyncStatus.error => (
        Icons.cloud_off,
        theme.colorScheme.error,
        backend.lastError ?? 'Abgleich fehlgeschlagen.',
      ),
      _ => (
        Icons.cloud_done,
        colors.success,
        backend.lastSync == null
            ? 'Verbunden.'
            : 'Zuletzt abgeglichen um ${_clock(backend.lastSync!)}.',
      ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: ListTile(
            leading: CircleAvatar(
              child: Icon(athlete ? Icons.directions_run : Icons.sports),
            ),
            title: Text(backend.email ?? ''),
            subtitle: Text(athlete ? 'Athlet' : 'Trainer'),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, color: color),
                    const SizedBox(width: 12),
                    Expanded(child: Text(text)),
                  ],
                ),
                if (pending > 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    '$pending ${pending == 1 ? 'Änderung wartet' : 'Änderungen warten'} '
                    'auf den Upload.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  key: const Key('sync_now'),
                  onPressed: backend.status == SyncStatus.syncing
                      ? null
                      : () => backend.sync(),
                  icon: const Icon(Icons.sync),
                  label: const Text('Jetzt abgleichen'),
                ),
              ],
            ),
          ),
        ),
        if (athlete && !backend.linked) ...[
          const SizedBox(height: 12),
          const _RedeemCard(),
        ],
        if (athlete && backend.linked) ...[
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: Icon(Icons.link, color: colors.success),
              title: const Text('Mit deinem Trainer verknüpft'),
              subtitle: const Text(
                'Deine Einheiten erscheinen automatisch unter „Mein Training“.',
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),
        Row(
          children: [
            Icon(
              Icons.dns_outlined,
              size: 18,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                backend.url ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          key: const Key('sign_out'),
          onPressed: () async {
            if (pending > 0 && !athlete) {
              final ok = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Abmelden?'),
                  content: Text(
                    '$pending Änderungen sind noch nicht hochgeladen. Sie '
                    'bleiben auf diesem Gerät und werden beim nächsten '
                    'Anmelden übertragen.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Abbrechen'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Abmelden'),
                    ),
                  ],
                ),
              );
              if (ok != true) return;
            }
            await backend.signOut();
          },
          child: const Text('Abmelden'),
        ),
      ],
    );
  }
}

class _RedeemCard extends StatefulWidget {
  const _RedeemCard();

  @override
  State<_RedeemCard> createState() => _RedeemCardState();
}

class _RedeemCardState extends State<_RedeemCard> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _redeem() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await BackendScope.read(context).redeemInvite(_code.text);
    } on BackendException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      // Eigene Semantik je Element, damit das Code-Feld für Screenreader
      // nicht mit dem Erklärtext verschmilzt.
      semanticContainer: false,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionHeader(
              'Einladungscode',
              padding: EdgeInsets.only(bottom: 8),
            ),
            const Text(
              'Gib den Code ein, den du von deinem Trainer bekommen hast. '
              'Danach siehst du deine Einheiten.',
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('invite_code'),
              controller: _code,
              textCapitalization: TextCapitalization.characters,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'Code'),
              onSubmitted: (_) => _redeem(),
            ),
            _ErrorText(_error),
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('invite_redeem'),
              onPressed: _busy ? null : _redeem,
              child: Text(_busy ? 'Prüfe …' : 'Einlösen'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Wolken-Symbol für die Kopfleiste; zeigt den Abgleich-Zustand und führt
/// zum Konto-Bildschirm.
class SyncButton extends StatelessWidget {
  const SyncButton({super.key});

  @override
  Widget build(BuildContext context) {
    final backend = BackendScope.of(context);
    final pending = StoreScope.of(context).sync.pendingCount;
    final (IconData icon, String tip) = !backend.signedIn
        ? (Icons.cloud_off_outlined, 'Konto & Sync · nur lokal')
        : switch (backend.status) {
            SyncStatus.syncing => (
              Icons.cloud_sync_outlined,
              'Konto & Sync · Abgleich läuft',
            ),
            SyncStatus.error => (
              Icons.cloud_off,
              'Konto & Sync · Abgleich fehlgeschlagen',
            ),
            _ =>
              pending > 0
                  ? (
                      Icons.cloud_upload_outlined,
                      'Konto & Sync · Änderungen warten',
                    )
                  : (Icons.cloud_done_outlined, 'Konto & Sync · abgeglichen'),
          };
    return IconButton(
      key: const Key('account_button'),
      tooltip: tip,
      icon: Icon(
        icon,
        color: backend.signedIn && backend.status == SyncStatus.error
            ? AppPalette.tartanBright
            : null,
      ),
      onPressed: () =>
          Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const AccountScreen())),
    );
  }
}
