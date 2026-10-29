import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../format.dart';
import '../models.dart';
import '../modules.dart';
import '../theme.dart';
import 'fipe_dialog.dart';
import 'widgets.dart';

class ClaimFormTab extends StatelessWidget {
  const ClaimFormTab({super.key, required this.claim});
  final Claim claim;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final c = claim;
    final v = c.vehicle;
    void q() => store.saveLater(c); // salva sem redesenhar
    void r() => store.touch(c); // salva e redesenha
    final hasInsurer = c.type != ClaimType.particular;

    final customers = store.contactsOf(ContactKind.cliente);
    final insurers = store.contactsOf(ContactKind.seguradora);
    final regulators = store.contactsOf(ContactKind.regulador);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionCard(
                  title: 'Identificação',
                  icon: Icons.badge_outlined,
                  children: [
                    FieldGrid(children: [
                      Picker<ClaimType>(
                        label: 'Tipo de atendimento',
                        value: c.type,
                        values: ClaimType.values,
                        labelOf: (e) => e.label,
                        onChanged: (e) {
                          c.type = e;
                          r();
                        },
                      ),
                      BoundField(
                        label: hasInsurer ? 'Nº do sinistro' : 'Nº de referência',
                        value: c.claimNumber,
                        prefixIcon: Icons.tag,
                        onChanged: (t) {
                          c.claimNumber = t;
                          q();
                        },
                      ),
                      DateField(
                        label: 'Data do sinistro',
                        value: c.accidentDate,
                        onChanged: (d) {
                          c.accidentDate = d;
                          r();
                        },
                      ),
                      DateField(
                        label: 'Previsão de entrega',
                        value: c.dueDate,
                        onChanged: (d) {
                          c.dueDate = d;
                          r();
                        },
                      ),
                    ]),
                  ],
                ),
                SectionCard(
                  title: 'Cliente',
                  icon: Icons.person_outline,
                  children: [
                    FieldGrid(children: [
                      BoundField(
                        label: 'Nome',
                        value: c.customerName,
                        prefixIcon: Icons.person,
                        capitalization: TextCapitalization.words,
                        suggestions: [for (final e in customers) e.name],
                        onChanged: (t) {
                          c.customerName = t;
                          final match = customers.where((e) =>
                              e.name.toLowerCase() == t.trim().toLowerCase());
                          if (match.isNotEmpty) {
                            final m = match.first;
                            if (c.customerPhone.isEmpty) c.customerPhone = m.phone;
                            if (c.customerDoc.isEmpty) c.customerDoc = m.doc;
                            if (c.customerEmail.isEmpty) c.customerEmail = m.email;
                            r();
                          } else {
                            q();
                          }
                        },
                      ),
                      BoundField(
                        label: 'Telefone / WhatsApp',
                        value: c.customerPhone,
                        keyboard: TextInputType.phone,
                        prefixIcon: Icons.phone,
                        onChanged: (t) {
                          c.customerPhone = t;
                          q();
                        },
                      ),
                      BoundField(
                        label: 'CPF / CNPJ',
                        value: c.customerDoc,
                        keyboard: TextInputType.number,
                        onChanged: (t) {
                          c.customerDoc = t;
                          q();
                        },
                      ),
                      BoundField(
                        label: 'E-mail',
                        value: c.customerEmail,
                        keyboard: TextInputType.emailAddress,
                        capitalization: TextCapitalization.none,
                        onChanged: (t) {
                          c.customerEmail = t;
                          q();
                        },
                      ),
                    ]),
                  ],
                ),
                if (hasInsurer)
                  SectionCard(
                    title: 'Seguradora e regulação',
                    icon: Icons.shield_outlined,
                    children: [
                      FieldGrid(children: [
                        BoundField(
                          label: c.type == ClaimType.frota
                              ? 'Frota / cooperativa'
                              : 'Seguradora',
                          value: c.insurerName,
                          prefixIcon: Icons.shield,
                          capitalization: TextCapitalization.words,
                          suggestions: [for (final e in insurers) e.name],
                          onChanged: (t) {
                            c.insurerName = t;
                            q();
                          },
                        ),
                        BoundField(
                          label: 'Apólice',
                          value: c.policyNumber,
                          onChanged: (t) {
                            c.policyNumber = t;
                            q();
                          },
                        ),
                        BoundField(
                          label: 'Regulador / perito',
                          value: c.regulatorName,
                          prefixIcon: Icons.engineering,
                          capitalization: TextCapitalization.words,
                          suggestions: [for (final e in regulators) e.name],
                          onChanged: (t) {
                            c.regulatorName = t;
                            final match = regulators.where((e) =>
                                e.name.toLowerCase() == t.trim().toLowerCase());
                            if (match.isNotEmpty && c.regulatorContact.isEmpty) {
                              c.regulatorContact = match.first.phone;
                              r();
                            } else {
                              q();
                            }
                          },
                        ),
                        BoundField(
                          label: 'Contato do regulador',
                          value: c.regulatorContact,
                          keyboard: TextInputType.phone,
                          onChanged: (t) {
                            c.regulatorContact = t;
                            q();
                          },
                        ),
                        if (c.type == ClaimType.seguradora)
                          NumField(
                            label: 'Franquia',
                            prefix: 'R\$',
                            value: c.deductible,
                            onChanged: (n) {
                              c.deductible = n;
                              r();
                            },
                          ),
                      ]),
                      if (c.approvedAt != null) ...[
                        const SizedBox(height: 12),
                        Row(children: [
                          Icon(Icons.verified,
                              color: statusColor(ClaimStatus.aprovado)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                                'Aprovado${c.approvedBy.isEmpty ? '' : ' por ${c.approvedBy}'} em ${dateTime(c.approvedAt)}'),
                          ),
                        ]),
                      ],
                    ],
                  ),
                SectionCard(
                  title: 'Veículo',
                  icon: Icons.directions_car_outlined,
                  trailing: !gate.allows(Mod.integracoes, Perm.sinistroEditar)
                      ? null
                      : FilledButton.tonalIcon(
                    onPressed: () async {
                      final res = await showFipeDialog(context);
                      if (res == null) return;
                      v.brand = res.brand;
                      v.model = res.model;
                      v.year = res.year;
                      v.fuel = res.fuel;
                      v.fipeCode = res.fipeCode;
                      v.fipeValue = res.value;
                      c.timeline.add(TimelineEvent(
                          text:
                              'Consulta FIPE ${res.fipeCode} (${res.reference}): ${money(res.value)}'));
                      r();
                    },
                    icon: const Icon(Icons.travel_explore, size: 18),
                    label: const Text('Buscar na FIPE'),
                  ),
                  children: [
                    FieldGrid(children: [
                      BoundField(
                        label: 'Placa',
                        value: v.plate,
                        prefixIcon: Icons.pin_outlined,
                        capitalization: TextCapitalization.characters,
                        formatters: [
                          LengthLimitingTextInputFormatter(8),
                          _PlateFormatter(),
                        ],
                        onChanged: (t) {
                          v.plate = t;
                          q();
                        },
                      ),
                      BoundField(
                        label: 'Marca',
                        value: v.brand,
                        capitalization: TextCapitalization.words,
                        onChanged: (t) {
                          v.brand = t;
                          q();
                        },
                      ),
                      BoundField(
                        label: 'Modelo / versão',
                        value: v.model,
                        onChanged: (t) {
                          v.model = t;
                          q();
                        },
                      ),
                      BoundField(
                        label: 'Ano',
                        value: v.year,
                        onChanged: (t) {
                          v.year = t;
                          q();
                        },
                      ),
                      BoundField(
                        label: 'Cor',
                        value: v.color,
                        capitalization: TextCapitalization.words,
                        onChanged: (t) {
                          v.color = t;
                          q();
                        },
                      ),
                      BoundField(
                        label: 'Chassi',
                        value: v.chassis,
                        capitalization: TextCapitalization.characters,
                        onChanged: (t) {
                          v.chassis = t;
                          q();
                        },
                      ),
                      BoundField(
                        label: 'Quilometragem',
                        value: v.km,
                        keyboard: TextInputType.number,
                        onChanged: (t) {
                          v.km = t;
                          q();
                        },
                      ),
                      BoundField(
                        label: 'Combustível',
                        value: v.fuel,
                        onChanged: (t) {
                          v.fuel = t;
                          q();
                        },
                      ),
                      NumField(
                        label: 'Valor FIPE',
                        prefix: 'R\$',
                        value: v.fipeValue,
                        onChanged: (n) {
                          v.fipeValue = n;
                          r();
                        },
                      ),
                    ]),
                    if (v.fipeCode.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('Código FIPE: ${v.fipeCode}',
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ],
                ),
                SectionCard(
                  title: 'Relato e observações',
                  icon: Icons.notes,
                  children: [
                    BoundField(
                      label: 'Relato do sinistro / reclamação do cliente',
                      value: c.description,
                      maxLines: 5,
                      onChanged: (t) {
                        c.description = t;
                        q();
                      },
                    ),
                    const SizedBox(height: 12),
                    BoundField(
                      label: 'Observações internas',
                      value: c.notes,
                      maxLines: 4,
                      onChanged: (t) {
                        c.notes = t;
                        q();
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PlateFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final t = plateMask(newValue.text);
    return TextEditingValue(
      text: t,
      selection: TextSelection.collapsed(offset: t.length),
    );
  }
}
