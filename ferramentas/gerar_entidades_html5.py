"""Gera app/lib/integracoes/noticias/entidades_html5.dart a partir de html.entities.html5 (Python 3.12).

Uso: py -3.12 ferramentas/gerar_entidades_html5.py
"""
import sys
from html.entities import html5
from pathlib import Path

if sys.version_info[:2] != (3, 12):
    sys.exit(f"Este gerador exige Python 3.12 (atual: {sys.version.split()[0]}).")

DESTINO = Path(__file__).resolve().parents[1] / "app" / "lib" / "integracoes" / "noticias" / "entidades_html5.dart"


def literal(texto):
    saida = []
    for c in texto:
        if c.isascii() and c.isprintable() and c not in "$\\'":
            saida.append(c)
        else:
            saida.append("\\u{%x}" % ord(c))
    return "'" + "".join(saida) + "'"


def main():
    linhas = [
        "// Gerado por ferramentas/gerar_entidades_html5.py a partir de html.entities.html5 (Python 3.12). Não editar.",
        "",
        "/// Entidades HTML5 nomeadas (chaves com e sem `;`).",
        "const Map<String, String> entidadesHtml5 = {",
    ]
    for nome in sorted(html5):
        linhas.append(f"  {literal(nome)}: {literal(html5[nome])},")
    linhas.append("};")
    DESTINO.parent.mkdir(parents=True, exist_ok=True)
    DESTINO.write_text("\n".join(linhas) + "\n", encoding="utf-8", newline="\n")
    print(f"{len(html5)} entradas")


if __name__ == "__main__":
    main()
