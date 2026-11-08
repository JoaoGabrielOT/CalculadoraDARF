#!/usr/bin/env bash
# Confere o APK novo contra o esperado e contra o publicado (mesmo pacote, versionCode maior, mesma assinatura).
# Uso: conferir_apk.sh <novo.apk> <versionCode esperado> <anterior.apk> [tag|branch]
# Em execução por tag (padrão) o versionCode precisa ser maior que o publicado; em push de branch ou
# workflow_dispatch ("branch") basta ser maior ou igual, e igual vira aviso.
set -euo pipefail

if [ "$#" -lt 3 ] || [ "$#" -gt 4 ]; then
  echo "Uso: $0 <novo.apk> <versionCode esperado> <anterior.apk> [tag|branch]" >&2
  exit 2
fi
NOVO="$1"; ESPERADO="$2"; ANTERIOR="$3"; MODO="${4:-tag}"
if [ "$MODO" != "tag" ] && [ "$MODO" != "branch" ]; then
  echo "Modo inválido: $MODO (use tag ou branch)" >&2
  exit 2
fi

BT="$(ls -d "${ANDROID_HOME:?ANDROID_HOME não definido}"/build-tools/*/ | sort -V | tail -n 1)"
AAPT2="${BT}aapt2"
APKSIGNER="${BT}apksigner"

falhou=0
ok() { echo "OK $1"; echo "::notice title=APK::OK $1"; }
erro() { echo "ERRO $1: $2"; echo "::error title=APK::ERRO $1: $2"; falhou=1; }

badging_novo="$("$AAPT2" dump badging "$NOVO")"
badging_ant="$("$AAPT2" dump badging "$ANTERIOR")"
pacote_de() { echo "$1" | sed -nE "s/^package: name='([^']*)'.*/\1/p" | head -n 1; }
codigo_de() { echo "$1" | sed -nE "s/^package:.* versionCode='([^']*)'.*/\1/p" | head -n 1; }

# 1. pacote e versionCode
pacote="$(pacote_de "$badging_novo")"
codigo="$(codigo_de "$badging_novo")"
if [ "$pacote" = "io.github.joaogabrielot.calculadoradarf" ]; then ok "package $pacote"; else erro "package" "$pacote"; fi
if [ "$codigo" = "$ESPERADO" ]; then ok "versionCode $codigo"; else erro "versionCode" "$codigo (esperado $ESPERADO)"; fi

# 2. ABIs
abis="$(echo "$badging_novo" | sed -nE "s/^native-code: (.*)$/\1/p" | head -n 1)"
if [ "$abis" = "'arm64-v8a' 'armeabi-v7a'" ]; then ok "ABIs $abis"; else
  erro "ABIs" "$abis"
  # quais bibliotecas nativas trouxeram ABIs a mais
  extras="$(unzip -l "$NOVO" | awk '{print $4}' | grep -E '^lib/(x86|x86_64|mips)' | head -n 8 | tr '
' ' ' || true)"
  echo "::notice title=APK::bibliotecas de ABIs extras: $extras"
fi

# 3. o res/raw/keep.xml sobreviveu ao shrinkResources
recursos="$("$AAPT2" dump resources "$NOVO")"  # em variável: grep -q fecharia o pipe (SIGPIPE) sob pipefail
if grep -q "drawable/ic_notificacao" <<< "$recursos"; then
  ok "drawable/ic_notificacao presente"
else
  erro "drawable/ic_notificacao" "ausente"
fi

# 4. mesmo pacote do publicado e versionCode maior (ou igual fora de tag)
pacote_ant="$(pacote_de "$badging_ant")"
codigo_ant="$(codigo_de "$badging_ant")"
if [ "$pacote_ant" = "$pacote" ]; then ok "mesmo pacote do publicado"; else erro "pacote do publicado" "$pacote_ant"; fi
if [ -z "$codigo" ] || [ -z "$codigo_ant" ]; then
  erro "versionCode maior que o publicado" "novo=$codigo anterior=$codigo_ant"
elif [ "$codigo" -gt "$codigo_ant" ]; then
  ok "versionCode $codigo maior que o publicado ($codigo_ant)"
elif [ "$MODO" = "branch" ] && [ "$codigo" -eq "$codigo_ant" ]; then
  echo "::warning title=APK::versionCode $codigo igual ao publicado (execução de branch, sem publicar)"
  ok "versionCode $codigo igual ao publicado ($codigo_ant), aceito fora de tag"
else
  erro "versionCode maior que o publicado" "novo=$codigo anterior=$codigo_ant"
fi

# 5. mesma assinatura
sha_de() { "$APKSIGNER" verify --print-certs "$1" | sed -nE 's/.*certificate SHA-256 digest: *([0-9a-fA-F]+).*/\1/p' | head -n 1; }
sha_novo="$(sha_de "$NOVO")"
sha_ant="$(sha_de "$ANTERIOR")"
if [ -n "$sha_novo" ] && [ "$sha_novo" = "$sha_ant" ]; then
  ok "certificado SHA-256 igual ao publicado ($sha_novo)"
else
  erro "certificado SHA-256" "novo=$sha_novo anterior=$sha_ant"
fi

exit "$falhou"
