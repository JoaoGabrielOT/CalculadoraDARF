#!/usr/bin/env bash
# Testa montar_web.sh, publicar_web.sh e conferir_web.sh em pastas temporárias.
# Uso: bash app/ci/testar_ci_web.sh  (PY sobrescreve o Python usado no servidor local)
set -uo pipefail

CI="$(cd "$(dirname "$0")" && pwd)"
RAIZ="$(cd "$CI/../.." && pwd)"
PY="${PY:-$(command -v python3 || command -v python)}"
TMP="$(mktemp -d)"
SERVIDOR_PID=""
encerrar() {
  if [ -n "$SERVIDOR_PID" ]; then kill "$SERVIDOR_PID" 2>/dev/null || true; fi
  rm -rf "$TMP"
}
trap encerrar EXIT

casos=0
falha() { echo "FALHA caso $1: $2"; exit 1; }
passou() { casos=$((casos + 1)); echo "ok caso $1"; }

build_falso() {
  mkdir -p "$1"
  echo '<!doctype html>' > "$1/index.html"
  echo '{"version":"9.9.9"}' > "$1/version.json"
  echo 'x' > "$1/.last_build_id"
}

# 1. montagem: build + api + vercel.json + package.json, sem test/ (client_secret no JS é legítimo)
build_falso "$TMP/b1"
echo 'var c="client_secret";' > "$TMP/b1/main.dart.js"
saida="$TMP/s1"
bash "$CI/montar_web.sh" "$TMP/b1" "$RAIZ/web_servidor" "$saida" > "$TMP/c1.log" 2>&1 \
  || falha 1 "montar_web.sh saiu com erro: $(cat "$TMP/c1.log")"
for f in index.html version.json main.dart.js api/auth/token.js api/_lib/http.js vercel.json package.json; do
  [ -f "$saida/$f" ] || falha 1 "$f ausente na saída"
done
[ ! -e "$saida/test" ] || falha 1 "test/ foi para a saída"
[ ! -e "$saida/.last_build_id" ] || falha 1 ".last_build_id foi para a saída"
passou 1

# 2. credentials.json no build
build_falso "$TMP/b2"
mkdir -p "$TMP/b2/assets/assets/google"
echo '{}' > "$TMP/b2/assets/assets/google/credentials.json"
if bash "$CI/montar_web.sh" "$TMP/b2" "$RAIZ/web_servidor" "$TMP/s2" > "$TMP/c2.log" 2>&1; then
  falha 2 "montar_web.sh aceitou credentials.json"
fi
grep -q '::error' "$TMP/c2.log" || falha 2 "sem ::error: $(cat "$TMP/c2.log")"
passou 2

# 3. valor de segredo OAuth (GOCSPX-) no JS compilado
build_falso "$TMP/b3"
echo 'var s="GOCSPX-abc123";' > "$TMP/b3/main.dart.js"
if bash "$CI/montar_web.sh" "$TMP/b3" "$RAIZ/web_servidor" "$TMP/s3" > "$TMP/c3.log" 2>&1; then
  falha 3 "montar_web.sh aceitou GOCSPX- no main.dart.js"
fi
grep -q '::error' "$TMP/c3.log" || falha 3 "sem ::error: $(cat "$TMP/c3.log")"
passou 3

# 4. publicação (file:// força o clone raso de verdade): dois conteúdos -> 2 commits encadeados; terceiro igual -> continua 2
remoto="$TMP/remoto.git"
git init --quiet --bare "$remoto"
mkdir -p "$TMP/p1" "$TMP/p2"
echo '<p>1</p>' > "$TMP/p1/index.html"; echo 'velho' > "$TMP/p1/so_no_1.txt"
echo '<p>2</p>' > "$TMP/p2/index.html"
for p in p1 p2 p2; do
  bash "$CI/publicar_web.sh" "$TMP/$p" "file://$remoto" 9.9.9 > "$TMP/c4.log" 2>&1 \
    || falha 4 "publicar_web.sh ($p) saiu com erro: $(cat "$TMP/c4.log")"
done
grep -q '::notice' "$TMP/c4.log" || falha 4 "terceira publicação sem ::notice"
n=$(git --git-dir="$remoto" log web-dist --oneline | wc -l | tr -d ' ')
[ "$n" = 2 ] || falha 4 "web-dist com $n commits (esperado 2)"
pai=$(git --git-dir="$remoto" rev-parse web-dist~1)
primeiro=$(git --git-dir="$remoto" rev-list --max-parents=0 web-dist)
[ "$pai" = "$primeiro" ] || falha 4 "o 2º commit não é filho do 1º"
arquivos=$(git --git-dir="$remoto" ls-tree --name-only web-dist | tr '\n' ' ')
[ "$arquivos" = "index.html " ] || falha 4 "conteúdo não foi trocado: $arquivos"
assunto=$(git --git-dir="$remoto" log -1 --format='%s|%an' web-dist)
case "$assunto" in "Web 9.9.9 ("*")|github-actions[bot]") ;; *) falha 4 "commit inesperado: $assunto" ;; esac
# remoto inacessível não é "branch ausente": não pode criar órfã
if bash "$CI/publicar_web.sh" "$TMP/p1" "file://$TMP/nao_existe.git" 9.9.9 > "$TMP/c4.log" 2>&1; then
  falha 4 "publicar_web.sh aceitou remoto inexistente"
fi
grep -q '::error' "$TMP/c4.log" || falha 4 "remoto inexistente sem ::error: $(cat "$TMP/c4.log")"
passou 4

# 5. conferência do version.json num servidor local
porta=$("$PY" -c "import socket; s=socket.socket(); s.bind(('127.0.0.1', 0)); print(s.getsockname()[1])")
mkdir -p "$TMP/site"
"$PY" -m http.server "$porta" --bind 127.0.0.1 --directory "$TMP/site" > /dev/null 2>&1 &
SERVIDOR_PID=$!
url="http://127.0.0.1:$porta"
echo '{"version":"9.9.9"}' > "$TMP/site/version.json"
for _ in $(seq 1 50); do curl -fs "$url/version.json" > /dev/null 2>&1 && break; sleep 0.2; done
TENTATIVAS=1 ESPERA=0 bash "$CI/conferir_web.sh" 9.9.9 "$url" "$url" --sem-api > "$TMP/c5.log" 2>&1 \
  || falha 5 "conferir_web.sh recusou 9.9.9: $(cat "$TMP/c5.log")"
echo '{"version":"9.9.8"}' > "$TMP/site/version.json"
if TENTATIVAS=1 ESPERA=0 bash "$CI/conferir_web.sh" 9.9.9 "$url" "$url" --sem-api > "$TMP/c5.log" 2>&1; then
  falha 5 "conferir_web.sh aceitou 9.9.8"
fi
passou 5

echo "ok: $casos casos"
