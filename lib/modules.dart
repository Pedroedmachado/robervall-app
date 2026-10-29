/// Módulos do Funilar, permissões por papel e a checagem central
/// (licença → ativação local → permissão do usuário).
library;

/// Módulos que a licença pode autorizar. O núcleo (sinistros, cadastros,
/// orçamento, PDF, ajustes e backup) é sempre ativo.
enum Mod {
  nucleo('Núcleo', 'Sinistros, cadastros, orçamento, PDF, ajustes e backup.'),
  vistoria('Vistoria',
      'Mapa de avarias, avarias pré-existentes, fotos e checklist de entrada.'),
  financeiro('Financeiro',
      'Fluxo de caixa, gastos, receitas e lucro do mês.'),
  ocr('Leitura de nota',
      'Lê a foto da nota no celular e preenche o gasto sozinho.'),
  equipe('Equipe do carro',
      'Pintor, funileiro, martelinho… e o custo de cada um por carro.'),
  estoque('Estoque',
      'Peças, insumos, peças de cliente, endereço e baixa ao aprovar.'),
  producao('Produção (O.S.)',
      'Ordem de serviço com tarefas, insumos liberados e custo real.'),
  integracoes('Integrações online',
      'Consulta FIPE e busca de peças no Mercado Livre.');

  const Mod(this.label, this.description);
  final String label;
  final String description;

  /// Precisa destes módulos ligados para funcionar.
  List<Mod> get requires => switch (this) {
        Mod.ocr => const [Mod.financeiro],
        Mod.producao => const [Mod.estoque],
        _ => const [],
      };

  /// Fica limitado (mas funciona) sem estes módulos.
  List<(Mod, String)> get softRequires => switch (this) {
        Mod.equipe => const [
            (Mod.financeiro,
                'sem o Financeiro, o custo da equipe não é lançado sozinho')
          ],
        Mod.vistoria => const [],
        _ => const [],
      };

  /// O que some/para quando o módulo é desligado (análise de impacto).
  List<String> get offEffects => switch (this) {
        Mod.nucleo => const [],
        Mod.vistoria => const [
            'Abas Avarias e Fotos somem dos sinistros',
            'Checklist de entrada e marcação de pré-existentes ficam ocultos',
          ],
        Mod.financeiro => const [
            'Aba Financeiro e o "Lucro do mês" do Painel somem',
            'Não dá para lançar, editar ou excluir gastos e receitas',
          ],
        Mod.ocr => const ['Botões "Ler nota" e "Anexar foto da nota" somem'],
        Mod.equipe => const [
            'Cartão "Equipe do carro" some do orçamento',
            'O custo da equipe para de ser lançado no Financeiro (fica congelado até reativar)',
          ],
        Mod.estoque => const [
            'Aba Estoque e o aviso "Tem no estoque" somem',
            'Baixa e devolução automáticas de peças param (acertadas ao reativar)',
          ],
        Mod.producao => const [
            'Aba O.S. some dos sinistros',
            'Não dá para liberar ou devolver insumos',
          ],
        Mod.integracoes => const [
            'Consulta FIPE e botão Mercado Livre somem',
            'O app não acessa a internet para nada',
          ],
      };

  static Mod? byName(String n) {
    for (final m in Mod.values) {
      if (m.name == n) return m;
    }
    return null;
  }
}

/// Ações que dependem do papel do usuário.
enum Perm {
  valoresVer('Ver valores em R\$'),
  sinistroEditar('Criar e editar sinistros'),
  vistoriaEditar('Vistoria, fotos e checklist'),
  orcamentoEditar('Editar orçamento e catálogo'),
  financeiroVer('Ver o Financeiro'),
  financeiroEditar('Lançar no Financeiro'),
  estoqueVer('Ver o estoque'),
  estoqueEditar('Cadastrar no estoque'),
  insumoLiberar('Liberar insumos'),
  osExecutar('Marcar tarefas da O.S.'),
  equipeEditar('Escalar a equipe do carro'),
  cadastrosEditar('Cadastros (clientes, funcionários…)'),
  ajustes('Ajustes da oficina e backup'),
  usuarios('Usuários e permissões');

  const Perm(this.label);
  final String label;
}

/// Papéis da oficina.
enum Role {
  admin('Administrador da empresa'),
  gestor('Gestor / financeiro'),
  orcamentista('Orçamentista'),
  almoxarife('Almoxarife'),
  producao('Produção');

  const Role(this.label);
  final String label;

