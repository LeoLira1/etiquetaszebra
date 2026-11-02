#!/usr/bin/env bash
# Gera o projeto Android (flutter create num diretorio temporario, copia so android/)
# e ajusta nome do app e permissoes. Usado pelo CI e para compilar na maquina.
# Mesma ideia do Gondolas/Risca: nenhum binario (gradle-wrapper.jar) entra no repositorio.
set -euo pipefail

TMP="${TMPDIR:-/tmp}/etiquetas_scaffold"
rm -rf "$TMP"
flutter create --org com.camda --project-name etiquetas_camda "$TMP"

MANIFEST="$TMP/android/app/src/main/AndroidManifest.xml"

# Nome na tela inicial.
sed -i 's/android:label="etiquetas_camda"/android:label="Etiquetas CAMDA"/' "$MANIFEST"

# Rede (Turso, a partir da fase 2). Sem INTERNET o DNS falha em release.
grep -q 'android.permission.INTERNET' "$MANIFEST" || \
  sed -i 's|<application|<uses-permission android:name="android.permission.INTERNET"/>\n    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>\n    <application|' "$MANIFEST"

# Bluetooth: BLUETOOTH, BLUETOOTH_ADMIN (ate o Android 11), BLUETOOTH_CONNECT e BLUETOOTH_SCAN
# (Android 12+) ja vem do plugin pelo merge do manifesto. Declaramos aqui tambem, de forma explicita,
# para o permission_handler enxergar no manifesto do app.
grep -q 'android.permission.BLUETOOTH_CONNECT' "$MANIFEST" || \
  sed -i 's|<application|<uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30"/>\n    <uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30"/>\n    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT"/>\n    <uses-permission android:name="android.permission.BLUETOOTH_SCAN"/>\n    <application|' "$MANIFEST"

# O plugin Bluetooth (flutter_bluetooth_classic_serial) ainda compila contra o Android 33 e o
# Gradle recusa ("checkReleaseAarMetadata"). Sobe o compileSdk dos modulos de plugin (so afeta a
# compilacao, nao muda o comportamento nem o targetSdk do app). O bloco entra ANTES do
# `evaluationDependsOn(":app")` do template, senao o afterEvaluate chega tarde demais.
python3 - "$TMP/android/build.gradle.kts" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
bloco = """subprojects {
    afterEvaluate {
        if (project.name != "app") {
            project.extensions.findByName("android")?.withGroovyBuilder {
                setProperty("compileSdk", 36)
            }
        }
    }
}
"""
marca = "subprojects {\n    project.evaluationDependsOn"
assert marca in s, "template do Gradle mudou: ajuste tool/preparar_android.sh"
open(p, "w").write(s.replace(marca, bloco + marca, 1))
PY

rm -rf android
cp -r "$TMP/android" .
echo "Projeto Android gerado."
