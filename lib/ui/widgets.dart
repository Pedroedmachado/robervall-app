import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../format.dart';
import '../models.dart';
import '../theme.dart';

bool isWide(BuildContext context) => MediaQuery.sizeOf(context).width >= 900;

class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key, this.dense = false});
  final ClaimStatus status;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final c = statusColor(status);
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: dense ? 8 : 10, vertical: dense ? 2 : 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: 0.5)),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: c,
          fontWeight: FontWeight.w600,
          fontSize: dense ? 11 : 12,
        ),
      ),
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    required this.children,
    this.icon,
    this.trailing,
  });
  final String title;
  final IconData? icon;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: t.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 20, color: t.colorScheme.primary),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(title,
                      style: t.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// Grade responsiva: 1 coluna no celular, 2 ou 3 em telas largas.
class FieldGrid extends StatelessWidget {
  const FieldGrid({super.key, required this.children, this.maxColumns = 3});
  final List<Widget> children;
  final int maxColumns;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, cons) {
      var cols = (cons.maxWidth / 260).floor().clamp(1, maxColumns);
      const gap = 12.0;
      final w = (cons.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [for (final c in children) SizedBox(width: w, child: c)],
      );
    });
  }
}

/// Campo de texto ligado a um valor do modelo.
class BoundField extends StatefulWidget {
  const BoundField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.keyboard,
    this.maxLines = 1,
    this.hint,
    this.prefixIcon,
    this.formatters,
    this.capitalization = TextCapitalization.sentences,
    this.suggestions = const [],
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final TextInputType? keyboard;
  final int maxLines;
  final String? hint;
  final IconData? prefixIcon;
  final List<TextInputFormatter>? formatters;
  final TextCapitalization capitalization;
  final List<String> suggestions;

  @override
  State<BoundField> createState() => _BoundFieldState();
}

class _BoundFieldState extends State<BoundField> {
  late final TextEditingController _c =
      TextEditingController(text: widget.value);
  final _focus = FocusNode();

  @override
  void didUpdateWidget(covariant BoundField old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && widget.value != _c.text) {
      _c.text = widget.value;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  InputDecoration _decoration() => InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        prefixIcon: widget.prefixIcon == null
            ? null
            : Icon(widget.prefixIcon, size: 20),
      );

