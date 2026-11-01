#!/usr/bin/env bash
# Gera (ou atualiza) um dos sistemas separados a partir do Funilar completo.
#
#   bash tool/gerar_modulos.sh orcamentacao ../orcamentacao
#   bash tool/gerar_modulos.sh cadastros    ../cadastros-cliente
#   bash tool/gerar_modulos.sh gestao       ../gestao-oficina
#
# Copia o código, fixa a edição, troca o nome do pacote, do app, dos arquivos
# publicados e do repositório. A pasta .git do destino é mantida.
set -euo pipefail
src="$(cd "$(dirname "$0")/.." && pwd)"
ed="${1:?edição: orcamentacao | cadastros | gestao}"
dest="${2:?pasta de destino}"

case "$ed" in
  orcamentacao)
    pkg=orcamentacao; title='Funilar Orçamentos'; title_w='Funilar Or\\u00e7amentos'
    asset=Orcamentacao; repo=Pedroedmachado/orcamentacao
    about='Orçamentos, vistorias e sinistros: dados do carro e do cliente, mapa de avarias, fotos, orçamento (troca, reparo, pintura, R&I, mão de obra por hora ou por peça), catálogo, consulta FIPE, busca no Mercado Livre e PDF.'
    ;;
  cadastros)
    pkg=cadastros_cliente; title='Funilar Cadastros'; title_w='Funilar Cadastros'
    asset=Cadastros; repo=Pedroedmachado/cadastros-cliente
    about='Cadastro de clientes, seguradoras, reguladores/peritos, fornecedores e funcionários, com busca, telefone e documento, backup e atualização.'
    ;;
  gestao)
    pkg=gestao_oficina; title='Funilar Gestão'; title_w='Funilar Gest\\u00e3o'
    asset=Gestao; repo=Pedroedmachado/gestao-oficina
    about='Gestão da oficina: carros e O.S. (recepção com checklist, tarefas, insumos liberados por funcionário, custo real), estoque com endereço e fotos, equipe (pintor, funileiro, martelinho…), financeiro com vendas, caixa e resultado por funcionário.'
    ;;
  *) echo "edição desconhecida: $ed"; exit 1 ;;
esac

mkdir -p "$dest"
# limpa o destino (menos o .git) e copia os arquivos do Funilar
find "$dest" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
(cd "$src" && git ls-files -co --exclude-standard -z | tar --null -T - -cf -) | (cd "$dest" && tar -xf -)
rm -f "$dest/.github/workflows/licenca.yml" "$dest/tool/licenca.dart" "$dest/tool/gerar_modulos.sh"
cd "$dest"

# edição fixa e nome do pacote
sed -i "s/^const Edition appEdition = Edition\.completo;/const Edition appEdition = Edition.$ed;/" lib/edition.dart
grep -q "appEdition = Edition.$ed;" lib/edition.dart
sed -i "s/^name: funilar$/name: $pkg/; s/^description: .*/description: $title - $(echo "$about" | sed 's/[&/\]/\\&/g')/" pubspec.yaml
grep -rl 'package:funilar/' lib test tool 2>/dev/null | xargs -r sed -i "s#package:funilar/#package:$pkg/#g"

# nome do app nos builds
cat > tool/app.env <<EOF
APP_PACKAGE=$pkg
APP_TITLE='$title'
APP_ASSET=$asset
APP_ORG=br.com.funilar
APP_TITLE_W='$title_w'
EOF

# instalador do Windows
mv tool/atualizar-funilar.ps1 "tool/atualizar-$pkg.ps1"
sed -i "s#Pedroedmachado/robervall-app/main/tool/atualizar-funilar.ps1#$repo/main/tool/atualizar-$pkg.ps1#; \
  s#'Pedroedmachado/robervall-app'#'$repo'#; \
  s#'funilar.exe'#'$pkg.exe'#; \
  s#Get-Process funilar#Get-Process $pkg#g; \
  s#Funilar-windows-x64.zip#$asset-windows-x64.zip#g; \
  s#Funilar-novo#$asset-novo#g; \
  s#'Funilar.lnk'#'@@T@@.lnk'#; \
  s#'Funilar - orçamentos e sinistros'#'@@T@@'#; \
  s#\\\\Funilar#\\\\$asset#g; \
  s#'Funilar'#'$asset'#g; \
  s#Funilar#$title#g; \
  s#@@T@@#$title#g" "tool/atualizar-$pkg.ps1"

cat > README.md <<EOF
# $title

$about

Faz parte da família **Funilar**: o Funilar completo (repositório \`robervall-app\`) junta tudo;
este sistema traz só a sua parte e funciona sozinho, com os próprios dados.
Android, iPhone, Windows e Linux (Flutter). Funciona offline; os dados ficam no aparelho.

## Baixar
Cada push na \`main\` compila no GitHub Actions e publica em **Releases**:
\`$asset-android.apk\`, \`$asset-windows-x64.zip\`, \`$asset-linux-x64.tar.gz\`
(iPhone: \`[ios]\` na mensagem do commit gera \`$asset-ios-sem-assinatura.ipa\`).

No Windows, para instalar ou atualizar pelo PowerShell:
\`\`\`powershell
irm https://raw.githubusercontent.com/$repo/main/tool/atualizar-$pkg.ps1 | iex
\`\`\`
Dentro do app: **Ajustes › Atualizações**.

## Backup entre os sistemas
O backup (.zip) de qualquer sistema Funilar pode ser restaurado em outro —
por exemplo, levar os cadastros para o Funilar completo.

## Compilar na sua máquina
\`\`\`bash
bash tool/prepare_platforms.sh   # gera android/, ios/, linux/, windows/
flutter pub get
flutter test
flutter run
\`\`\`

## Código
Este repositório é gerado a partir do Funilar completo
(\`bash tool/gerar_modulos.sh $ed <pasta>\` no \`robervall-app\`), por isso as correções
feitas lá chegam aqui na próxima geração.
EOF

# .gitignore das pastas geradas
cat > .gitignore <<'EOF'
.dart_tool/
build/
coverage/
ci/
android/
ios/
linux/
windows/
macos/
web/
pubspec.lock
.flutter-plugins
.flutter-plugins-dependencies
*.iml
.idea/
EOF
echo "Pronto: $title em $dest"
