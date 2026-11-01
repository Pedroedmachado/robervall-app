/// Qual sistema este código é. O Funilar completo e os três sistemas
/// separados (Orçamentação, Cadastro de clientes e Gestão de oficina) usam
/// o mesmo motor; cada repositório fixa a sua edição em [appEdition].
library;

import 'modules.dart';

/// Páginas do menu principal.
enum AppPage { painel, sinistros, financeiro, estoque, catalogo, cadastros, ajustes }

enum Edition {
  completo(
    title: 'Funilar',
    package: 'funilar',
    repo: 'Pedroedmachado/robervall-app',
    asset: 'Funilar',
    tagline: 'orçamentos, vistorias e sinistros para oficinas',
  ),
  orcamentacao(
    title: 'Funilar Orçamentos',
    package: 'orcamentacao',
    repo: 'Pedroedmachado/orcamentacao',
    asset: 'Orcamentacao',
    tagline: 'orçamentos, vistorias e sinistros',
  ),
  cadastros(
    title: 'Funilar Cadastros',
    package: 'cadastros_cliente',
    repo: 'Pedroedmachado/cadastros-cliente',
    asset: 'Cadastros',
    tagline: 'cadastro de clientes, seguradoras, fornecedores e equipe',
  ),
  gestao(
    title: 'Funilar Gestão',
    package: 'gestao_oficina',
    repo: 'Pedroedmachado/gestao-oficina',
    asset: 'Gestao',
    tagline: 'gestão da oficina: O.S., estoque, equipe e financeiro',
  );

  const Edition({
    required this.title,
    required this.package,
    required this.repo,
    required this.asset,
    required this.tagline,
  });

  /// Nome que aparece na janela, no celular e no PDF.
  final String title;

  /// Nome do pacote, do executável (`<package>.exe`) e da pasta de dados.
  final String package;

  /// Repositório no GitHub (versões e atualização).
  final String repo;

  /// Prefixo dos arquivos publicados (`<asset>-windows-x64.zip`…).
  final String asset;
  final String tagline;

  /// Módulos que este sistema traz ligados.
  Set<Mod> get modules => switch (this) {
        Edition.completo || Edition.gestao => Mod.values.toSet(),
        Edition.orcamentacao => {Mod.nucleo, Mod.vistoria, Mod.integracoes},
        Edition.cadastros => {Mod.nucleo},
      };

  /// Páginas do menu deste sistema.
  Set<AppPage> get pages => switch (this) {
        Edition.completo || Edition.gestao => AppPage.values.toSet(),
        Edition.orcamentacao => {
            AppPage.painel,
            AppPage.sinistros,
            AppPage.catalogo,
            AppPage.cadastros,
            AppPage.ajustes,
          },
        Edition.cadastros => {AppPage.cadastros, AppPage.ajustes},
      };

  /// Nome da lista de carros no menu.
  String get claimsLabel => this == Edition.gestao ? 'Carros' : 'Sinistros';

  /// Ajustes de valores e orçamento só fazem sentido onde há orçamento.
  bool get hasBudget => pages.contains(AppPage.sinistros);
}

/// Edição fixada por este repositório (o gerador dos módulos troca esta linha).
const Edition appEdition = Edition.completo;

/// Edição em uso. É sempre [appEdition] no app; os testes do motor
/// compartilhado podem trocar para conferir cada sistema.
Edition edition = appEdition;

/// Backups de qualquer um dos sistemas podem ser restaurados em outro.
const backupAppIds = {'funilar', 'robervall', 'orcamentacao', 'cadastros_cliente', 'gestao_oficina'};
