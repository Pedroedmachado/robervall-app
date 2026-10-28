// Modelos de dados do Funilar. Tudo é serializado em JSON e salvo localmente.

String newId() {
  final now = DateTime.now().microsecondsSinceEpoch;
  _idCounter = (_idCounter + 1) % 100000;
  return '${now.toRadixString(36)}${_idCounter.toRadixString(36)}';
}

int _idCounter = 0;

double _d(Object? v, [double def = 0]) {
  if (v == null) return def;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString().replaceAll(',', '.')) ?? def;
}

int _i(Object? v, [int def = 0]) {
  if (v == null) return def;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? def;
}

String _s(Object? v, [String def = '']) => v == null ? def : v.toString();

DateTime? _dt(Object? v) => v == null ? null : DateTime.tryParse(v.toString());

T _enum<T extends Enum>(List<T> values, Object? name, T def) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return def;
}

// ---------------------------------------------------------------------------
// Enums

enum ClaimStatus {
  aberto('Aberto'),
  vistoria('Em vistoria'),
  orcamento('Em orçamento'),
  aguardandoAprovacao('Aguardando aprovação'),
  aprovado('Aprovado'),
  emReparo('Em reparo'),
  concluido('Concluído'),
  entregue('Entregue'),
  cancelado('Cancelado / recusado');

  const ClaimStatus(this.label);
  final String label;

  bool get isOpen =>
      this != ClaimStatus.entregue && this != ClaimStatus.cancelado;
}

enum ClaimType {
  particular('Particular'),
  seguradora('Seguradora'),
  terceiro('Terceiro'),
  frota('Frota / cooperativa');

  const ClaimType(this.label);
  final String label;
}

/// Operação do item do orçamento (T, R, P, S).
enum ItemOp {
  troca('Troca', 'T'),
  reparo('Reparo', 'R'),
  pintura('Pintura', 'P'),
  servico('Serviço', 'S');

  const ItemOp(this.label, this.code);
  final String label;
  final String code;
}

enum PartOrigin {
  nenhuma('—'),
  original('Original (montadora)'),
  genuina('Genuína'),
  paralela('Paralela / similar'),
  usada('Usada / recondicionada');

  const PartOrigin(this.label);
  final String label;
}

enum LaborType {
  funilaria('Funilaria'),
  mecanica('Mecânica'),
  eletrica('Elétrica'),
  tapecaria('Tapeçaria'),
  vidracaria('Vidraçaria');

  const LaborType(this.label);
  final String label;
}

enum PhotoCategory {
  avaria('Avaria'),
  geral('Geral do veículo'),
  documento('Documento'),
  antes('Antes do reparo'),
  depois('Depois do reparo');

  const PhotoCategory(this.label);
  final String label;
}

enum ContactKind {
  cliente('Cliente'),
  seguradora('Seguradora'),
  regulador('Regulador / perito'),
  fornecedor('Fornecedor'),
  funcionario('Funcionário');

  const ContactKind(this.label);
  final String label;
}

// ---------------------------------------------------------------------------

class Vehicle {
  String plate;
  String brand;
  String model;
  String year;
  String color;
  String chassis;
  String km;
  String fuel;
  String fipeCode;
  double fipeValue;

  Vehicle({
    this.plate = '',
    this.brand = '',
    this.model = '',
    this.year = '',
    this.color = '',
    this.chassis = '',
    this.km = '',
    this.fuel = '',
    this.fipeCode = '',
    this.fipeValue = 0,
  });

  String get title {
    final parts = [brand, model, year].where((e) => e.trim().isNotEmpty);
    return parts.isEmpty ? 'Veículo não informado' : parts.join(' ');
  }

  Map<String, dynamic> toJson() => {
        'plate': plate,
        'brand': brand,
        'model': model,
        'year': year,
        'color': color,
        'chassis': chassis,
        'km': km,
        'fuel': fuel,
        'fipeCode': fipeCode,
        'fipeValue': fipeValue,
      };

  factory Vehicle.fromJson(Map<String, dynamic> j) => Vehicle(
        plate: _s(j['plate']),
        brand: _s(j['brand']),
        model: _s(j['model']),
        year: _s(j['year']),
        color: _s(j['color']),
        chassis: _s(j['chassis']),
        km: _s(j['km']),
        fuel: _s(j['fuel']),
        fipeCode: _s(j['fipeCode']),
        fipeValue: _d(j['fipeValue']),
      );
}

