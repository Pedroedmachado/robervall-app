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
  entrada('Entrada (recepção)'),
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

  /// Mão de obra na peça é remoção e instalação (R&I), não reparo.
  bool removeInstall;

  /// Com R&I: a peça também é reparada (desmonta, recupera e monta).
  bool alsoRepair;

  /// Peça que sai do estoque da oficina (vazio = comprar).
  String stockId;

  /// Tarefa concluída na produção (O.S.).
  bool done;

  /// Peça principal da qual este item é complemento (vazio = item normal).
  String parentId;

  /// Mão de obra cobrada por peça (valor fechado, sem separar horas de
  /// reparo e de pintura). [doRepair]/[doPaint] dizem o que é feito na peça.
  bool perPiece;
  double piecePrice;
  bool doRepair;
  bool doPaint;

  /// Tem reparo/R&I/mão de obra na peça (por horas ou por peça).
  bool get hasLabor => perPiece ? doRepair : laborHours > 0;

  /// Tem pintura na peça (por horas ou por peça).
  bool get hasPaint => perPiece ? doPaint : paintHours > 0;

  /// Valores usados nas siglas (1 = tem, quando cobrado por peça).
  double get labFlag => perPiece ? (doRepair ? 1 : 0) : laborHours;
  double get paintFlag => perPiece ? (doPaint ? 1 : 0) : paintHours;

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
    this.alsoRepair = false,
    this.stockId = '',
    this.done = false,
    this.parentId = '',
    this.perPiece = false,
    this.piecePrice = 0,
    this.doRepair = true,
    this.doPaint = false,
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
        if (alsoRepair) 'rr': true,
        if (stockId.isNotEmpty) 'stock': stockId,
        if (done) 'done': true,
        'parent': parentId,
        if (perPiece) ...{
          'pp': true,
          'ppv': piecePrice,
          'pr': doRepair,
          'pt': doPaint,
        },
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
        alsoRepair: j['rr'] == true,
        stockId: _s(j['stock']),
        done: j['done'] == true,
        parentId: _s(j['parent']),
        perPiece: j['pp'] == true,
        piecePrice: _d(j['ppv']),
        doRepair: j['pr'] != false,
        doPaint: j['pt'] == true,
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
  DateTime? concludedAt; // quando ficou concluído (vai para o Caixa)
  String notes;

  List<BudgetItem> items;
  List<ClaimPhoto> photos;
  Map<String, int> damages; // região -> severidade 1..3
  /// Quem trabalha no carro (pintor, funileiro, martelinho…), com o custo.
  List<CrewMember> crew;
  List<TimelineEvent> timeline;

  /// Quanto já saiu do estoque por item (id do item → uso), para devolver
  /// se o orçamento reabrir ou o item sair.
  Map<String, StockUse> stockTaken;

  /// Avarias que já estavam no carro quando ele chegou (não entram no
  /// orçamento): região -> intensidade 1..3.
  Map<String, int> preDamages;

  /// Checklist de entrada (recepção).
  Reception reception;

  /// Insumos usados na O.S. (lixa, massa, primer…), com custo.
  List<SupplyUse> supplies;

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
    this.concludedAt,
    this.notes = '',
    List<BudgetItem>? items,
    List<ClaimPhoto>? photos,
    Map<String, int>? damages,
    List<TimelineEvent>? timeline,
    List<CrewMember>? crew,
    Map<String, StockUse>? stockTaken,
    Map<String, int>? preDamages,
    Reception? reception,
    List<SupplyUse>? supplies,
  })  : id = id ?? newId(),
        crew = crew ?? [],
        stockTaken = stockTaken ?? {},
        preDamages = preDamages ?? {},
        reception = reception ?? Reception(),
        supplies = supplies ?? [],
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
        if (concludedAt != null) 'concludedAt': concludedAt!.toIso8601String(),
        'notes': notes,
        'items': items.map((e) => e.toJson()).toList(),
        'photos': photos.map((e) => e.toJson()).toList(),
        'damages': damages,
        'crew': crew.map((e) => e.toJson()).toList(),
        if (preDamages.isNotEmpty) 'preDamages': preDamages,
        if (!reception.isEmpty) 'reception': reception.toJson(),
        if (supplies.isNotEmpty)
          'supplies': supplies.map((e) => e.toJson()).toList(),
        if (stockTaken.isNotEmpty)
          'stockTaken': {
            for (final e in stockTaken.entries) e.key: e.value.toJson()
          },
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
      concludedAt: _dt(j['concludedAt']),
      notes: _s(j['notes']),
      items: list(j['items']).map(BudgetItem.fromJson).toList(),
      photos: list(j['photos']).map(ClaimPhoto.fromJson).toList(),
      damages: dmg,
      crew: [
        ...list(j['crew']).map(CrewMember.fromJson),
        // versões antigas: só um pintor por carro
        if (j['crew'] == null && _s(j['painter']).isNotEmpty)
          CrewMember(role: OutsourcedService.pintura, contactId: _s(j['painter'])),
      ],
      timeline: list(j['timeline']).map(TimelineEvent.fromJson).toList(),
      preDamages: {
        if (j['preDamages'] is Map)
          for (final e in (j['preDamages'] as Map).entries)
            '${e.key}': _d(e.value).round(),
      },
      reception: j['reception'] is Map
          ? Reception.fromJson(Map<String, dynamic>.from(j['reception'] as Map))
          : Reception(),
      supplies: list(j['supplies']).map(SupplyUse.fromJson).toList(),
      stockTaken: {
        if (j['stockTaken'] is Map)
          for (final e in (j['stockTaken'] as Map).entries)
            if (e.value is Map)
              '${e.key}':
                  StockUse.fromJson(Map<String, dynamic>.from(e.value as Map)),
      },
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

  // Funcionário: modalidade, forma de pagamento e valor combinado
  bool outsourced;
  OutsourcedService service;
  PayType payType;
  double rate; // salário mensal, valor da empreita ou valor por peça

  Contact({
    String? id,
    this.kind = ContactKind.cliente,
    this.name = '',
    this.phone = '',
    this.email = '',
    this.doc = '',
    this.notes = '',
    this.outsourced = false,
    this.service = OutsourcedService.pintura,
    this.payType = PayType.porPeca,
    this.rate = 0,
  }) : id = id ?? newId();

  /// Ex.: "Terceirizado · Pintura · Por peça".
  String get workerSummary => [
        outsourced ? 'Terceirizado · ${service.label}' : 'Funcionário',
        payType.label,
      ].join(' · ');

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'name': name,
        'phone': phone,
        'email': email,
        'doc': doc,
        'notes': notes,
        'outsourced': outsourced,
        'service': service.name,
        'payType': payType.name,
        'rate': rate,
      };

  factory Contact.fromJson(Map<String, dynamic> j) => Contact(
        id: _s(j['id'], newId()),
        kind: _enum(ContactKind.values, j['kind'], ContactKind.cliente),
        name: _s(j['name']),
        phone: _s(j['phone']),
        email: _s(j['email']),
        doc: _s(j['doc']),
        notes: _s(j['notes']),
        outsourced: j['outsourced'] == true,
        service: _enum(OutsourcedService.values, j['service'],
            OutsourcedService.pintura),
        payType: _enum(PayType.values, j['payType'], PayType.porPeca),
        rate: _d(j['rate']),
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
  bool alsoRepair;
  bool perPiece;
  double piecePrice;
  bool doRepair;
  bool doPaint;

  double get labFlag => perPiece ? (doRepair ? 1 : 0) : laborHours;
  double get paintFlag => perPiece ? (doPaint ? 1 : 0) : paintHours;

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
    this.alsoRepair = false,
    this.perPiece = false,
    this.piecePrice = 0,
    this.doRepair = true,
    this.doPaint = false,
  }) : id = id ?? newId();

  BudgetItem toBudgetItem() => BudgetItem(
        perPiece: perPiece,
        piecePrice: piecePrice,
        doRepair: doRepair,
        doPaint: doPaint,
        description: description,
        partNumber: partNumber,
        op: op,
        laborType: laborType,
        price: price,
        laborHours: laborHours,
        paintHours: paintHours,
        region: region,
        removeInstall: removeInstall,
        alsoRepair: alsoRepair,
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
        if (alsoRepair) 'rr': true,
        if (perPiece) ...{
          'pp': true,
          'ppv': piecePrice,
          'pr': doRepair,
          'pt': doPaint,
        },
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
        alsoRepair: j['rr'] == true,
        perPiece: j['pp'] == true,
        piecePrice: _d(j['ppv']),
        doRepair: j['pr'] != false,
        doPaint: j['pt'] == true,
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
  bool perPieceDefault; // itens novos já cobram a mão de obra por peça
  bool showHours; // mostra horas de M.O./pintura no orçamento (seguradora)
  String managerPin; // PIN do gestor (modo produção, baixa de insumos)
  bool productionMode; // aparelho em modo chão de fábrica (sem valores)

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
    this.perPieceDefault = false,
    this.showHours = false,
    this.managerPin = '',
    this.productionMode = false,
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
        'perPiece': perPieceDefault,
        'showHours': showHours,
        'managerPin': managerPin,
        'productionMode': productionMode,
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
      perPieceDefault: j['perPiece'] == true,
      showHours: j['showHours'] == true,
      managerPin: _s(j['managerPin']),
      productionMode: j['productionMode'] == true,
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
  ('R&I', 'Remoção e instalação'),
  ('R', 'Reparo / recuperação da peça'),
  ('P', 'Pintura'),
  ('S', 'Serviço'),
];

