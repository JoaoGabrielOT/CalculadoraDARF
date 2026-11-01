"""Confere que todo teste Python foi portado para o Dart.

Uso (na raiz do repositório):
    py -3.12 ferramentas/conferir_portados.py

Lista `Classe.metodo` de cada `test_*` em tests/*.py (via `ast`) e as descrições dos testes Dart em
app/test/nucleo/portados/**/*.dart (`test('Classe.metodo', ...)`). Imprime `N de N portados` ou os faltantes e
sobrantes e sai com código 1.
"""
import ast
import re
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[1]
DESCRICAO = re.compile(r"""\btest\(\s*(?:'([^'\\]*)'|"([^"\\]*)")""")


def testes_python():
    nomes = []
    for arq in sorted((RAIZ / "tests").glob("*.py")):
        for no in ast.parse(arq.read_text(encoding="utf-8")).body:
            if isinstance(no, ast.ClassDef):
                nomes += [f"{no.name}.{f.name}" for f in no.body
                          if isinstance(f, (ast.FunctionDef, ast.AsyncFunctionDef)) and f.name.startswith("test")]
    return nomes


def testes_dart():
    nomes = []
    for arq in sorted((RAIZ / "app" / "test" / "nucleo" / "portados").rglob("*.dart")):
        for m in DESCRICAO.finditer(arq.read_text(encoding="utf-8")):
            nomes.append(m.group(1) or m.group(2))
    return nomes


def main():
    py, dart = testes_python(), testes_dart()
    faltam = sorted(set(py) - set(dart))
    sobram = sorted(set(dart) - set(py))
    duplicados = sorted({n for n in dart if dart.count(n) > 1})
    if faltam or sobram or duplicados or len(set(py)) != len(py):
        print(f"{len(set(py) & set(dart))} de {len(py)} portados")
        for rotulo, lista in (("faltam", faltam), ("sobram", sobram), ("duplicados no Dart", duplicados)):
            for n in lista:
                print(f"  {rotulo}: {n}")
        return 1
    print(f"{len(py)} de {len(py)} portados")
    return 0


if __name__ == "__main__":
    sys.exit(main())