class BudgetItem {
  String id;
  String description;
  String partNumber;
  ItemOp op;
  PartOrigin origin;
  LaborType laborType;
  double qty;

  /// Preço unitário da peça (troca) ou valor fixo do serviço (servico).
  double price;

  /// Horas de mão de obra (remoção/instalação, reparo, serviço técnico).
  double laborHours;

  /// Horas de pintura.
  double paintHours;
  double discountPct;
  String supplier;
  String region;
  bool approved;
  String note;

  /// Mão de obra na peça é remoção e instalação (R I), não reparo.
  bool removeInstall;

  BudgetItem({
    String? id,
    this.description = '',
    this.partNumber = '',
    this.op = ItemOp.troca,
    this.origin = PartOrigin.nenhuma,
    this.laborType = LaborType.funilaria,
    this.qty = 1,
    this.price = 0,
    this.laborHours = 0,
    this.paintHours = 0,
    this.discountPct = 0,
    this.supplier = '',
    this.region = '',
    this.approved = true,
    this.note = '',
    this.removeInstall = false,
  }) : id = id ?? newId();

  BudgetItem copy() => BudgetItem.fromJson(toJson())..id = newId();

  Map<String, dynamic> toJson() => {
        'id': id,
        'description': description,
        'partNumber': partNumber,
        'op': op.name,
        'origin': origin.name,
        'laborType': laborType.name,
        'qty': qty,
        'price': price,
        'laborHours': laborHours,
        'paintHours': paintHours,
        'discountPct': discountPct,
        'supplier': supplier,
        'region': region,
        'approved': approved,
        'note': note,
        'ri': removeInstall,
      };

  factory BudgetItem.fromJson(Map<String, dynamic> j) => BudgetItem(
        id: _s(j['id'], newId()),
        description: _s(j['description']),
        partNumber: _s(j['partNumber']),
        op: _enum(ItemOp.values, j['op'], ItemOp.troca),
        origin: _enum(PartOrigin.values, j['origin'], PartOrigin.nenhuma),
        laborType:
            _enum(LaborType.values, j['laborType'], LaborType.funilaria),
        qty: _d(j['qty'], 1),
        price: _d(j['price']),
        laborHours: _d(j['laborHours']),
        paintHours: _d(j['paintHours']),
        discountPct: _d(j['discountPct']),
        supplier: _s(j['supplier']),
        region: _s(j['region']),
        approved: j['approved'] != false,
        note: _s(j['note']),
        removeInstall: j['ri'] == true,
      );
}

class ClaimPhoto {
  String id;
  String fileName; // relativo à pasta de fotos
  PhotoCategory category;
  String caption;
  DateTime takenAt;

  ClaimPhoto({
    String? id,
    required this.fileName,
    this.category = PhotoCategory.avaria,
    this.caption = '',
    DateTime? takenAt,
  })  : id = id ?? newId(),
        takenAt = takenAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'fileName': fileName,
        'category': category.name,
        'caption': caption,
        'takenAt': takenAt.toIso8601String(),
      };

  factory ClaimPhoto.fromJson(Map<String, dynamic> j) => ClaimPhoto(
        id: _s(j['id'], newId()),
        fileName: _s(j['fileName']),
        category:
            _enum(PhotoCategory.values, j['category'], PhotoCategory.avaria),
        caption: _s(j['caption']),
        takenAt: _dt(j['takenAt']),
      );
}

class TimelineEvent {
  DateTime at;
  String text;
  bool isStatus;

  TimelineEvent({DateTime? at, required this.text, this.isStatus = false})
      : at = at ?? DateTime.now();

  Map<String, dynamic> toJson() =>
      {'at': at.toIso8601String(), 'text': text, 'isStatus': isStatus};

  factory TimelineEvent.fromJson(Map<String, dynamic> j) => TimelineEvent(
        at: _dt(j['at']),
        text: _s(j['text']),
        isStatus: j['isStatus'] == true,
      );
}

class Claim {
  String id;
  String number; // número interno (ex.: FN-0001)
  String claimNumber; // número do sinistro na seguradora
  ClaimType type;
  ClaimStatus status;

  String customerName;
  String customerPhone;
  String customerDoc;
  String customerEmail;

  String insurerName;
  String policyNumber;
  String regulatorName;
  String regulatorContact;

  Vehicle vehicle;
  String description; // relato do sinistro / reclamação
  DateTime createdAt;
  DateTime updatedAt;
  DateTime? accidentDate;
  DateTime? dueDate; // previsão de entrega

