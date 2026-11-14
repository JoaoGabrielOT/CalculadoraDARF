#!/usr/bin/env bash
# Publica a pasta montada na branch web-dist (lida pela Vercel e pelo Render), com um commit novo e sem force push.
# Uso: publicar_web.sh <saida> <remoto> <versao>
# Sem a branch no remoto, cria uma órfã; sem mudança no conteúdo, avisa e sai 0.
set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "Uso: $0 <saida> <remoto> <versao>" >&2
  exit 2
fi
SAIDA="$(cd "$1" && pwd)"; REMOTO="$2"; VERSAO="$3"
[ -f "$SAIDA/index.html" ] || { echo "::error title=Web::$SAIDA/index.html ausente"; exit 1; }

TRABALHO="$(mktemp -d)"
trap 'rm -rf "$TRABALHO"' EXIT
git() { command git -c core.autocrlf=false "$@"; }

if git ls-remote --exit-code --heads "$REMOTO" web-dist > /dev/null 2>&1; then
  # depth 1: o histórico guarda um build por versão e só o último interessa
  git clone --quiet --depth 1 --single-branch --branch web-dist "$REMOTO" "$TRABALHO/repo"
  cd "$TRABALHO/repo"
else
  echo "::notice title=Web::branch web-dist ausente no remoto; criando órfã"
  mkdir "$TRABALHO/repo"
  cd "$TRABALHO/repo"
  git init --quiet
  git checkout --quiet --orphan web-dist
  git remote add origin "$REMOTO"
fi

find . -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
cp -R "$SAIDA/." .
git add -A
if git diff --cached --quiet; then
  echo "::notice title=Web::web-dist já tem este conteúdo; nada a publicar"
  exit 0
fi

git -c user.name="github-actions[bot]" \
    -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
    commit --quiet -m "Web $VERSAO (${GITHUB_SHA:-local})"
git push --quiet origin web-dist
echo "::notice title=Web::web-dist $(git rev-parse HEAD) (Web $VERSAO)"
