#!/usr/bin/env bash
# Monta a pasta publicada na branch web-dist: o build Web mais as funções da Vercel (api/, vercel.json, package.json).
# Uso: montar_web.sh <build_web> <servidor> <saida>
# A <saida> é recriada; falha se houver credentials*.json ou o valor de um segredo OAuth (GOCSPX-) nela.
set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "Uso: $0 <build_web> <servidor> <saida>" >&2
  exit 2
fi
BUILD="$1"; SERVIDOR="$2"; SAIDA="$3"

erro() { echo "::error title=Web::$1"; exit 1; }

[ -f "$BUILD/index.html" ] || erro "$BUILD/index.html ausente (rode flutter build web)"
for item in api vercel.json package.json; do
  [ -e "$SERVIDOR/$item" ] || erro "$SERVIDOR/$item ausente"
done
[ ! -e "$BUILD/api" ] || erro "$BUILD/api já existe e se misturaria com as funções"

rm -rf "$SAIDA"
mkdir -p "$SAIDA"
cp -R "$BUILD/." "$SAIDA/"
rm -f "$SAIDA/.last_build_id"
# só o que o site e as funções usam: test/ e node_modules ficam de fora
cp -R "$SERVIDOR/api" "$SAIDA/api"
cp "$SERVIDOR/vercel.json" "$SERVIDOR/package.json" "$SAIDA/"

# a palavra client_secret aparece no JS compilado; o que não pode ir é o valor nem o arquivo de credencial
credenciais="$(find "$SAIDA" -name 'credentials*.json' | head -n 5 | tr '\n' ' ')"
[ -z "$credenciais" ] || erro "arquivo de credencial na saída: $credenciais"
segredos="$(grep -rl -- 'GOCSPX-' "$SAIDA" | head -n 5 | tr '\n' ' ' || true)"
[ -z "$segredos" ] || erro "segredo OAuth (GOCSPX-) na saída: $segredos"

n=$(find "$SAIDA" -type f | wc -l | tr -d ' ')
echo "Saída Web montada em $SAIDA ($n arquivos)"
