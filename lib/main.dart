import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'modules.dart';
import 'store.dart';
import 'theme.dart';
import 'ui/shell.dart';

/// Mensagens globais (ex.: módulo desativado / sem permissão).
final messengerKey = GlobalKey<ScaffoldMessengerState>();

void _showDenied(AccessDenied e) {
  messengerKey.currentState
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(e.message)));
}

/// Qualquer tentativa barrada pela checagem central vira um aviso, nunca
/// um erro: vale para botões, atalhos e chamadas em segundo plano.
void installAccessGuard() {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    final e = details.exception;
    if (e is AccessDenied) return _showDenied(e);
    previous?.call(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    if (error is AccessDenied) {
      _showDenied(error);
      return true;
    }
    return false;
  };
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  installAccessGuard();
  final store = await AppStore.open();
  runApp(FunilarApp(store: store));
}

class FunilarApp extends StatefulWidget {
  const FunilarApp({super.key, required this.store});
  final AppStore store;

  @override
  State<FunilarApp> createState() => _FunilarAppState();
}

class _FunilarAppState extends State<FunilarApp>
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
            title: 'Funilar',
            scaffoldMessengerKey: messengerKey,
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
