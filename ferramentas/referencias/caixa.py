"""Referências de caixa, liquidação D+2 e feriados da B3 (nucleo.py:538-739).

Funções (campo `funcao` de cada caso):
- pascoa / feriados_b3: entrada {anos}; saída {"<ano>": ...}.
- liquidacao_dias: entrada {inicio, fim, dias_uteis}; saída {"dias": [[data, dia_util, liquidacao, fmt]]}.
- vencimentos: entrada {hojes}; saída {"<hoje>": [{d, uteis_ate, uteis_de, rotulo}]}; rotulo_sem_hoje usa o hoje congelado.
- resumo_ordem: grade de ordens.
- cenarios_caixa: entrada {arquivos, cenarios: [{hoje, caixa}]}; saída {lancamentos, cenarios: [...]}.
- saldos: entrada {arquivos, cfg, operacoes}; saída {"resultados": [cfg["caixa"] depois de cada operação]}.
"""
from datetime import date, timedelta

from . import base
from . import fechamento as fe

nc = base.nc


def _d(iso):
    return date.fromisoformat(iso)


def _dias(inicio, fim):
    d = _d(inicio)
    while d <= _d(fim):
        yield d
        d += timedelta(days=1)


def _feriados():
    anos = list(range(1990, 2071))
    return [
        base.caso("pascoa_1990_2070", "pascoa", {"anos": anos}, {str(a): nc._pascoa(a) for a in anos}),
        base.caso("feriados_b3_1990_2070", "feriados_b3", {"anos": anos},
                  {str(a): sorted(nc.feriados_b3(a)) for a in anos}),
    ]


def _liquidacao():
    out = []
    for dias_uteis, inicio, fim in ((2, "2023-01-01", "2027-12-31"), (0, "2026-01-01", "2026-12-31"),
                                    (1, "2026-01-01", "2026-12-31"), (5, "2026-01-01", "2026-12-31")):
        linhas = []
        for d in _dias(inicio, fim):
            liq = nc.calcular_data_liquidacao(d.isoformat(), dias_uteis)
            linhas.append([d.isoformat(), nc.dia_util(d), liq, nc.fmt_liquidacao(liq)])
        out.append(base.caso(f"liquidacao_d{dias_uteis}", "liquidacao_dias",
                             {"inicio": inicio, "fim": fim, "dias_uteis": dias_uteis}, {"dias": linhas}))
    return out


def _vencimentos():
    hojes = ["2026-10-28", "2026-10-30", "2026-12-23", "2026-04-01", "2024-11-18"]
    saida = {}
    with base.congelar():
        for h in hojes:
            hoje = _d(h)
            linhas = []
            for k in range(-3, 11):
                d = hoje + timedelta(days=k)
                linhas.append({"d": d.isoformat(), "uteis_ate": nc.dias_uteis_entre(hoje, d),
                               "uteis_de": nc.dias_uteis_entre(d, hoje),
                               "rotulo": nc.rotulo_vencimento(d, hoje)})
            saida[h] = linhas
        saida["rotulo_sem_hoje"] = [{"d": (_d("2026-10-28") + timedelta(days=k)).isoformat(),
                                     "rotulo": nc.rotulo_vencimento(_d("2026-10-28") + timedelta(days=k))}
                                    for k in range(-3, 11)]
    return [base.caso("vencimentos", "vencimentos", {"hojes": hojes}, saida)]


def _ordens():
    entradas = []
    for lado in ("compra", "venda"):
        for day_trade in (False, True):
            for qtd in (1, 100, 300, 1000, 2500):
                for preco in (0.5, 10.0, 33.33, 150.0, 250.0):
                    for preco_compra in (None, 9.0, 12.5, 140.0, 0.0):
                        for data in ("2026-10-28", "2026-10-30", "2026-12-23"):
                            entradas.append({"lado": lado, "qtd": qtd, "preco": preco, "data": data,
                                             "preco_compra": preco_compra, "day_trade": day_trade})
    saidas = [nc.resumo_ordem(e["lado"], e["qtd"], e["preco"], e["data"], e["preco_compra"], e["day_trade"])
              for e in entradas]
    return [base.caso("grade_de_ordens", "resumo_ordem", {"ordens": entradas}, {"resultados": saidas})]


def _depois(arquivos, operacoes):
    """Arquivos de dados depois de executar as operações do roteiro de fechamento."""
    with base.pasta_dados() as pasta, base.congelar():
        base.gravar_arquivos(pasta, arquivos)
        for op in operacoes:
            nc.agora = lambda t=op["agora"]: t
            fe._executar(op)
        return base.arquivos(pasta)


