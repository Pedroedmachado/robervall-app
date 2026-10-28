#!/usr/bin/env bash
# Gera as pastas de plataforma (android/, linux/, windows/) que faltarem e
# aplica os ajustes do Funilar. Pode rodar quantas vezes quiser.
set -euo pipefail
cd "$(dirname "$0")/.."

flutter create --platforms=android,linux,windows --org br.com.funilar --project-name funilar . >/dev/null
rm -f test/widget_test.dart

# Android: internet (consulta FIPE) e nome do app
manifest=android/app/src/main/AndroidManifest.xml
if [ -f "$manifest" ]; then
  if ! grep -q 'android.permission.INTERNET' "$manifest"; then
    sed -i.bak 's#<application#<uses-permission android:name="android.permission.INTERNET"/>\n    <application#' "$manifest"
    rm -f "$manifest.bak"
  fi
  sed -i.bak 's#android:label="[^"]*"#android:label="Funilar"#' "$manifest" && rm -f "$manifest.bak"
  grep -q 'android.permission.INTERNET' "$manifest" || { echo "ERRO: permissão INTERNET não foi aplicada"; exit 1; }
  echo "AndroidManifest:"; grep -E 'uses-permission|android:label' "$manifest"
fi

# Linux: título da janela
if [ -f linux/runner/my_application.cc ]; then
  sed -i.bak 's#"funilar"#"Funilar"#g' linux/runner/my_application.cc && rm -f linux/runner/my_application.cc.bak
fi
# Windows: título da janela
if [ -f windows/runner/main.cpp ]; then
  sed -i.bak 's#L"funilar"#L"Funilar"#g' windows/runner/main.cpp && rm -f windows/runner/main.cpp.bak
fi
echo "Plataformas prontas."
