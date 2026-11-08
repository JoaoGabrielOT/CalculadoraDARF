"""Confere a ida e volta Dart -> Python da planilha.

Uso (na raiz do repositório, depois de `flutter test --tags ida_e_volta` em app/):
    py -3.12 ferramentas/conferir_ida_e_volta.py app/build/ida_e_volta

Para cada arquivo gravado pelo teste Dart: confere que google_sync.celula dá as mesmas células que o Dart, passa as
linhas pelo completamento de `Google.ler` (google_sync.py:441), roda nucleo.reconstruir e nucleo.reconstruir_metas e
compara com o estado que o Dart tem depois da sincronização. A comparação é estrita (int != float, -0.0 != 0.0).
Além dos casos de sincronizacao.json, aceita os roteiros só do Dart (nome com `dart_`), como o da planilha da 2.1 com
o marcador de custo médio na 14ª coluna do Resumo: o Python ignora essa coluna, então os campos do marcador saem do
estado do Dart antes da comparação.
Imprime `IDA E VOLTA OK (<n> roteiros)` ou as diferenças, e sai com código 1.
"""
import json
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(RAIZ))

from ferramentas.referencias import base  # noqa: E402
import google_sync  # noqa: E402

nc = base.nc
REFERENCIA = RAIZ / "app" / "test" / "referencias" / "sincronizacao.json"
# campos do mês que só a 2.1 grava (marcador de custo médio); o Python não os lê da planilha
CAMPOS_2_1 = ("metodo", "posicao_inicial", "prejuizo_anterior")


def igual(a, b, caminho, difs):
    """Igualdade estrita; acumula em `difs` o caminho de cada diferença."""
    if isinstance(a, bool) or isinstance(b, bool):
        if a is not b:
            difs.append(f"{caminho}: python {a!r}, dart {b!r}")
    elif isinstance(a, (int, float)) and isinstance(b, (int, float)):
        if type(a) is not type(b) or a != b or (a == 0 and str(a) != str(b)):
            difs.append(f"{caminho}: python {a!r}, dart {b!r}")
    elif isinstance(a, dict) and isinstance(b, dict):
        for k in sorted(set(a) | set(b), key=str):
            if k not in a:
                difs.append(f"{caminho}.{k}: ausente no python, dart {b[k]!r}")
            elif k not in b:
                difs.append(f"{caminho}.{k}: python {a[k]!r}, ausente no dart")
            else:
                igual(a[k], b[k], f"{caminho}.{k}", difs)
    elif isinstance(a, list) and isinstance(b, list):
        if len(a) != len(b):
            difs.append(f"{caminho}: python tem {len(a)} itens, dart {len(b)}")
        for i, (x, y) in enumerate(zip(a, b)):
            igual(x, y, f"{caminho}[{i}]", difs)
    elif type(a) is not type(b) or a != b:
        difs.append(f"{caminho}: python {a!r}, dart {b!r}")


def valor_da_celula(c):
    """O que a API devolve (UNFORMATTED_VALUE) para uma célula gravada: vazia some, número e texto voltam iguais."""
    if not c:
        return ""
    v = c["userEnteredValue"]
    return v["numberValue"] if "numberValue" in v else v["stringValue"]


def ler(celulas):
    """Aba -> linhas como `Google.ler` as devolve: a API corta as células vazias do fim, o código completa com ""."""
    res = {a: [] for a in google_sync.ABAS}
    for aba, linhas in celulas.items():
        n = len(google_sync.ABAS[aba]["colunas"])
        for linha in linhas:
            valores = [valor_da_celula(c) for c in linha]
            while valores and valores[-1] == "":
                valores.pop()
            res[aba].append((valores + [""] * n)[:n])
    return res


def conferir(arquivo):
    doc = json.loads(arquivo.read_text(encoding="utf-8"))
    difs = []
    linhas, celulas, estado = doc["linhas"], doc["celulas"], doc["estado"]

    esperadas = {aba: [[google_sync.celula(v) for v in l] for l in ls] for aba, ls in linhas.items()}
    igual(esperadas, celulas, "celulas", difs)

    abas = ler(celulas)
    with base.pasta_dados(), base.congelar():
        meses, amigos, radar, excl_cfg, caixa = nc.reconstruir(abas)
        metas = nc.reconstruir_metas(abas)

    cfg = estado["cfg"]
    # Duas diferenças que são do formato da planilha, iguais no Python (o Dart grava as mesmas células que
    # nc.montar_linhas): a aba Vendas sai ordenada por data de venda, enquanto o arquivo do mês guarda as vendas na
    # ordem de inserção; e a coluna Posição leva o índice quando o item do radar não tem `pos`.
    for mes in estado["meses"].values():
        for campo in CAMPOS_2_1:
            mes.pop(campo, None)
        for lote in mes["lotes"]:
            lote["vendas"].sort(key=lambda v: v["id"])
    for mes in meses.values():
        for lote in mes["lotes"]:
            lote["vendas"].sort(key=lambda v: v["id"])
    # (montar_linhas ordena o radar com ordenar_radar antes de completar `pos` pelo índice)
    cfg["radar"] = [{**r, "pos": r.get("pos", i)} for i, r in enumerate(nc.ordenar_radar(cfg["radar"]))]
    chave_meta = lambda m: (m["criada_em"], m["id"])  # noqa: E731 (a aba Metas sai ordenada assim)
    igual(meses, estado["meses"], "meses", difs)
    igual(amigos, cfg["amigos"], "amigos", difs)
    igual(radar, cfg["radar"], "radar", difs)
    igual(excl_cfg, cfg["excluidos"], "excluidos", difs)
    igual(sorted(metas, key=chave_meta), sorted(cfg["metas"], key=chave_meta), "metas", difs)
    igual(caixa, cfg["caixa"] if cfg["caixa"].get("data") else None, "caixa", difs)
    return difs


def main():
    pasta = Path(sys.argv[1])
    arquivos = sorted(pasta.glob("*.json"))
    if not arquivos:
        print(f"nenhum arquivo em {pasta}")
        return 1
    # a pasta tem de ter exatamente um arquivo por caso de sincronizacao.json (nada a mais, nada a menos), além
    # dos roteiros só do Dart
    casos = json.loads(REFERENCIA.read_text(encoding="utf-8"))["casos"]
    esperados = sorted(c["nome"] for c in casos)
    achados = sorted(a.stem for a in arquivos if not a.stem.startswith("dart_"))
    if achados != esperados:
        print(f"a pasta {pasta} não bate com {REFERENCIA.name}: {len(achados)} arquivos para {len(esperados)} casos")
        for nome in sorted(set(esperados) - set(achados)):
            print(f"  falta {nome}")
        for nome in sorted(set(achados) - set(esperados)):
            print(f"  sobra {nome}")
        return 1
    falhas = 0
    for arq in arquivos:
        difs = conferir(arq)
        if difs:
            falhas += 1
            print(f"[{arq.stem}]")
            for d in difs:
                print("  " + d)
    if falhas:
        print(f"{falhas} de {len(arquivos)} roteiros com diferenças")
        return 1
    print(f"IDA E VOLTA OK ({len(arquivos)} roteiros)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