  double deductible; // franquia
  double discountPct; // desconto geral
  double extraCosts; // guincho, terceiros, etc.

  String approvedBy;
  DateTime? approvedAt;
  String notes;

  List<BudgetItem> items;
  List<ClaimPhoto> photos;
  Map<String, int> damages; // região -> severidade 1..3
  List<TimelineEvent> timeline;

  Claim({
    String? id,
    this.number = '',
    this.claimNumber = '',
    this.type = ClaimType.particular,
    this.status = ClaimStatus.aberto,
    this.customerName = '',
    this.customerPhone = '',
    this.customerDoc = '',
    this.customerEmail = '',
    this.insurerName = '',
    this.policyNumber = '',
    this.regulatorName = '',
    this.regulatorContact = '',
    Vehicle? vehicle,
    this.description = '',
    DateTime? createdAt,
    DateTime? updatedAt,
    this.accidentDate,
    this.dueDate,
    this.deductible = 0,
    this.discountPct = 0,
    this.extraCosts = 0,
    this.approvedBy = '',
    this.approvedAt,
    this.notes = '',
    List<BudgetItem>? items,
    List<ClaimPhoto>? photos,
    Map<String, int>? damages,
    List<TimelineEvent>? timeline,
  })  : id = id ?? newId(),
        vehicle = vehicle ?? Vehicle(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now(),
        items = items ?? [],
        photos = photos ?? [],
        damages = damages ?? {},
        timeline = timeline ?? [];

  bool get isOverdue {
    final d = dueDate;
    if (d == null || !status.isOpen) return false;
    if (status == ClaimStatus.concluido) return false;
    final today = DateTime.now();
    return DateTime(d.year, d.month, d.day)
        .isBefore(DateTime(today.year, today.month, today.day));
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'number': number,
        'claimNumber': claimNumber,
        'type': type.name,
        'status': status.name,
        'customerName': customerName,
        'customerPhone': customerPhone,
        'customerDoc': customerDoc,
        'customerEmail': customerEmail,
        'insurerName': insurerName,
        'policyNumber': policyNumber,
        'regulatorName': regulatorName,
        'regulatorContact': regulatorContact,
        'vehicle': vehicle.toJson(),
        'description': description,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'accidentDate': accidentDate?.toIso8601String(),
        'dueDate': dueDate?.toIso8601String(),
        'deductible': deductible,
        'discountPct': discountPct,
        'extraCosts': extraCosts,
        'approvedBy': approvedBy,
        'approvedAt': approvedAt?.toIso8601String(),
        'notes': notes,
        'items': items.map((e) => e.toJson()).toList(),
        'photos': photos.map((e) => e.toJson()).toList(),
        'damages': damages,
        'timeline': timeline.map((e) => e.toJson()).toList(),
      };

  factory Claim.fromJson(Map<String, dynamic> j) {
    final dmg = <String, int>{};
    final rawDmg = j['damages'];
    if (rawDmg is Map) {
      rawDmg.forEach((k, v) => dmg[k.toString()] = _i(v));
    }
    List<Map<String, dynamic>> list(Object? v) => v is List
        ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : <Map<String, dynamic>>[];
    final veh = j['vehicle'];
    return Claim(
      id: _s(j['id'], newId()),
      number: _s(j['number']),
      claimNumber: _s(j['claimNumber']),
      type: _enum(ClaimType.values, j['type'], ClaimType.particular),
      status: _enum(ClaimStatus.values, j['status'], ClaimStatus.aberto),
      customerName: _s(j['customerName']),
      customerPhone: _s(j['customerPhone']),
      customerDoc: _s(j['customerDoc']),
      customerEmail: _s(j['customerEmail']),
      insurerName: _s(j['insurerName']),
      policyNumber: _s(j['policyNumber']),
      regulatorName: _s(j['regulatorName']),
      regulatorContact: _s(j['regulatorContact']),
      vehicle: veh is Map
          ? Vehicle.fromJson(Map<String, dynamic>.from(veh))
          : Vehicle(),
      description: _s(j['description']),
      createdAt: _dt(j['createdAt']),
      updatedAt: _dt(j['updatedAt']),
      accidentDate: _dt(j['accidentDate']),
      dueDate: _dt(j['dueDate']),
      deductible: _d(j['deductible']),
      discountPct: _d(j['discountPct']),
      extraCosts: _d(j['extraCosts']),
      approvedBy: _s(j['approvedBy']),
      approvedAt: _dt(j['approvedAt']),
      notes: _s(j['notes']),
      items: list(j['items']).map(BudgetItem.fromJson).toList(),
      photos: list(j['photos']).map(ClaimPhoto.fromJson).toList(),
      damages: dmg,
      timeline: list(j['timeline']).map(TimelineEvent.fromJson).toList(),
    );
  }
}

class Contact {
  String id;
  ContactKind kind;
  String name;
  String phone;
  String email;
  String doc;
  String notes;

