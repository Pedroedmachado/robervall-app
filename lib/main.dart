import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'store.dart';
import 'theme.dart';
import 'ui/shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await AppStore.open();
  runApp(RobervallApp(store: store));
}

class RobervallApp extends StatefulWidget {
  const RobervallApp({super.key, required this.store});
  final AppStore store;

  @override
  State<RobervallApp> createState() => _RobervallAppState();
}

class _RobervallAppState extends State<RobervallApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      widget.store.flush();
    }
  }

  @override
  Widget build(BuildContext context) {
    return StoreScope(
      store: widget.store,
      child: ListenableBuilder(
        listenable: widget.store,
        builder: (context, _) {
          final mode = switch (widget.store.settings.themeMode) {
            'light' => ThemeMode.light,
            'dark' => ThemeMode.dark,
            _ => ThemeMode.system,
          };
          return MaterialApp(
            title: 'Robervall',
            debugShowCheckedModeBanner: false,
            theme: buildTheme(Brightness.light),
            darkTheme: buildTheme(Brightness.dark),
            themeMode: mode,
            locale: const Locale('pt', 'BR'),
            supportedLocales: const [Locale('pt', 'BR')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: const AppShell(),
          );
        },
      ),
    );
  }
}
