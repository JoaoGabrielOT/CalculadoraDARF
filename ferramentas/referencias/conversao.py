"""Referências das conversões do Python: str, float, int, truthiness, json.dumps e sorted estável."""
import json

from . import base


def _erro(fn, *args):
    try:
        return fn(*args)
    except Exception as e:  # noqa: BLE001 - o nome da exceção é a referência
        return {"erro": type(e).__name__}


def _texto_float(r):
    """float não finito não cabe em JSON: a referência de float é o repr do resultado."""
    return r if isinstance(r, dict) else repr(r)


def _num(v, padrao=0.0):
    # Cópia literal de nucleo._num (nucleo.py:770-774).
    try:
        return float(v) if v not in ("", None) else padrao
    except (TypeError, ValueError):
        return padrao


JSONS = [
    {"ticker": "PETR4", "motivo": "preço ≥ gatilho", "preco": 9.0, "ok": True, "nada": None},
    {"texto": 'aspas "duplas" e \\ barra', "quebra": "linha1\nlinha2\r\tfim", "ctl": "a\u001fb\u0008\u000c\u0000"},
    {"floats": [9.0, 1e-05, 21.78, 100.0, -0.0, 1e16, 1e22, 0.1, 123456789.125], "ints": [0, -7, 1000000]},
    {"unicode": "Itaú Unibanco, Nestlé, Ørsted, ﬁ, 😀, \u007f,  ", "vazio": {}, "lista": []},
    {"aninhado": {"b": [1, {"c": [2.5, "x"]}], "a": {"z": None, "y": False}}, "chave ≥": 1},
    [],
    {},
    "só texto ≥",
    42,
    3.5,
    None,
]

ORDENACOES = [
    ([[1, "a"], [2, "b"], [1, "c"]], False),
    ([[1, "a"], [2, "b"], [1, "c"]], True),
    ([[1.5], [1], [1.0], [0.5], [1]], False),
    ([[1.5], [1], [1.0], [0.5], [1]], True),
    ([[True], [False], [1], [0], [True]], False),
    ([[True], [False], [1], [0], [True]], True),
    ([["b", 1], ["B", 1], ["a", 2], ["a", 1], ["é", 0], ["z", 0]], False),
    ([["b", 1], ["B", 1], ["a", 2], ["a", 1], ["é", 0], ["z", 0]], True),
    ([["￿"], ["😀"], ["a"], ["\U00010000"], [""]], False),
    ([["￿"], ["😀"], ["a"], ["\U00010000"], [""]], True),
    ([["2026-10-28", "PETR4", 1.0], ["2026-10-28", "PETR4", 1.0], ["2026-10-27", "VALE3", 2.0],
      ["2026-10-28", "ABEV3", 1.0]], False),
    ([["2026-10-28", "PETR4", 1.0], ["2026-10-28", "PETR4", 1.0], ["2026-10-27", "VALE3", 2.0],
      ["2026-10-28", "ABEV3", 1.0]], True),
    ([[3], [3], [3], [3]], True),
    ([[2, 1], [1, 2], [2], [1]], False),
    ([], False),
    ([[5]], True),
]


def casos():
    out = []
    for i, v in enumerate([0, -7, 1.0, 100.0, -0.0, 1e16, 21.78, True, False, None, "x", 1e-05, 123456789.125]):
        out.append(base.caso(f"str {i}", "str", {"v": v}, str(v)))
    for i, v in enumerate([" 12.5 ", "1_000", "1e3", "inf", "-Infinity", "nan", "12,5", "", "0x10", "1__0", 7, True,
                           False, "+nan", "-inf", "INF", "iNfInItY", "1_e3", "1e1_0", ".5", "5.", "+.5e-2", "_1",
                           "1_", "1e", "e5", "1.5.2", "  -3 ", "\t4\n", "1e400", "-0", "-0.0", 2.5, "1_0.5_5",
                           "--1", "+-1", "infinit", "nan1", "1 2", None, [1]]):
        r = _erro(float, v)
        out.append(base.caso(f"float {i}", "float", {"v": v}, _texto_float(r)))
    for i, v in enumerate(["100", " 7 ", "1_0", "100.0", "", 100.9, -2.7, True, False, "+5", "-5", " -0 ", "1__0",
                           "_1", "1_", "0x10", "1e3", "12,5", 0.5, -0.0, "00012", "+-1", "1 2", None]):
        out.append(base.caso(f"int {i}", "int", {"v": v}, _erro(int, v)))
    for i, v in enumerate([None, True, False, 0, 0.0, -0.0, 1, -1, 0.5, "", " ", "0", "x", [], [0], {}, {"a": 1},
                           [[]]]):
        out.append(base.caso(f"bool {i}", "bool", {"v": v}, bool(v)))
    for i, v in enumerate(["", None, "12.5", "abc", 3, True, False, 0, [], {}, "nan", " 7 ", "1_0", "1e3", "inf",
                           2.5, "12,5"]):
        out.append(base.caso(f"num {i}", "num", {"v": v}, repr(_num(v))))
        out.append(base.caso(f"num padrão {i}", "num", {"v": v, "padrao": 5.0}, repr(_num(v, 5.0))))
    for i, v in enumerate(JSONS):
        out.append(base.caso(f"json {i}", "json", {"v": v, "compacto": False}, json.dumps(v, ensure_ascii=False)))
        out.append(base.caso(f"json compacto {i}", "json", {"v": v, "compacto": True},
                             json.dumps(v, ensure_ascii=False, separators=(",", ":"))))
    for i, (chaves, reverso) in enumerate(ORDENACOES):
        idx = sorted(range(len(chaves)), key=lambda j: tuple(chaves[j]), reverse=reverso)
        out.append(base.caso(f"sorted {i} reverso={reverso}", "sorted", {"chaves": chaves, "reverso": reverso}, idx))
    return out