  Set<Perm> get perms => switch (this) {
        Role.admin => Perm.values.toSet(),
        Role.gestor => {
            Perm.valoresVer,
            Perm.sinistroEditar,
            Perm.vistoriaEditar,
            Perm.orcamentoEditar,
            Perm.financeiroVer,
            Perm.financeiroEditar,
            Perm.estoqueVer,
            Perm.estoqueEditar,
            Perm.insumoLiberar,
            Perm.osExecutar,
            Perm.equipeEditar,
            Perm.cadastrosEditar,
          },
        Role.orcamentista => {
            Perm.valoresVer,
            Perm.sinistroEditar,
            Perm.vistoriaEditar,
            Perm.orcamentoEditar,
            Perm.estoqueVer,
            Perm.osExecutar,
            Perm.cadastrosEditar,
          },
        Role.almoxarife => {
            Perm.valoresVer,
            Perm.estoqueVer,
            Perm.estoqueEditar,
            Perm.insumoLiberar,
            Perm.osExecutar,
          },
        Role.producao => {Perm.estoqueVer, Perm.osExecutar},
      };

  static Role byName(String n) =>
      Role.values.where((r) => r.name == n).firstOrNull ?? Role.producao;
}

/// Usuário da oficina. O PIN é guardado só como hash (PBKDF2 + sal).
class AppUser {
  String id;
  String name;
  Role role;
  String pinHash; // vazio = sem PIN (só permitido para Produção)
  String salt;
  bool active;

  AppUser({
    required this.id,
    required this.name,
    this.role = Role.producao,
    this.pinHash = '',
    this.salt = '',
    this.active = true,
  });

  bool can(Perm p) => role.perms.contains(p);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'role': role.name,
        'pin': pinHash,
        'salt': salt,
        'active': active,
      };

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: '${j['id'] ?? ''}',
        name: '${j['name'] ?? ''}',
        role: Role.byName('${j['role'] ?? ''}'),
        pinHash: '${j['pin'] ?? ''}',
        salt: '${j['salt'] ?? ''}',
        active: j['active'] != false,
      );
}

/// Tentativa de usar um módulo desligado ou uma ação sem permissão.
class AccessDenied implements Exception {
  AccessDenied(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Checagem central usada pelas telas E pelos serviços.
class ModuleGate {
  /// Módulos autorizados pela licença válida (vazio = sem licença).
  Set<Mod> licensed = {};

  /// Módulos ligados neste aparelho.
  Set<Mod> enabled = {};

  /// Sem licença válida: só consulta, nada é gravado.
  bool readOnly = false;

  /// Usuário atual (null = sem usuários cadastrados → acesso total).
  AppUser? user;

  /// Esperando login (mais de um usuário e ninguém entrou).
  bool locked = false;

  bool active(Mod m) =>
      m == Mod.nucleo || (licensed.contains(m) && enabled.contains(m));

  bool can(Perm p) {
    if (locked) return false;
    if (readOnly && _writes.contains(p)) return false;
    final u = user;
    return u == null || u.can(p);
  }

  /// O papel do usuário permite (sem considerar o modo só consulta). Usado
  /// para mostrar telas; para gravar, use [can].
  bool roleCan(Perm p) {
    if (locked) return false;
    final u = user;
    return u == null || u.can(p);
  }

  /// Módulo ativo e permissão (quando informada).
  bool allows(Mod m, [Perm? p]) => active(m) && (p == null || can(p));

  /// Lança [AccessDenied] se o módulo estiver desligado.
  void require(Mod m) {
    if (!active(m)) {
      throw AccessDenied('O módulo ${m.label} está desativado.');
    }
  }

  /// Lança [AccessDenied] se não puder gravar.
  void requireWrite() {
    if (readOnly) {
      throw AccessDenied(
          'Licença inválida ou ausente: o app está somente para consulta.');
    }
  }

  void requirePerm(Perm p) {
    requireWrite();
    if (!can(p)) {
      throw AccessDenied('Seu usuário não tem permissão: ${p.label}.');
    }
  }

  static const _writes = {
    Perm.sinistroEditar,
    Perm.vistoriaEditar,
    Perm.orcamentoEditar,
    Perm.financeiroEditar,
    Perm.estoqueEditar,
    Perm.insumoLiberar,
    Perm.osExecutar,
    Perm.equipeEditar,
    Perm.cadastrosEditar,
    Perm.ajustes,
    Perm.usuarios,
  };
}

/// Instância única usada pelo app inteiro.
final gate = ModuleGate();
