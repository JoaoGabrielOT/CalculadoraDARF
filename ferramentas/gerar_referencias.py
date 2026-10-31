"""Gera app/test/referencias/<area>.json com Python 3.12.

Uso: py -3.12 ferramentas/gerar_referencias.py [area ...]
Sem argumentos, gera todas as áreas em ferramentas/referencias/.
"""
import importlib
import json
import sys
from pathlib import Path

if sys.version_info[:2] != (3, 12):
    sys.exit(f"Este gerador exige Python 3.12 (atual: {sys.version.split()[0]}).")

AQUI = Path(__file__).resolve().parent
RAIZ = AQUI.parent
sys.path.insert(0, str(AQUI))
sys.path.insert(0, str(RAIZ))

DESTINO = RAIZ / "app" / "test" / "referencias"


def areas_disponiveis():
    return sorted(p.stem for p in (AQUI / "referencias").glob("*.py") if p.stem not in ("__init__", "base"))


def gerar(area):
    modulo = importlib.import_module(f"referencias.{area}")
    casos = modulo.casos()
    DESTINO.mkdir(parents=True, exist_ok=True)
    doc = {"python": sys.version, "area": area, "casos": casos}
    (DESTINO / f"{area}.json").write_text(json.dumps(doc, ensure_ascii=False, allow_nan=False), encoding="utf-8")
    print(f"{area}: {len(casos)} casos")


def main(argv):
    for area in argv or areas_disponiveis():
        gerar(area)


if __name__ == "__main__":
    main(sys.argv[1:])
