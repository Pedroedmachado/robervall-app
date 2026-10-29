#!/usr/bin/env bash
# Gera as pastas de plataforma (android/, ios/, linux/, windows/) que faltarem e
# aplica os ajustes do Funilar. Pode rodar quantas vezes quiser.
set -euo pipefail
cd "$(dirname "$0")/.."

flutter create --platforms=android,ios,linux,windows --org br.com.funilar --project-name funilar . >/dev/null
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

# Android: o leitor de notas (ML Kit) cita idiomas que não usamos
if [ -d android/app ]; then
  rules=android/app/proguard-rules.pro
  touch "$rules"
  for lang in chinese devanagari japanese korean; do
    grep -q "mlkit.vision.text.$lang" "$rules" || echo "-dontwarn com.google.mlkit.vision.text.$lang.**" >> "$rules"
  done
fi

# Linux: título da janela
if [ -f linux/runner/my_application.cc ]; then
  sed -i.bak 's#"funilar"#"Funilar"#g' linux/runner/my_application.cc && rm -f linux/runner/my_application.cc.bak
fi
# Windows: título da janela
if [ -f windows/runner/main.cpp ]; then
  sed -i.bak 's#L"funilar"#L"Funilar"#g' windows/runner/main.cpp && rm -f windows/runner/main.cpp.bak
fi
# iOS: leitor de notas (ML Kit) exige iOS 15.5 ou mais novo
if [ -f ios/Podfile ]; then
  sed -i.bak -E "s/^#? *platform :ios, '[0-9.]+'/platform :ios, '15.5'/" ios/Podfile && rm -f ios/Podfile.bak
  grep -q "^platform :ios, '15.5'" ios/Podfile || sed -i.bak "1s/^/platform :ios, '15.5'\n/" ios/Podfile
  rm -f ios/Podfile.bak
fi
if [ -f ios/Runner.xcodeproj/project.pbxproj ]; then
  sed -i.bak -E 's/IPHONEOS_DEPLOYMENT_TARGET = [0-9.]+;/IPHONEOS_DEPLOYMENT_TARGET = 15.5;/g' ios/Runner.xcodeproj/project.pbxproj && rm -f ios/Runner.xcodeproj/project.pbxproj.bak
fi
if [ -f ios/Flutter/AppFrameworkInfo.plist ]; then
  sed -i.bak -E 's#<string>1[0-9]\.[0-9]+</string>#<string>15.5</string>#' ios/Flutter/AppFrameworkInfo.plist && rm -f ios/Flutter/AppFrameworkInfo.plist.bak
fi

# iOS: nome do app, permissões de câmera/fotos e acesso aos arquivos
plist=ios/Runner/Info.plist
if [ -f "$plist" ] && [ -x /usr/libexec/PlistBuddy ]; then
  pb() { /usr/libexec/PlistBuddy -c "Set :$1 $3" "$plist" 2>/dev/null || /usr/libexec/PlistBuddy -c "Add :$1 $2 $3" "$plist"; }
  pb CFBundleDisplayName string "Funilar"
  pb CFBundleName string "Funilar"
  pb NSCameraUsageDescription string "Usada para fotografar as avarias e o veículo."
  pb NSPhotoLibraryUsageDescription string "Usada para anexar fotos do veículo aos orçamentos."
  pb NSPhotoLibraryAddUsageDescription string "Usada para salvar fotos do veículo."
  pb UIFileSharingEnabled bool true
  pb LSSupportsOpeningDocumentsInPlace bool true
  echo "Info.plist:"; /usr/libexec/PlistBuddy -c "Print" "$plist" | grep -E "DisplayName|UsageDescription|FileSharing"
fi
echo "Plataformas prontas."