  @override
  Widget build(BuildContext context) {
    if (widget.suggestions.isEmpty) {
      return TextField(
        controller: _c,
        focusNode: _focus,
        keyboardType: widget.keyboard,
        maxLines: widget.maxLines,
        minLines: 1,
        inputFormatters: widget.formatters,
        textCapitalization: widget.capitalization,
        decoration: _decoration(),
        onChanged: widget.onChanged,
      );
    }
    return RawAutocomplete<String>(
      textEditingController: _c,
      focusNode: _focus,
      optionsBuilder: (v) {
        final q = v.text.trim().toLowerCase();
        if (q.isEmpty) return const Iterable<String>.empty();
        return widget.suggestions
            .where((s) => s.toLowerCase().contains(q) && s.toLowerCase() != q)
            .take(8);
      },
      onSelected: widget.onChanged,
      fieldViewBuilder: (context, controller, focus, onSubmit) => TextField(
        controller: controller,
        focusNode: focus,
        keyboardType: widget.keyboard,
        textCapitalization: widget.capitalization,
        inputFormatters: widget.formatters,
        decoration: _decoration(),
        onChanged: widget.onChanged,
      ),
      optionsViewBuilder: (context, onSelected, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(10),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240, maxWidth: 360),
            child: ListView(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              children: [
                for (final o in options)
                  ListTile(dense: true, title: Text(o), onTap: () => onSelected(o)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Campo numérico (aceita vírgula).
class NumField extends StatelessWidget {
  const NumField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.prefix,
    this.suffix,
  });
  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final String? prefix;
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    return _NumFieldInner(
      label: label,
      value: value,
      onChanged: onChanged,
      prefix: prefix,
      suffix: suffix,
    );
  }
}

class _NumFieldInner extends StatefulWidget {
  const _NumFieldInner({
    required this.label,
    required this.value,
    required this.onChanged,
    this.prefix,
    this.suffix,
  });
  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final String? prefix;
  final String? suffix;

  @override
  State<_NumFieldInner> createState() => _NumFieldInnerState();
}

class _NumFieldInnerState extends State<_NumFieldInner> {
  late final TextEditingController _c =
      TextEditingController(text: numField(widget.value));
  final _focus = FocusNode();

  @override
  void didUpdateWidget(covariant _NumFieldInner old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && parseNum(_c.text) != widget.value) {
      _c.text = numField(widget.value);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _c,
      focusNode: _focus,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
      decoration: InputDecoration(
        labelText: widget.label,
        prefixText: widget.prefix == null ? null : '${widget.prefix} ',
        suffixText: widget.suffix,
      ),
      onChanged: (t) => widget.onChanged(parseNum(t)),
    );
  }
}

/// Seletor de valores de enum (ou qualquer lista) em menu.
class Picker<T> extends StatelessWidget {
  const Picker({
    super.key,
    required this.label,
    required this.value,
    required this.values,
    required this.labelOf,
    required this.onChanged,
  });
  final String label;
  final T value;
  final List<T> values;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownMenu<T>(
      key: ValueKey(value),
      initialSelection: value,
      label: Text(label),
      expandedInsets: EdgeInsets.zero,
      requestFocusOnTap: false,
      dropdownMenuEntries: [
        for (final v in values) DropdownMenuEntry<T>(value: v, label: labelOf(v)),
      ],
      onSelected: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}

class DateField extends StatelessWidget {
  const DateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () async {
        final now = DateTime.now();
        final d = await showDatePicker(
          context: context,
          initialDate: value ?? now,
          firstDate: DateTime(now.year - 10),
          lastDate: DateTime(now.year + 5),
        );
        if (d != null) onChanged(d);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.event, size: 20),
          suffixIcon: value == null
              ? null
              : IconButton(
                  tooltip: 'Limpar',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => onChanged(null),
                ),
        ),
        child: Text(value == null ? 'Selecionar' : date(value)),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState(
      {super.key, required this.icon, required this.text, this.action});
  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 56, color: t.colorScheme.outline),
        const SizedBox(height: 12),
        Text(text,
            textAlign: TextAlign.center,
            style: t.textTheme.bodyLarge
                ?.copyWith(color: t.colorScheme.onSurfaceVariant)),
        if (action != null) ...[const SizedBox(height: 16), action!],
      ],
    );
    return LayoutBuilder(builder: (context, cons) {
      // dentro de listas (altura infinita) não pode rolar de novo
      if (!cons.maxHeight.isFinite) {
        return Padding(padding: const EdgeInsets.all(24), child: content);
      }
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: content,
        ),
      );
    });
  }
}

Future<bool> confirm(BuildContext context, String title, String message,
    {String ok = 'Confirmar', bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar')),
        FilledButton(
          style: danger
              ? FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error)
              : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return r == true;
}

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 3),
      showCloseIcon: true,
    ));
}

/// Aviso com "Desfazer" que some sozinho em 5 s e tem X para fechar.
/// (Com ação, o Flutter manteria o aviso aberto até alguém tocar nele.)
void showUndo(BuildContext context, String msg, VoidCallback onUndo) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  var open = true;
  final ctl = messenger.showSnackBar(SnackBar(
    content: Text(msg),
    behavior: SnackBarBehavior.floating,
    duration: const Duration(seconds: 5),
    showCloseIcon: true,
    action: SnackBarAction(label: 'Desfazer', onPressed: onUndo),
  ));
  ctl.closed.whenComplete(() => open = false);
  Timer(const Duration(seconds: 5), () {
    if (open) messenger.hideCurrentSnackBar();
  });
}

class KeyValue extends StatelessWidget {
  const KeyValue(this.k, this.v, {super.key, this.bold = false, this.color});
  final String k;
  final String v;
  final bool bold;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
      fontSize: bold ? 16 : 14,
      color: color,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(k, style: style)),
          Text(v, style: style),
        ],
      ),
    );
  }
}

/// Diálogo de formulário sem IntrinsicWidth (permite campos com LayoutBuilder).
Future<T?> showFormDialog<T>({
  required BuildContext context,
  required String title,
  required Widget Function(BuildContext ctx, StateSetter setS) body,
  required T? Function() onSave,
}) {
  return showDialog<T>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
                child: Text(title, style: Theme.of(ctx).textTheme.titleLarge),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: body(ctx, setS),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 16, 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancelar')),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () {
                        final r = onSave();
                        if (r != null) Navigator.pop(ctx, r);
                      },
                      child: const Text('Salvar'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Ponto de origem do menu de compartilhar (obrigatório no iPad).
Rect shareOrigin(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  return Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 3), width: 2, height: 2);
}