def _empate(invertido):
    """Compra e venda do mesmo ticker liquidando no mesmo dia, com a mesma data e o mesmo ticker (Review Focus 2)."""
    grande = fe._lote("B", "PETR4", "2026-09-01", 1000, 28.0,
                      [fe._venda("vb1", "2026-10-05", 10, 31.0), fe._venda("vb2", "2026-10-05", 20, 32.0),
                       fe._venda("vb3", "2026-10-05", 600, 40.0)])
    daytrade = fe._lote("A", "PETR4", "2026-10-05", 200, 30.0, [fe._venda("va1", "2026-10-05", 100, 35.0)])
    sexta = fe._lote("C", "PETR4", "2026-10-09", 50, 30.5)
    fimdesemana = fe._lote("D", "PETR4", "2026-09-01", 50, 30.0, [fe._venda("vd1", "2026-10-11", 50, 31.0)])
    lotes = [grande, daytrade, sexta, fimdesemana]
    if invertido:
        lotes = lotes[::-1]
    return {"2026-10.json": fe._mes("2026-10", lotes)}


CAIXAS = [{}, {"saldo": 1000.5, "data": "2026-02-10"}, {"saldo": -250.75, "data": "2026-10-06"},
          {"saldo": 500.0, "data": "2026-11-15"}, {"saldo": 0.0, "data": "2026-03-01"}]
HOJES = ["2026-01-10", "2026-02-20", "2026-03-13", "2026-04-01", "2026-10-07", "2026-10-14", "2026-10-28"]


def _cenarios(arquivos):
    cenarios = [{"hoje": h, "caixa": c} for h in HOJES for c in CAIXAS]
    saida = []
    with base.pasta_dados() as pasta, base.congelar():
        base.gravar_arquivos(pasta, arquivos)
        lancamentos = nc.lancamentos_caixa()
        for cen in cenarios:
            hoje = _d(cen["hoje"])
            r = nc.resumo_caixa({"caixa": dict(cen["caixa"])}, hoje)
            ag = nc.agenda_caixa(r, hoje)
            saida.append({
                "resumo": r,
                "agenda": [{"data": d, "rotulo": rot, "total": t, "itens": it} for d, rot, t, it in ag],
                "agenda_curta": [{"data": d, "rotulo": rot, "total": t, "itens": it}
                                 for d, rot, t, it in nc.agenda_caixa(r, hoje, 3)],
                "projecao": [{"data": d, "rotulo": rot, "total": t, "itens": it, "saldo_apos": s}
                             for d, rot, t, it, s in nc.projecao_caixa(r, hoje)],
            })
    return {"arquivos": arquivos, "cenarios": cenarios}, {"lancamentos": lancamentos, "cenarios": saida}


def _saldos():
    arquivos = fe._semestre()
    cfg = {"caixa": {"saldo": 100.0, "data": "2026-01-02", "mod": 1.5}, "tema": "Dark"}
    operacoes = [
        {"op": "ajustar", "delta": 50.25, "hoje": "2026-02-20"},
        {"op": "definir", "valor": 1234.567, "hoje": "2026-02-21"},
        {"op": "definir", "valor": 0.125, "hoje": "2026-03-13"},
        {"op": "ajustar", "delta": -300.0, "hoje": "2026-03-13"},
        {"op": "definir", "valor": 7, "hoje": "2026-10-28"},
        {"op": "ajustar", "delta": 0.0, "hoje": "2026-10-28"},
        {"op": "definir", "valor": -42.005, "hoje": "2026-10-28"},
    ]
    resultados = []
    with base.pasta_dados() as pasta, base.congelar():
        base.gravar_arquivos(pasta, arquivos)
        c = {k: (dict(v) if isinstance(v, dict) else v) for k, v in cfg.items()}
        for op in operacoes:
            hoje = _d(op["hoje"])
            if op["op"] == "definir":
                nc.definir_saldo(c, op["valor"], hoje)
            else:
                nc.ajustar_saldo(c, op["delta"], hoje)
            resultados.append(dict(c["caixa"]))
    return [base.caso("definir_e_ajustar", "saldos", {"arquivos": arquivos, "cfg": cfg, "operacoes": operacoes},
                      {"resultados": resultados})]


def casos():
    out = _feriados() + _liquidacao() + _vencimentos() + _ordens()

    semestre = fe._semestre()
    fechado = _depois(semestre, [fe._fechar("2026-01", 100.5), fe._fechar("2026-02", 200.5),
                                 fe._fechar("2026-03", 300.5), fe._fechar("2026-04", 400.5)])
    base_retro = {"2026-06.json": fe._mes("2026-06", [fe._lote("L1", "T1TW34", "2026-05-05", 58, 9.0)])}
    retro = _depois(base_retro, [fe._retro("2026-06", "L1", "2026-03-15", 10, 10.0, 100.5),
                                 fe._retro("2026-06", "L1", "2026-03-20", 30, 12.0, 200.5)])
    for nome, arquivos in (("semestre", semestre), ("semestre_fechado_com_levadas", fechado),
                           ("retroativa", retro), ("sem_meses", {}),
                           ("empate_lancamentos", _empate(False)),
                           ("empate_lancamentos_invertido", _empate(True))):
        entrada, saida = _cenarios(arquivos)
        out.append(base.caso(nome, "cenarios_caixa", entrada, saida))
    return out + _saldos()
