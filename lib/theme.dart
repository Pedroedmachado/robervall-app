import 'package:flutter/material.dart';

import 'models.dart';
import 'store.dart';

const brandSeed = Color(0xFF0E5A73);
const brandAccent = Color(0xFFF2A007);

ThemeData buildTheme(Brightness b) {
  final scheme = ColorScheme.fromSeed(
    seedColor: brandSeed,
    brightness: b,
    secondary: brandAccent,
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: b,
    visualDensity: VisualDensity.standard,
  );
  return base.copyWith(
    scaffoldBackgroundColor:
        b == Brightness.light ? const Color(0xFFF4F6F8) : scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor:
          b == Brightness.light ? Colors.white : scheme.surfaceContainer,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 1,
      centerTitle: false,
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      isDense: true,
      filled: true,
      fillColor: b == Brightness.light
          ? Colors.white
          : scheme.surfaceContainerHighest.withValues(alpha: 0.4),
    ),
  );
}

Color statusColor(ClaimStatus s) {
  switch (s) {
    case ClaimStatus.aberto:
      return const Color(0xFF607D8B);
    case ClaimStatus.vistoria:
      return const Color(0xFF7E57C2);
    case ClaimStatus.orcamento:
      return const Color(0xFF1E88E5);
    case ClaimStatus.aguardandoAprovacao:
      return const Color(0xFFF2A007);
    case ClaimStatus.aprovado:
      return const Color(0xFF00897B);
    case ClaimStatus.emReparo:
      return const Color(0xFF3949AB);
    case ClaimStatus.concluido:
      return const Color(0xFF43A047);
    case ClaimStatus.entregue:
      return const Color(0xFF2E7D32);
    case ClaimStatus.cancelado:
      return const Color(0xFFE53935);
  }
}

Color severityColor(int s) {
  switch (s) {
    case 1:
      return const Color(0xFFFBC02D);
    case 2:
      return const Color(0xFFFB8C00);
    default:
      return const Color(0xFFE53935);
  }
}

/// Dá acesso ao [AppStore] em qualquer widget e reconstrói quando ele muda.
class StoreScope extends InheritedNotifier<AppStore> {
  const StoreScope({super.key, required AppStore store, required super.child})
      : super(notifier: store);

  static AppStore of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StoreScope>()!.notifier!;

  static AppStore read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<StoreScope>()!.notifier!;
}
