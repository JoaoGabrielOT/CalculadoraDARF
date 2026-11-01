"""Referências dos pedidos ao Sheets/Drive montados por `Google` (google_sync.py:282-456), sem rede.

Uma `Google` real recebe uma sessão falsa (`request(metodo, url, timeout, params=None, json=None)`) que grava cada
pedido e devolve a próxima `Resposta` programada; o e-mail é `eu@exemplo.com`. Os corpos gravados são o contrato com a
planilha compartilhada com a versão Python.

Cada caso: funcao, entrada {respostas: [{status, json|texto}], args: [...]}, saida {pedidos: [{metodo, url, params,
json}], resultado | erro, mensagem, status}. `params` vira {chave: [str(valor), ...]}. Funções: criar_planilha,
garantir_abas, escrever, ler, buscar_planilha, planilha_existe, compartilhar, descompartilhar.
"""
import tempfile

import google_sync as gs

from . import _rede_falsa as rf
from . import base

ABAS = gs.ABAS
EMAIL = "eu@exemplo.com"
SID = "sid1"


class _Sessao:
    """Sessão falsa: grava o pedido e devolve a próxima resposta (a última se esgotarem)."""

    def __init__(self, respostas):
        self.respostas = respostas
        self.pedidos = []

    def request(self, metodo, url, timeout, params=None, json=None):
        itens = params.items() if params else []
        self.pedidos.append({
            "metodo": metodo, "url": url,
            "params": {str(k): [str(x) for x in (v if isinstance(v, (list, tuple)) else [v])] for k, v in itens},
            "json": json})
        r = self.respostas[min(len(self.pedidos) - 1, len(self.respostas) - 1)]
        return rf.Resposta(r["status"], json=r.get("json"), texto=r.get("texto"))


def _executar(funcao, argumentos, respostas):
    cm, _ = rf.rede([])
    with tempfile.TemporaryDirectory() as tmp, rf.google_falso(), cm:
        g = gs.Google(tmp, tmp)
        g.sessao = _Sessao(respostas)
        g.email = EMAIL
        saida = {}
        try:
            saida["resultado"] = funcao(g, *argumentos)
        except gs.ErroGoogle as e:
            saida.update(rf.erro(e))
            saida["status"] = e.status
        return {"pedidos": g.sessao.pedidos, **saida}


def _caso(nome, funcao, args, respostas, chamada):
    return base.caso(nome, funcao, {"args": args, "respostas": respostas}, _executar(chamada, args, respostas))


def _ok(corpo=None):
    return {"status": 200, **({"json": corpo} if corpo is not None else {})}


def _meta(colunas=None, linhas=None, ignorar=()):
    """Resposta do GET de propriedades; `colunas`/`linhas`: {aba: valor} que substituem o tamanho do esquema."""
    colunas, linhas = colunas or {}, linhas or {}
    return _ok({"sheets": [{"properties": {
        "sheetId": 10 * (i + 1), "title": nome,
        "gridProperties": {"rowCount": linhas.get(nome, 1000), "columnCount": colunas.get(nome, len(spec["colunas"]))}}}
        for i, (nome, spec) in enumerate(ABAS.items()) if nome not in ignorar]})


def _valores(n, i):
    modelo = [None, "", True, False, 0, -0.0, 0.1, 1761000000.123, "Ação preferencial — Itaú", 12, "2026-10-28", 3.5,
              "x"]
    return [modelo[(i + j) % len(modelo)] for j in range(n)]


def _dados_completos(linhas=3):
    return {nome: [_valores(len(spec["colunas"]), i + k) for k in range(linhas)]
            for i, (nome, spec) in enumerate(ABAS.items())}


def _casos_criacao():
    criada = _ok({"spreadsheetId": SID, "sheets": [
        {"properties": {"title": nome, "sheetId": 7 * i + 3, "index": i}} for i, nome in enumerate(ABAS)]})
    faltando = ["Caixa", "Metas", "Exclusões"]
    novas = _ok({"replies": [{"addSheet": {"properties": {"title": nome, "sheetId": 500 + i}}}
                             for i, nome in enumerate(faltando)]})
    return [
        _caso("criar_planilha", "criar_planilha", [], [criada, _ok({})], lambda g: g.criar_planilha()),
        _caso("garantir_abas_completa", "garantir_abas", [SID], [_meta()], lambda g, s: g._garantir_abas(s)),
        _caso("garantir_abas_faltando", "garantir_abas", [SID], [_meta(ignorar=faltando), novas, _ok({})],
              lambda g, s: g._garantir_abas(s)),
    ]


