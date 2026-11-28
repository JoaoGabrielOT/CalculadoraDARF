"""Gera o versao.json da release: versao, notas e tamanho/sha256 de cada asset.

Uso: gerar_manifesto.py VERSAO ARQUIVO_NOTAS SAIDA ASSET [ASSET...]
"""
import hashlib
import json
import os
import sys


def main(argv):
    versao, notas, saida, *assets = argv
    with open(notas, encoding="utf-8") as f:
        texto = f.read()
    info = {}
    for caminho in assets:
        with open(caminho, "rb") as f:
            conteudo = f.read()
        info[os.path.basename(caminho)] = {
            "tamanho": len(conteudo),
            "sha256": hashlib.sha256(conteudo).hexdigest(),
        }
    with open(saida, "w", encoding="utf-8", newline="\n") as f:
        json.dump({"versao": versao, "notas": texto, "assets": info}, f, ensure_ascii=False)


if __name__ == "__main__":
    if len(sys.argv) < 5:
        sys.exit(__doc__)
    main(sys.argv[1:])