  Contact({
    String? id,
    this.kind = ContactKind.cliente,
    this.name = '',
    this.phone = '',
    this.email = '',
    this.doc = '',
    this.notes = '',
  }) : id = id ?? newId();

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'name': name,
        'phone': phone,
        'email': email,
        'doc': doc,
        'notes': notes,
      };

  factory Contact.fromJson(Map<String, dynamic> j) => Contact(
        id: _s(j['id'], newId()),
        kind: _enum(ContactKind.values, j['kind'], ContactKind.cliente),
        name: _s(j['name']),
        phone: _s(j['phone']),
        email: _s(j['email']),
        doc: _s(j['doc']),
        notes: _s(j['notes']),
      );
}

/// Item do catálogo próprio de peças e serviços (tabela de preços da oficina).
class CatalogItem {
  String id;
  String description;
  String partNumber;
  ItemOp op;
  LaborType laborType;
  double price;
  double laborHours;
  double paintHours;
  String region;
  bool removeInstall;

  CatalogItem({
    String? id,
    this.description = '',
    this.partNumber = '',
    this.op = ItemOp.troca,
    this.laborType = LaborType.funilaria,
    this.price = 0,
    this.laborHours = 0,
    this.paintHours = 0,
    this.region = '',
    this.removeInstall = false,
  }) : id = id ?? newId();

  BudgetItem toBudgetItem() => BudgetItem(
        description: description,
        partNumber: partNumber,
        op: op,
        laborType: laborType,
        price: price,
        laborHours: laborHours,
        paintHours: paintHours,
        region: region,
        removeInstall: removeInstall,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'description': description,
        'partNumber': partNumber,
        'op': op.name,
        'laborType': laborType.name,
        'price': price,
        'laborHours': laborHours,
        'paintHours': paintHours,
        'region': region,
        'ri': removeInstall,
      };

  factory CatalogItem.fromJson(Map<String, dynamic> j) => CatalogItem(
        id: _s(j['id'], newId()),
        description: _s(j['description']),
        partNumber: _s(j['partNumber']),
        op: _enum(ItemOp.values, j['op'], ItemOp.troca),
        laborType:
            _enum(LaborType.values, j['laborType'], LaborType.funilaria),
        price: _d(j['price']),
        laborHours: _d(j['laborHours']),
        paintHours: _d(j['paintHours']),
        region: _s(j['region']),
        removeInstall: j['ri'] == true,
      );
}

class Settings {
  String shopName;
  String shopDoc;
  String shopAddress;
  String shopPhone;
  String shopEmail;
  String budgetFooter;
  int budgetValidityDays;
  int nextNumber;
  String numberPrefix;
  String themeMode; // system | light | dark

  /// Valor da hora por tipo de mão de obra.
  Map<String, double> laborRates;
  double paintRate; // hora de pintura (mão de obra)
  double paintMaterialRate; // material de pintura por hora pintada
  double totalLossPct; // % do valor FIPE para indicar possível perda total

  Settings({
    this.shopName = 'Funilar',
    this.shopDoc = '',
    this.shopAddress = '',
    this.shopPhone = '',
    this.shopEmail = '',
    this.budgetFooter =
        'Orçamento sujeito a alteração após desmontagem do veículo.',
    this.budgetValidityDays = 15,
    this.nextNumber = 1,
    this.numberPrefix = 'FN',
    this.themeMode = 'system',
    Map<String, double>? laborRates,
    this.paintRate = 90,
    this.paintMaterialRate = 70,
    this.totalLossPct = 75,
  }) : laborRates = laborRates ??
            {
              LaborType.funilaria.name: 90,
              LaborType.mecanica.name: 110,
              LaborType.eletrica.name: 110,
              LaborType.tapecaria.name: 80,
              LaborType.vidracaria.name: 80,
            };

  double rateFor(LaborType t) => laborRates[t.name] ?? 0;