def _casos_escrita():
    def esc(nome, dados, meta):
        return _caso(nome, "escrever", [SID, dados], [meta, _ok({})], lambda g, s, d: g.escrever(s, d))
    return [
        esc("escrever_simples", _dados_completos(), _meta()),
        esc("escrever_crescer", {"Compras": [_valores(13, k) for k in range(12)], "Vendas": [_valores(17, 1)]},
            _meta(linhas={"Compras": 10})),
        esc("escrever_metas_12_colunas", {"Metas": [_valores(14, k) for k in range(2)]},
            _meta(colunas={"Metas": 12})),
        esc("escrever_encolheu", {"Compras": [_valores(13, 0)], "Vendas": [_valores(17, 0)]},
            _meta(linhas={"Compras": 1500, "Vendas": 1200})),
        esc("escrever_vazio", {"Compras": []}, _meta()),
    ]


def _casos_leitura():
    def aba(nome, valores):
        return {"range": f"'{nome}'!A2", "majorDimension": "ROWS", **({"values": valores} if valores else {})}
    meta = _ok({"sheets": [
        {"properties": {"title": "Resumo", "gridProperties": {"columnCount": 13}}},
        {"properties": {"title": "Metas", "gridProperties": {"columnCount": 12}}},
        {"properties": {"title": "Outra"}},
        {"properties": {"title": "Amigos"}},
    ]})
    lidas = _ok({"valueRanges": [
        aba("Resumo", [["2026-10", "Aberto", 1500.5]]),
        aba("Amigos", None),
        aba("Metas", [["m1", "PETR4", "venda", "", 100, 40.5], ["m2"]]),
    ]})
    return [
        _caso("ler", "ler", [SID], [meta, lidas], lambda g, s: g.ler(s)),
        _caso("ler_sem_abas", "ler", [SID], [_ok({})], lambda g, s: g.ler(s)),
    ]


def _casos_drive():
    def busca(g, d):
        return g.buscar_planilha(d)

    def existe(g, s):
        return g.planilha_existe(s)

    arquivos = _ok({"files": [{"id": "arq1"}, {"id": "arq2"}]})
    erro404 = {"status": 404, "json": {"error": {"message": "File not found"}}}
    permissoes = _ok({"permissions": [
        {"id": "p0", "emailAddress": "amigo@exemplo.com", "role": "owner"},
        {"id": "p1", "emailAddress": "Amigo@Exemplo.com", "role": "reader"},
        {"id": "p2", "emailAddress": "outro@exemplo.com", "role": "reader"},
        {"id": "p3", "role": "reader"}]})
    return [
        _caso("buscar_planilha_me", "buscar_planilha", ["me"], [arquivos], busca),
        _caso("buscar_planilha_aspas", "buscar_planilha", ["o'bri\\en@x.com"], [arquivos], busca),
        _caso("buscar_planilha_nada", "buscar_planilha", ["me"], [_ok({"files": []})], busca),
        _caso("planilha_existe_ok", "planilha_existe", [SID], [_ok({"id": SID, "trashed": False})], existe),
        _caso("planilha_existe_lixeira", "planilha_existe", [SID], [_ok({"id": SID, "trashed": True})], existe),
        _caso("planilha_existe_404", "planilha_existe", [SID], [erro404], existe),
        _caso("planilha_existe_500", "planilha_existe", [SID], [{"status": 500, "texto": "Backend Error"}], existe),
        _caso("compartilhar", "compartilhar", [SID, "amigo@exemplo.com"], [_ok({"id": "p9"})],
              lambda g, s, e: g.compartilhar(s, e)),
        _caso("descompartilhar", "descompartilhar", [SID, "amigo@exemplo.com"], [permissoes, _ok()],
              lambda g, s, e: g.descompartilhar(s, e)),
        _caso("descompartilhar_ninguem", "descompartilhar", [SID, "novo@exemplo.com"], [permissoes],
              lambda g, s, e: g.descompartilhar(s, e)),
        _caso("erro_401", "buscar_planilha", ["me"],
              [{"status": 401, "json": {"error": {"message": "Invalid Credentials"}}}], busca),
        _caso("erro_400_json", "buscar_planilha", ["me"],
              [{"status": 400, "json": {"error": {"message": "Invalid query"}}}], busca),
        _caso("erro_500_texto", "buscar_planilha", ["me"], [{"status": 500, "texto": "falha interna " + "x" * 400}],
              busca),
    ]


def casos():
    with base.congelar():
        return _casos_criacao() + _casos_escrita() + _casos_leitura() + _casos_drive()
