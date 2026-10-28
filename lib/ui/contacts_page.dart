import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../theme.dart';
import 'claims_page.dart';
import 'widgets.dart';

class ContactsPage extends StatefulWidget {
  const ContactsPage({super.key});

  @override
  State<ContactsPage> createState() => _ContactsPageState();
}

class _ContactsPageState extends State<ContactsPage> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return DefaultTabController(
      length: ContactKind.values.length,
      child: Builder(builder: (context) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Cadastros'),
            bottom: TabBar(
              isScrollable: !isWide(context),
              tabAlignment:
                  isWide(context) ? TabAlignment.fill : TabAlignment.start,
              tabs: [
                for (final k in ContactKind.values)
                  Tab(text: '${k.label} (${store.contactsOf(k).length})'),
              ],
            ),
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () async {
              final idx = DefaultTabController.of(context).index;
              final ct = await _editContact(
                  context, Contact(kind: ContactKind.values[idx]));
              if (ct != null) store.upsertContact(ct);
            },
            icon: const Icon(Icons.person_add_alt),
            label: const Text('Novo'),
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Buscar por nome, telefone ou documento',
                  ),
                  onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
                ),
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    for (final k in ContactKind.values) _list(context, k),
                  ],
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _list(BuildContext context, ContactKind k) {
    final store = StoreScope.of(context);
    final list = store
        .contactsOf(k)
        .where((c) =>
            _q.isEmpty ||
            c.name.toLowerCase().contains(_q) ||
            c.phone.contains(_q) ||
            c.doc.contains(_q))
        .toList();
    if (list.isEmpty) {
      return EmptyState(
        icon: Icons.contacts_outlined,
        text: k == ContactKind.cliente
            ? 'Clientes, seguradoras e reguladores entram aqui automaticamente quando você preenche um sinistro.'
            : 'Nenhum cadastro em ${k.label.toLowerCase()}.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 96),
      itemCount: list.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final c = list[i];
        final related = store.claims.where((cl) {
          final n = c.name.trim().toLowerCase();
          switch (k) {
            case ContactKind.cliente:
              return cl.customerName.trim().toLowerCase() == n;
            case ContactKind.seguradora:
              return cl.insurerName.trim().toLowerCase() == n;
            case ContactKind.regulador:
              return cl.regulatorName.trim().toLowerCase() == n;
            case ContactKind.fornecedor:
              return cl.items
                  .any((it) => it.supplier.trim().toLowerCase() == n);
            case ContactKind.funcionario:
              return store.entries.any((e) =>
                  e.claimId == cl.id && e.contact.trim().toLowerCase() == n);
          }
        }).toList();
        return ListTile(
          leading: CircleAvatar(
              child: Text(c.name.isEmpty ? '?' : c.name[0].toUpperCase())),
          title: Text(c.name),
          subtitle: Text([
            if (c.phone.isNotEmpty) c.phone,
            if (c.email.isNotEmpty) c.email,
            if (c.doc.isNotEmpty) c.doc,
            '${related.length} ${related.length == 1 ? 'registro' : 'registros'}',
          ].join(' · ')),
          onTap: () => _showContact(context, c, related),
          trailing: PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'edit') {
                final r = await _editContact(
                    context, Contact.fromJson(c.toJson()));
                if (r != null) {
                  final idx = store.contacts.indexOf(c);
                  if (idx >= 0) store.contacts[idx] = r;
                  store.upsertContact(r);
                }
              } else if (v == 'copy') {
                await Clipboard.setData(ClipboardData(text: c.phone));
                if (context.mounted) toast(context, 'Telefone copiado');
              } else if (v == 'del') {
                if (await confirm(context, 'Excluir cadastro?', c.name,
                    ok: 'Excluir', danger: true)) {
                  store.removeContact(c);
                }
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Editar')),
              if (c.phone.isNotEmpty)
                const PopupMenuItem(value: 'copy', child: Text('Copiar telefone')),
              const PopupMenuItem(value: 'del', child: Text('Excluir')),
            ],
          ),
        );
      },
    );
  }

  void _showContact(BuildContext context, Contact c, List<Claim> related) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints:
              BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.8),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            children: [
              Text(c.name, style: Theme.of(ctx).textTheme.titleLarge),
              Text(c.kind.label),
              const SizedBox(height: 12),
              if (c.phone.isNotEmpty) KeyValue('Telefone', c.phone),
              if (c.email.isNotEmpty) KeyValue('E-mail', c.email),
              if (c.doc.isNotEmpty) KeyValue('Documento', c.doc),
              if (c.notes.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(c.notes),
              ],
              const Divider(height: 24),
              Text('Registros (${related.length})',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              for (final cl in related)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${cl.number} · ${cl.vehicle.title}'),
                  subtitle: Text(cl.status.label),
                  onTap: () {
                    Navigator.pop(ctx);
                    openClaim(context, cl);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<Contact?> _editContact(BuildContext context, Contact ct) {
  return showFormDialog<Contact>(
    context: context,
    title: ct.name.isEmpty ? 'Novo cadastro' : 'Editar cadastro',
    onSave: () {
      if (ct.name.trim().isEmpty) {
        toast(context, 'Informe o nome.');
        return null;
      }
      ct.name = ct.name.trim();
      return ct;
    },
    body: (ctx, setS) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Picker<ContactKind>(
          label: 'Tipo',
          value: ct.kind,
          values: ContactKind.values,
          labelOf: (e) => e.label,
          onChanged: (e) => setS(() => ct.kind = e),
        ),
        const SizedBox(height: 12),
        BoundField(
            label: 'Nome',
            value: ct.name,
            capitalization: TextCapitalization.words,
            onChanged: (t) => ct.name = t),
        const SizedBox(height: 12),
        BoundField(
            label: 'Telefone',
            value: ct.phone,
            keyboard: TextInputType.phone,
            onChanged: (t) => ct.phone = t),
        const SizedBox(height: 12),
        BoundField(
            label: 'E-mail',
            value: ct.email,
            keyboard: TextInputType.emailAddress,
            capitalization: TextCapitalization.none,
            onChanged: (t) => ct.email = t),
        const SizedBox(height: 12),
        BoundField(
            label: 'CPF / CNPJ',
            value: ct.doc,
            onChanged: (t) => ct.doc = t),
        const SizedBox(height: 12),
        BoundField(
            label: 'Observações',
            value: ct.notes,
            maxLines: 3,
            onChanged: (t) => ct.notes = t),
      ],
    ),
  );
}