  Map<String, dynamic> toJson() => {
        'shopName': shopName,
        'shopDoc': shopDoc,
        'shopAddress': shopAddress,
        'shopPhone': shopPhone,
        'shopEmail': shopEmail,
        'budgetFooter': budgetFooter,
        'budgetValidityDays': budgetValidityDays,
        'nextNumber': nextNumber,
        'numberPrefix': numberPrefix,
        'themeMode': themeMode,
        'laborRates': laborRates,
        'paintRate': paintRate,
        'paintMaterialRate': paintMaterialRate,
        'totalLossPct': totalLossPct,
      };

  factory Settings.fromJson(Map<String, dynamic> j) {
    var shop = _s(j['shopName'], 'Funilar');
    if (shop == 'Robervall') shop = 'Funilar'; // nome antigo do app
    final s = Settings(
      shopName: shop,
      shopDoc: _s(j['shopDoc']),
      shopAddress: _s(j['shopAddress']),
      shopPhone: _s(j['shopPhone']),
      shopEmail: _s(j['shopEmail']),
      budgetFooter: _s(j['budgetFooter'],
          'Orçamento sujeito a alteração após desmontagem do veículo.'),
      budgetValidityDays: _i(j['budgetValidityDays'], 15),
      nextNumber: _i(j['nextNumber'], 1),
      numberPrefix: _s(j['numberPrefix'], 'FN'),
      themeMode: _s(j['themeMode'], 'system'),
      paintRate: _d(j['paintRate'], 90),
      paintMaterialRate: _d(j['paintMaterialRate'], 70),
      totalLossPct: _d(j['totalLossPct'], 75),
    );
    final r = j['laborRates'];
    if (r is Map) {
      r.forEach((k, v) => s.laborRates[k.toString()] = _d(v));
    }
    return s;
  }
}

// ---------------------------------------------------------------------------
// Peça unificada: uma linha por peça, com as operações por extenso.

/// Siglas das operações (usadas no PDF e na pré-visualização).
const opLegend = <(String, String)>[
  ('T', 'Troca da peça (peça nova)'),
  ('R I', 'Remoção e instalação'),
  ('R', 'Reparo / recuperação da peça'),
  ('P', 'Pintura'),
  ('S', 'Serviço'),
];

/// Sigla da linha, ex.: "T / P", "R I / P", "R / P".
String opCode(ItemOp op, double laborHours, double paintHours,
    {bool removeInstall = false}) {
  if (op == ItemOp.servico) return 'S';
  final parts = <String>[
    if (op == ItemOp.troca) 'T',
    if (op != ItemOp.troca && laborHours > 0) removeInstall ? 'R I' : 'R',
    if (paintHours > 0) 'P',
  ];
  if (parts.isEmpty) return op == ItemOp.troca ? 'T' : (removeInstall ? 'R I' : 'R');
  return parts.join(' / ');
}

/// Siglas usadas num conjunto de linhas, na ordem da legenda.
List<(String, String)> legendFor(Iterable<BudgetItem> items) {
  final used = <String>{};
  for (final it in items) {
    used.addAll(opCode(it.op, it.laborHours, it.paintHours,
            removeInstall: it.removeInstall)
        .split(' / '));
  }
  return [for (final e in opLegend) if (used.contains(e.$1)) e];
}

/// Nome das operações sem horas, ex.: "Troca + pintura".
String opNames(ItemOp op, double laborHours, double paintHours,
    {bool removeInstall = false}) {
  if (op == ItemOp.servico) return 'Serviço';
  final parts = <String>[
    if (op == ItemOp.troca) 'Troca',
    if (op != ItemOp.troca && laborHours > 0)
      removeInstall ? 'Remoção e instalação' : 'Reparo',
    if (paintHours > 0) 'Pintura',
  ];
  if (parts.isEmpty) return op == ItemOp.troca ? 'Troca' : 'Reparo';
  return [parts.first, ...parts.skip(1).map((e) => e.toLowerCase())].join(' + ');
}

String _h(double v) {
  var s = v.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '');
  if (s.endsWith('.')) s = s.substring(0, s.length - 1);
  return '${s.replaceAll('.', ',')} h';
}

/// Operações com horas, ex.: ["Troca", "Mão de obra 1 h", "Pintura 2 h"].
List<String> opDetails(ItemOp op, double laborHours, double paintHours,
    {bool removeInstall = false}) {
  if (op == ItemOp.servico) return ['Serviço'];
  return [
    if (op == ItemOp.troca) 'Troca',
    if (laborHours > 0)
      op == ItemOp.troca
          ? 'Mão de obra ${_h(laborHours)}'
          : (removeInstall
              ? 'Remoção e instalação ${_h(laborHours)}'
              : 'Reparo ${_h(laborHours)}'),
    if (paintHours > 0) 'Pintura ${_h(paintHours)}',
    if (op != ItemOp.troca && laborHours <= 0 && paintHours <= 0) 'Reparo',
  ];
}

