import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'demo.dart';
import 'screens/home_screen.dart';
import 'store.dart';
import 'sync/backend.dart';
import 'theme.dart';

/// Server-Vorgabe aus dem Build, damit Athleten nichts eintippen müssen:
/// flutter build apk --dart-define=SUPABASE_URL=https://… \
///                   --dart-define=SUPABASE_ANON_KEY=…
const _defaultUrl = String.fromEnvironment('SUPABASE_URL');
const _defaultKey = String.fromEnvironment('SUPABASE_ANON_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (demoMode) {
    runApp(const DemoApp());
    return;
  }
  final store = AppStore();
  await store.load();
  final backend = Backend(store);
  try {
    // Ohne Netz nicht am Start hängen bleiben; die App läuft lokal weiter.
    await backend
        .init(defaultUrl: _defaultUrl, defaultKey: _defaultKey)
        .timeout(const Duration(seconds: 4));
  } catch (_) {}
  backend.startAutoSync();
  runApp(CoachApp(store: store, backend: backend));
}

class CoachApp extends StatefulWidget {
  const CoachApp({super.key, required this.store, this.backend, this.banner});

  final AppStore store;

  /// Ohne Angabe läuft die App rein lokal (z. B. in Tests).
  final Backend? backend;

  /// Leiste über der App (Demo-Modus).
  final Widget? banner;

  @override
  State<CoachApp> createState() => _CoachAppState();
}

class _CoachAppState extends State<CoachApp> with WidgetsBindingObserver {
  late final Backend _backend = widget.backend ?? Backend(widget.store);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (widget.backend == null) _backend.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Beim Zurückkehren in die App den neuesten Stand holen.
    if (state == AppLifecycleState.resumed) unawaited(_backend.sync());
  }

  @override
  Widget build(BuildContext context) {
    return StoreScope(
      store: widget.store,
      child: BackendScope(
        backend: _backend,
        child: MaterialApp(
          title: 'CoachPlan',
          debugShowCheckedModeBanner: false,
          locale: const Locale('de'),
          supportedLocales: const [Locale('de')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          builder: widget.banner == null
              ? null
              : (context, child) => Column(
                  children: [
                    widget.banner!,
                    Expanded(
                      child: MediaQuery.removePadding(
                        context: context,
                        removeTop: true,
                        child: child!,
                      ),
                    ),
                  ],
                ),
          home: const HomeScreen(),
        ),
      ),
    );
  }
}