/// Sigla da linha, ex.: "T / P", "R I / P", "R / P".
String opCode(ItemOp op, double laborHours, double paintHours,
    {bool removeInstall = false, bool alsoRepair = false}) {
  if (op == ItemOp.servico) return 'S';
  final parts = <String>[
    if (op == ItemOp.troca) 'T',
    if (op != ItemOp.troca && laborHours > 0)
      removeInstall ? (alsoRepair ? 'R&I / R' : 'R&I') : 'R',
    if (paintHours > 0) 'P',
  ];
  if (parts.isEmpty) return op == ItemOp.troca ? 'T' : (removeInstall ? 'R&I' : 'R');
  return parts.join(' / ');
}

/// Siglas usadas num conjunto de linhas, na ordem da legenda.
List<(String, String)> legendFor(Iterable<BudgetItem> items) {
  final used = <String>{};
  for (final it in items) {
    used.addAll(opCode(it.op, it.labFlag, it.paintFlag,
            removeInstall: it.removeInstall, alsoRepair: it.alsoRepair)
        .split(' / '));
  }
  return [for (final e in opLegend) if (used.contains(e.$1)) e];
}

/// Nome das operações sem horas, ex.: "Troca + pintura".
String opNames(ItemOp op, double laborHours, double paintHours,
    {bool removeInstall = false, bool alsoRepair = false}) {
  if (op == ItemOp.servico) return 'Serviço';
  final parts = <String>[
    if (op == ItemOp.troca) 'Troca',
    if (op != ItemOp.troca && laborHours > 0 && removeInstall)
      'Remoção e instalação',
    if (op != ItemOp.troca && laborHours > 0 && (!removeInstall || alsoRepair))
      'Reparo',
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
    {bool removeInstall = false, bool alsoRepair = false, bool perPiece = false}) {
  if (op == ItemOp.servico) return ['Serviço'];
  if (perPiece) {
    final n = opNames(op, laborHours, paintHours,
        removeInstall: removeInstall, alsoRepair: alsoRepair);
    return [...n.split(' + ').map((e) => e[0].toUpperCase() + e.substring(1)), 'Por peça'];
  }
  return [
    if (op == ItemOp.troca) 'Troca',
    if (laborHours > 0)
      op == ItemOp.troca
          ? 'Mão de obra ${_h(laborHours)}'
          : (removeInstall
              ? (alsoRepair
                  ? 'R&I + reparo ${_h(laborHours)}'
                  : 'Remoção e instalação ${_h(laborHours)}')
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
    if (it.op == ItemOp.servico || it.parentId.isNotEmpty || it.perPiece) {
      out.add(it);
      continue;
    }
    final key = it.description.trim().toLowerCase();
    BudgetItem? same;
    for (final o in out) {
      if (o.op != ItemOp.servico &&
          o.parentId.isEmpty &&
          !o.perPiece &&
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
    if (same.removeInstall != it.removeInstall && same.op != ItemOp.troca) {
      same.alsoRepair = true;
    }
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
  funcionario('Funcionários e terceirizados'),
  materiais('Materiais'),
  impostos('Impostos e taxas'),
  outros('Outros');

  const ExpenseCategory(this.label);
  final String label;
}

/// Forma de pagamento de funcionário ou terceirizado.
enum PayType {
  salario('Salário'),
  empreita('Empreita'),
  porPeca('Por peça');

  const PayType(this.label);
  final String label;
}

/// Serviço feito por terceirizado (e função de quem trabalha no carro).
enum OutsourcedService {
  funilaria('Funilaria', 'Funileiro'),
  pintura('Pintura', 'Pintor'),
  martelinho('Martelinho de ouro', 'Martelinho de ouro'),
  mecanica('Mecânica', 'Mecânico'),
  eletrica('Elétrica', 'Eletricista'),
  polimento('Polimento', 'Polidor'),
  tapecaria('Tapeçaria', 'Tapeceiro'),
  vidracaria('Vidraçaria', 'Vidraceiro'),
  outros('Outros', 'Outro serviço');

  const OutsourcedService(this.label, this.worker);
  final String label;

  /// Nome da função de quem faz (Pintor, Funileiro…).
  final String worker;
}

/// Itens conferidos na entrada do carro.
const receptionItems = [
  'Estepe',
  'Macaco',
  'Chave de roda',
  'Triângulo',
  'Rádio / multimídia',
  'Tapetes',
  'Antena',
  'Calotas',
  'Documento (CRLV)',
  'Manual',
  'Chave reserva',
  'Objetos pessoais',
];

/// Nível de combustível na entrada.
const fuelLevels = ['Reserva', '1/4', '1/2', '3/4', 'Cheio'];

/// Checklist de entrada do veículo.
class Reception {
  int fuel; // -1 = não informado; 0..4 = fuelLevels
  Set<String> items; // itens que estavam no carro
  String notes;
  DateTime? at;

  Reception({this.fuel = -1, Set<String>? items, this.notes = '', this.at})
      : items = items ?? {};

  bool get isEmpty => fuel < 0 && items.isEmpty && notes.isEmpty && at == null;

  String get fuelLabel => fuel >= 0 && fuel < fuelLevels.length ? fuelLevels[fuel] : '';

  Map<String, dynamic> toJson() => {
        'fuel': fuel,
        'items': items.toList(),
        'notes': notes,
        'at': at?.toIso8601String(),
      };

  factory Reception.fromJson(Map<String, dynamic> j) => Reception(
        fuel: _d(j['fuel'], -1).round(),
        items: {
          if (j['items'] is List)
            for (final e in j['items'] as List) e.toString()
        },
        notes: _s(j['notes']),
        at: _dt(j['at']),
      );
}

/// Resumo do checklist de entrada para o PDF e a pré-visualização.
List<String> receptionLines(Claim c) {
  final r = c.reception;
  String two(int n) => n.toString().padLeft(2, '0');
  return [
    [
      if (r.at != null)
        'Entrada: ${two(r.at!.day)}/${two(r.at!.month)}/${r.at!.year} ${two(r.at!.hour)}:${two(r.at!.minute)}',
      if (r.fuelLabel.isNotEmpty) 'Combustível: ${r.fuelLabel}',
      if (c.vehicle.km.trim().isNotEmpty) 'Km: ${c.vehicle.km.trim()}',
    ].join('   '),
    if (r.items.isNotEmpty)
      'No veículo: ${[for (final i in receptionItems) if (r.items.contains(i)) i].join(', ')}',
    if (r.notes.trim().isNotEmpty) 'Obs.: ${r.notes.trim()}',
  ].where((e) => e.isNotEmpty).toList();
}

/// Insumo usado numa O.S. (sai do estoque, entra no custo real).
class SupplyUse {
  String id;
  String stockId;
  String name; // nome no momento da saída
  double qty;
  String unit;
  double unitCost;
  String itemId; // peça do orçamento em que foi usado (opcional)
  String workerId; // funcionário que recebeu (cadastro)
  String workerName; // nome no momento da saída
  DateTime date;
  String note;

  SupplyUse({
    String? id,
    this.stockId = '',
    this.name = '',
    this.qty = 1,
    this.unit = 'un',
    this.unitCost = 0,
    this.itemId = '',
    this.workerId = '',
    this.workerName = '',
    DateTime? date,
    this.note = '',
  })  : id = id ?? newId(),
        date = date ?? DateTime.now();

  double get total => qty * unitCost;

  Map<String, dynamic> toJson() => {
        'id': id,
        'stock': stockId,
        'name': name,
        'qty': qty,
        'unit': unit,
        'cost': unitCost,
        'item': itemId,
        if (workerId.isNotEmpty) 'worker': workerId,
        if (workerName.isNotEmpty) 'workerName': workerName,
        'date': date.toIso8601String(),
        'note': note,
      };

  factory SupplyUse.fromJson(Map<String, dynamic> j) => SupplyUse(
        id: _s(j['id']).isEmpty ? null : _s(j['id']),
        stockId: _s(j['stock']),
        name: _s(j['name']),
        qty: _d(j['qty'], 1),
        unit: _s(j['unit'], 'un'),
        unitCost: _d(j['cost']),
        itemId: _s(j['item']),
        workerId: _s(j['worker']),
        workerName: _s(j['workerName']),
        date: _dt(j['date']),
        note: _s(j['note']),
      );
}

/// Saída de uma peça do estoque para um item do orçamento.
class StockUse {
  final String stockId;
  final double qty;
  const StockUse(this.stockId, this.qty);

  Map<String, dynamic> toJson() => {'s': stockId, 'q': qty};

  factory StockUse.fromJson(Map<String, dynamic> j) =>
      StockUse(_s(j['s']), _d(j['q']));
}

/// Profissional escalado num carro: função, quem é e quanto custa.
/// [pieces] e [rate] nulos = automático (peças do orçamento / valor do cadastro).
class CrewMember {
  String id;
  OutsourcedService role;
  String contactId;
  double? pieces;
  double? rate;

  CrewMember({
    String? id,
    this.role = OutsourcedService.pintura,
    this.contactId = '',
    this.pieces,
    this.rate,
  }) : id = id ?? newId();

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role.name,
        'contact': contactId,
        if (pieces != null) 'pieces': pieces,
        if (rate != null) 'rate': rate,
      };

  factory CrewMember.fromJson(Map<String, dynamic> j) => CrewMember(
        id: _s(j['id']).isEmpty ? null : _s(j['id']),
        role: _enum(OutsourcedService.values, j['role'], OutsourcedService.outros),
        contactId: _s(j['contact']),
        pieces: j['pieces'] == null ? null : _d(j['pieces']),
        rate: j['rate'] == null ? null : _d(j['rate']),
      );
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

  // Funcionários e terceirizados
  bool outsourced; // terceirizado (prestador de fora)
  OutsourcedService service;
  PayType payType;
  double pieces; // quantidade de peças (pagamento por peça)
  double pieceValue; // valor de cada peça

  /// Lançamento gerado pelo app (ex.: 'pintor'); vazio = lançado à mão.
  String autoKey;

  /// Foto da nota/recibo (arquivo na pasta de fotos).
  String receiptFile;

  /// Nº da nota / fatura / pedido e forma de pagamento.
  String invoiceNumber;
  String paymentMethod;

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
    this.outsourced = false,
    this.service = OutsourcedService.funilaria,
    this.payType = PayType.salario,
    this.pieces = 0,
    this.pieceValue = 0,
    this.autoKey = '',
    this.receiptFile = '',
    this.invoiceNumber = '',
    this.paymentMethod = '',
  })  : id = id ?? newId(),
        date = date ?? DateTime.now();

  String get categoryLabel => isIncome ? 'Outras receitas' : category.label;

  bool get isWorker => !isIncome && category == ExpenseCategory.funcionario;

  /// Ex.: "Terceirizado · Funilaria" ou "Por peça".
  String get workerLabel => !isWorker
      ? ''
      : outsourced
          ? 'Terceirizado · ${service.label}'
          : payType.label;

  /// Pagamento por peça (valor = peças × valor da peça).
  bool get paidByPiece => isWorker && payType == PayType.porPeca;

  /// Recalcula o valor quando o pagamento é por peça.
  void syncPieceAmount() {
    if (paidByPiece) amount = pieces * pieceValue;
  }

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
        'outsourced': outsourced,
        'service': service.name,
        'payType': payType.name,
        'pieces': pieces,
        'pieceValue': pieceValue,
        'auto': autoKey,
        'receipt': receiptFile,
        'invoice': invoiceNumber,
        'payment': paymentMethod,
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
        outsourced: j['outsourced'] == true,
        service: _enum(OutsourcedService.values, j['service'],
            OutsourcedService.funilaria),
        payType: _enum(PayType.values, j['payType'], PayType.salario),
        pieces: _d(j['pieces']),
        pieceValue: _d(j['pieceValue']),
        autoKey: _s(j['auto']),
        receiptFile: _s(j['receipt']),
        invoiceNumber: _s(j['invoice']),
        paymentMethod: _s(j['payment']),
      );
}
