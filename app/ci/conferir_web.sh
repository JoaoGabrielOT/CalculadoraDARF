#!/usr/bin/env bash
# Confere a Web publicada: version.json nas duas URLs e o CORS da API da Vercel.
# Uso: conferir_web.sh <versao> <url_vercel> <url_render> [--sem-api]
# TENTATIVAS (padrão 20) e ESPERA em segundos (padrão 30) cobrem o tempo de deploy das duas plataformas.
set -uo pipefail

if [ "$#" -lt 3 ] || [ "$#" -gt 4 ] || { [ "$#" = 4 ] && [ "$4" != "--sem-api" ]; }; then
  echo "Uso: $0 <versao> <url_vercel> <url_render> [--sem-api]" >&2
  exit 2
fi
VERSAO="$1"; URL_VERCEL="${2%/}"; URL_RENDER="${3%/}"; SEM_API="${4:-}"
TENTATIVAS="${TENTATIVAS:-20}"; ESPERA="${ESPERA:-30}"
API="$URL_VERCEL/api/yahoo/chart/PETR4.SA?range=5d&interval=1d"

versao_de() {
  curl -fsS --max-time 20 -H 'Cache-Control: no-cache' "$1/version.json?t=$(date +%s)" 2>/dev/null \
    | tr -d '\r\n' | sed -nE 's/.*"version" *: *"([^"]*)".*/\1/p'
}

# devolve vazio quando tudo confere; senão, o motivo
conferir() {
  local v url
  for url in "$URL_VERCEL" "$URL_RENDER"; do
    v="$(versao_de "$url")"
    [ "$v" = "$VERSAO" ] || { echo "$url/version.json com version '$v' (esperado $VERSAO)"; return; }
  done
  [ "$SEM_API" = "--sem-api" ] && return
  local cabecalhos codigo origem
  cabecalhos="$(mktemp)"
  codigo="$(curl -sS --max-time 30 -o /dev/null -D "$cabecalhos" -w '%{http_code}' -H "Origin: $URL_RENDER" "$API" 2>/dev/null)"
  origem="$(tr -d '\r' < "$cabecalhos" | sed -nE 's/^[Aa]ccess-[Cc]ontrol-[Aa]llow-[Oo]rigin: *(.*)$/\1/p' | tail -n 1)"
  rm -f "$cabecalhos"
  [ "$codigo" = 200 ] || { echo "API com Origin $URL_RENDER respondeu $codigo (esperado 200)"; return; }
  [ "$origem" = "$URL_RENDER" ] || { echo "access-control-allow-origin '$origem' (esperado $URL_RENDER)"; return; }
  codigo="$(curl -sS --max-time 30 -o /dev/null -w '%{http_code}' "$API" 2>/dev/null)"
  [ "$codigo" = 403 ] || { echo "API sem Origin nem Referer respondeu $codigo (esperado 403)"; return; }
}

for i in $(seq 1 "$TENTATIVAS"); do
  motivo="$(conferir)"
  if [ -z "$motivo" ]; then
    echo "::notice title=Web::versão $VERSAO em $URL_VERCEL e $URL_RENDER${SEM_API:+ (sem conferir a API)}"
    exit 0
  fi
  echo "tentativa $i/$TENTATIVAS: $motivo"
  [ "$i" = "$TENTATIVAS" ] || sleep "$ESPERA"
done
echo "::error title=Web::$motivo"
exit 1
