import 'package:flutter/material.dart';

import '../fipe.dart';
import '../format.dart';
import 'widgets.dart';

Future<FipeResult?> showFipeDialog(BuildContext context) {
  final wide = isWide(context);
  if (wide) {
    return showDialog<FipeResult>(
      context: context,
      builder: (_) => const Dialog(
        child: SizedBox(width: 560, height: 640, child: _FipeFlow()),
      ),
    );
  }
  return Navigator.of(context).push<FipeResult>(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => const _FipeFlow(),
  ));
}

class _FipeFlow extends StatefulWidget {
  const _FipeFlow();

  @override
  State<_FipeFlow> createState() => _FipeFlowState();
}

class _FipeFlowState extends State<_FipeFlow> {
  FipeKind _kind = FipeKind.carros;
  FipeOption? _brand, _model, _year;
  List<FipeOption> _options = [];
  FipeResult? _result;
  bool _loading = false;
  String? _error;
  String _filter = '';
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadStep();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  int get _step => _brand == null
      ? 0
      : _model == null
          ? 1
          : _year == null
              ? 2
              : 3;

  Future<void> _loadStep() async {
    setState(() {
      _loading = true;
      _error = null;
      _filter = '';
      _search.clear();
    });
    try {
      switch (_step) {
        case 0:
          _options = await fipe.brands(_kind);
        case 1:
          _options = await fipe.models(_kind, _brand!.code);
        case 2:
          _options = await fipe.years(_kind, _brand!.code, _model!.code);
        default:
          _result =
              await fipe.price(_kind, _brand!.code, _model!.code, _year!.code);
      }
    } catch (e) {
      _error =
          'Não foi possível consultar a FIPE agora. Verifique a internet e tente de novo.\n($e)';
    }
    if (mounted) setState(() => _loading = false);
  }

  void _back() {
    setState(() {
      _result = null;
      if (_year != null) {
        _year = null;
      } else if (_model != null) {
        _model = null;
      } else if (_brand != null) {
        _brand = null;
      }
    });
    _loadStep();
  }

  @override
  Widget build(BuildContext context) {
    final titles = ['Marca', 'Modelo', 'Ano / combustível', 'Resultado'];
    final filtered = _options
        .where((o) => o.name.toLowerCase().contains(_filter.toLowerCase()))
        .toList();
    return Scaffold(
      appBar: AppBar(
        leading: _step == 0
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context))
            : IconButton(icon: const Icon(Icons.arrow_back), onPressed: _back),
        title: Text('Tabela FIPE · ${titles[_step]}'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_step == 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: SegmentedButton<FipeKind>(
                segments: [
                  for (final k in FipeKind.values)
                    ButtonSegment(value: k, label: Text(k.label)),
                ],
                selected: {_kind},
                onSelectionChanged: (s) {
                  _kind = s.first;
                  _loadStep();
                },
              ),
            ),
          if (_step > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(
                [_brand?.name, _model?.name, _year?.name]
                    .whereType<String>()
                    .join(' › '),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (_step < 3)
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _search,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'Filtrar ${titles[_step].toLowerCase()}…',
                ),
                onChanged: (v) => setState(() => _filter = v),
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? EmptyState(
                        icon: Icons.wifi_off,
                        text: _error!,
                        action: FilledButton(
                            onPressed: _loadStep,
                            child: const Text('Tentar de novo')),
                      )
                    : _step == 3
                        ? _resultView()
                        : ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (context, i) {
                              final o = filtered[i];
                              return ListTile(
                                title: Text(o.name),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () {
                                  setState(() {
                                    if (_step == 0) {
                                      _brand = o;
                                    } else if (_step == 1) {
                                      _model = o;
                                    } else {
                                      _year = o;
                                    }
                                  });
                                  _loadStep();
                                },
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }

  Widget _resultView() {
    final r = _result;
    if (r == null) return const SizedBox();
    final t = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(r.model, style: t.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text('${r.brand} · ${r.year} · ${r.fuel}'),
        const SizedBox(height: 16),
        Text(money(r.value),
            style: t.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w800, color: t.colorScheme.primary)),
        Text('Código ${r.fipeCode} · referência ${r.reference}',
            style: t.textTheme.bodySmall),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, r),
          icon: const Icon(Icons.check),
          label: const Text('Usar estes dados no veículo'),
        ),
      ],
    );
  }
}