/// Define a operação a partir do que a pessoa escolheu no editor.
ItemOp opFor({required bool service, required bool replace, required double laborHours, required double paintHours}) {
  if (service) return ItemOp.servico;
  if (replace) return ItemOp.troca;
  if (laborHours <= 0 && paintHours > 0) return ItemOp.pintura;
  return ItemOp.reparo;
}

/// Junta linhas da mesma peça (ex.: "Capô" reparo + "Capô" pintura) numa só.
/// Duas trocas da mesma peça não são juntadas (podem ser quantidades).
List<BudgetItem> mergePartLines(List<BudgetItem> items) {
  final out = <BudgetItem>[];
  for (final it in items) {
    if (it.op == ItemOp.servico) {
      out.add(it);
      continue;
    }
    final key = it.description.trim().toLowerCase();
    BudgetItem? same;
    for (final o in out) {
      if (o.op != ItemOp.servico &&
          o.approved == it.approved &&
          o.description.trim().toLowerCase() == key &&
          !(o.op == ItemOp.troca && it.op == ItemOp.troca)) {
        same = o;
        break;
      }
    }
    if (same == null || key.isEmpty) {
      out.add(it);
      continue;
    }
    if (it.op == ItemOp.troca) {
      same.op = ItemOp.troca;
      same.price = it.price;
      same.qty = it.qty;
      same.origin = it.origin;
      same.partNumber = it.partNumber.isEmpty ? same.partNumber : it.partNumber;
      same.supplier = it.supplier.isEmpty ? same.supplier : it.supplier;
      same.discountPct = it.discountPct;
    }
    same.laborHours += it.laborHours;
    same.paintHours += it.paintHours;
    same.removeInstall = same.removeInstall || it.removeInstall;
    if (same.op != ItemOp.troca) {
      same.op = opFor(
          service: false,
          replace: false,
          laborHours: same.laborHours,
          paintHours: same.paintHours);
    }
    if (it.note.isNotEmpty) {
      same.note = same.note.isEmpty ? it.note : '${same.note}; ${it.note}';
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// Financeiro

enum ExpenseCategory {
  fixo('Gastos fixos'),
  fornecedor('Fornecedores / peças'),
  funcionario('Funcionários'),
  materiais('Materiais'),
  impostos('Impostos e taxas'),
  outros('Outros');

  const ExpenseCategory(this.label);
  final String label;
}

/// Lançamento manual do financeiro (gasto ou receita avulsa).
class FinanceEntry {
  String id;
  bool isIncome;
  DateTime date;
  String description;
  ExpenseCategory category;
  double amount;
  String contact; // fornecedor, funcionário, cliente...
  String claimId; // sinistro vinculado (opcional)
  bool recurring; // repete todo mês a partir de [date]
  DateTime? recurringUntil;
  String notes;

  FinanceEntry({
    String? id,
    this.isIncome = false,
    DateTime? date,
    this.description = '',
    this.category = ExpenseCategory.outros,
    this.amount = 0,
    this.contact = '',
    this.claimId = '',
    this.recurring = false,
    this.recurringUntil,
    this.notes = '',
  })  : id = id ?? newId(),
        date = date ?? DateTime.now();

  String get categoryLabel => isIncome ? 'Outras receitas' : category.label;

  Map<String, dynamic> toJson() => {
        'id': id,
        'isIncome': isIncome,
        'date': date.toIso8601String(),
        'description': description,
        'category': category.name,
        'amount': amount,
        'contact': contact,
        'claimId': claimId,
        'recurring': recurring,
        'recurringUntil': recurringUntil?.toIso8601String(),
        'notes': notes,
      };

  factory FinanceEntry.fromJson(Map<String, dynamic> j) => FinanceEntry(
        id: _s(j['id'], newId()),
        isIncome: j['isIncome'] == true,
        date: _dt(j['date']),
        description: _s(j['description']),
        category:
            _enum(ExpenseCategory.values, j['category'], ExpenseCategory.outros),
        amount: _d(j['amount']),
        contact: _s(j['contact']),
        claimId: _s(j['claimId']),
        recurring: j['recurring'] == true,
        recurringUntil: _dt(j['recurringUntil']),
        notes: _s(j['notes']),
      );
}
