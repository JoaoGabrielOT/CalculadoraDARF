"""Referências da detecção do gatilho de metas e do stop móvel (metas.py:358-417).

Funções (campo `funcao` de cada caso):
- achar_barra: entrada {barras: [{dt, alta}], alvo, criada}; saída {"indice"} da barra escolhida (posição na lista
  de entrada) ou {"indice": null}.
- nivel_vigente: entrada {niveis, data}; saída {"nivel"} (null sem nível em vigor).
- achar_barra_stop: entrada {barras: [{dt, alta, baixa, abre}], niveis, criada}; saída {"indice", "nivel"} ou
  {"indice": null}.
- preco_execucao_stop: entrada {abre, nivel}; saída {"preco", "gap"}.
- atualizar_stop_movel: entrada {meta, barras: [{data, abre, alta, baixa, fech}], hoje}; saída {"mudou", "meta"}
  (meta depois da chamada).
- barras_aleatorias: entrada {n}; saída {"barras"} (tests/test_metas.py:1113-1123, Random(7)).
"""
import copy
import random
from datetime import date, datetime, timedelta, timezone

from . import base

mt = base.mt

CRIADA = "2026-10-20T11:00:00-03:00"


def _dt(texto):
    return datetime.fromisoformat(texto)


def _horarias(rng, n, inicio="2026-10-20T09:00:00-03:00"):
    """Barras de 1h com alta/baixa/abre aleatórias, embaralhadas, algumas sem mínima ou abertura."""
    t0 = _dt(inicio)
    preco = rng.uniform(8, 12)
    out = []
    for i in range(n):
        abre = preco
        preco = max(0.5, preco + rng.uniform(-0.5, 0.5))
        alta = max(abre, preco) + rng.uniform(0, 0.3)
        baixa = min(abre, preco) - rng.uniform(0, 0.3)
        b = {"dt": (t0 + timedelta(hours=i)).isoformat(), "alta": round(alta, 2),
             "baixa": None if rng.random() < 0.1 else round(baixa, 2),
             "abre": None if rng.random() < 0.15 else round(abre, 2)}
        out.append(b)
    rng.shuffle(out)
    return out


def _barras_alta(entrada):
    return [{"dt": _dt(b["dt"]), "alta": b["alta"]} for b in entrada["barras"]]


def _barras_stop(entrada):
    return [{"dt": _dt(b["dt"]), "alta": b["alta"], "baixa": b["baixa"], "abre": b["abre"]}
            for b in entrada["barras"]]


def _achar_barra():
    out = []
    rng = random.Random(4)
    cenarios = [
        ("lista_vazia", [], 21.78),
        ("igual_ao_alvo", [{"dt": "2026-10-20T12:00:00-03:00", "alta": 21.78}], 21.78),
        ("tolerancia_dentro", [{"dt": "2026-10-20T12:00:00-03:00", "alta": 21.78 - 5e-10}], 21.78),
        ("tolerancia_fora", [{"dt": "2026-10-20T12:00:00-03:00", "alta": 21.78 - 2e-9}], 21.78),
        ("na_hora_da_criacao", [{"dt": "2026-10-20T11:00:00-03:00", "alta": 22.0}], 21.78),
        ("um_segundo_antes", [{"dt": "2026-10-20T10:59:59-03:00", "alta": 99.0}], 21.78),
        ("fuso_utc", [{"dt": "2026-10-20T14:00:00+00:00", "alta": 22.0}], 21.78),
        ("fuso_utc_antes", [{"dt": "2026-10-20T13:59:00+00:00", "alta": 22.0}], 21.78),
        ("empate_de_tempo", [{"dt": "2026-10-20T12:00:00-03:00", "alta": 30.0},
                             {"dt": "2026-10-20T12:00:00-03:00", "alta": 40.0}], 21.78),
        ("fora_de_ordem", [{"dt": "2026-10-20T13:00:00-03:00", "alta": 30.0},
                           {"dt": "2026-10-20T12:00:00-03:00", "alta": 25.0},
                           {"dt": "2026-10-20T10:00:00-03:00", "alta": 25.0}], 21.78),
    ]
    for nome, barras, alvo in cenarios:
        entrada = {"barras": barras, "alvo": alvo, "criada": CRIADA}
        out.append(_caso_achar(f"achar_{nome}", entrada))
    for i in range(30):
        barras = _horarias(rng, rng.randint(1, 40))
        alvo = round(rng.uniform(9, 13), 2)
        entrada = {"barras": [{"dt": b["dt"], "alta": b["alta"]} for b in barras], "alvo": alvo, "criada": CRIADA}
        out.append(_caso_achar(f"achar_aleatorio_{i}", entrada))
    return out


def _caso_achar(nome, entrada):
    barras = _barras_alta(entrada)
    r = mt.achar_barra(barras, entrada["alvo"], _dt(entrada["criada"]))
    indice = None if r is None else next(i for i, b in enumerate(barras) if b is r)
    return base.caso(nome, "achar_barra", entrada, {"indice": indice})


def _niveis():
    niveis_a = [{"desde": "2026-10-20", "stop": 5.0, "calc_em": "2026-10-20"}]
    niveis_b = [{"desde": "2026-10-20", "stop": 5.0, "calc_em": "x"}, {"desde": "2026-10-22", "stop": 9.0, "calc_em": "x"},
                {"desde": "2026-10-23", "stop": 7.0, "calc_em": "x"}]
    datas = ["2026-10-19", "2026-10-20", "2026-10-21", "2026-10-22", "2026-10-23", "2026-10-24"]
    out = [base.caso("nivel_sem_niveis", "nivel_vigente", {"niveis": [], "data": "2026-10-21"},
                     {"nivel": mt.nivel_vigente([], "2026-10-21")})]
    for nome, niveis in (("um_nivel", niveis_a), ("tres_niveis", niveis_b)):
        for d in datas:
            out.append(base.caso(f"nivel_{nome}_{d}", "nivel_vigente", {"niveis": niveis, "data": d},
                                 {"nivel": mt.nivel_vigente(niveis, d)}))
    return out


def _caso_stop(nome, entrada):
    barras = _barras_stop(entrada)
    r = mt.achar_barra_stop(barras, entrada["niveis"], _dt(entrada["criada"]))
    if r is None:
        saida = {"indice": None}
    else:
        saida = {"indice": next(i for i, b in enumerate(barras) if b is r[0]), "nivel": r[1]}
    return base.caso(nome, "achar_barra_stop", entrada, saida)


def _achar_barra_stop():
    out = []
    n9 = [{"desde": "2026-10-20", "stop": 9.0, "calc_em": "2026-10-20"}]
    n_tres = [{"desde": "2026-10-20", "stop": 5.0, "calc_em": "x"}, {"desde": "2026-10-22", "stop": 9.0, "calc_em": "x"}]

    def b(texto, alta, baixa, abre=None):
        return {"dt": texto, "alta": alta, "baixa": baixa, "abre": abre}
    cenarios = [
        ("igual_ao_stop", [b("2026-10-21T10:00:00-03:00", 10, 9.01), b("2026-10-21T11:00:00-03:00", 10, 9.00)], n9),
        ("acima_do_stop", [b("2026-10-21T10:00:00-03:00", 10, 9.01)], n9),
        ("antes_da_criacao", [b("2026-10-20T10:00:00-03:00", 10, 1)], n9),
        ("tolerancia_dentro", [b("2026-10-21T10:00:00-03:00", 10, 9.0 + 5e-10)], n9),
        ("tolerancia_fora", [b("2026-10-21T10:00:00-03:00", 10, 9.0 + 2e-9)], n9),
        ("sem_minima", [b("2026-10-21T10:00:00-03:00", 10, None), b("2026-10-21T11:00:00-03:00", 10, 8.0)], n9),
        ("so_sem_minima", [b("2026-10-21T10:00:00-03:00", 10, None)], n9),
        ("desde_posterior_nao_vale", [b("2026-10-21T10:00:00-03:00", 10, 8.0)], n_tres),
        ("desde_posterior_vale", [b("2026-10-22T10:00:00-03:00", 10, 8.0)], n_tres),
        ("sem_niveis", [b("2026-10-21T10:00:00-03:00", 10, 0.1)], []),
        ("dia_no_proprio_fuso", [b("2026-10-21T02:00:00+00:00", 10, 4.0)], n_tres),
        ("fora_de_ordem", [b("2026-10-22T11:00:00-03:00", 10, 3.0), b("2026-10-22T10:00:00-03:00", 10, 4.0)], n_tres),
    ]
    for nome, barras, niveis in cenarios:
        out.append(_caso_stop(f"stop_{nome}", {"barras": barras, "niveis": niveis, "criada": CRIADA}))
    rng = random.Random(4)
    for i in range(30):
        barras = _horarias(rng, rng.randint(1, 40))
        niveis = [{"desde": "2026-10-20", "stop": round(rng.uniform(6, 10), 2), "calc_em": "x"}]
        if rng.random() < 0.5:
            niveis.append({"desde": "2026-10-21", "stop": round(rng.uniform(8, 11), 2), "calc_em": "x"})
        out.append(_caso_stop(f"stop_aleatorio_{i}", {"barras": barras, "niveis": niveis, "criada": CRIADA}))
    return out


def _execucao():
    out = []
    for nome, abre, nivel in (("sem_abertura", None, 9.0), ("gap", 8.5, 9.0), ("abertura_acima", 9.2, 9.0),
                              ("abertura_igual", 9.0, 9.0), ("tolerancia_dentro", 9.0 - 5e-10, 9.0),
                              ("tolerancia_fora", 9.0 - 2e-9, 9.0), ("gap_ate_zero", 0.0, 9.0),
                              ("gap_negativo", -3.0, 9.0), ("gap_fracao_de_centavo", 8.4999, 9.0),
                              ("gap_meio_centavo", 8.455, 9.0), ("gap_abaixo_do_minimo", 0.004, 9.0)):
        preco, gap = mt.preco_execucao_stop({"abre": abre}, nivel)
        out.append(base.caso(f"execucao_{nome}", "preco_execucao_stop", {"abre": abre, "nivel": nivel},
                             {"preco": preco, "gap": gap}))
    rng = random.Random(4)
    for i in range(40):
        abre = round(rng.uniform(5, 12), rng.choice([2, 3, 4]))
        nivel = round(rng.uniform(6, 11), 2)
        preco, gap = mt.preco_execucao_stop({"abre": abre}, nivel)
        out.append(base.caso(f"execucao_aleatoria_{i}", "preco_execucao_stop", {"abre": abre, "nivel": nivel},
                             {"preco": preco, "gap": gap}))
    return out


def barras_aleatorias(n=120):
    r = random.Random(7)
    preco, saida = 10.0, []
    for i in range(n):
        abre = preco
        preco = max(1.0, preco + r.uniform(-0.6, 0.7))
        saida.append({"data": date(2026, 6, 1) + timedelta(days=i), "abre": abre,
                      "alta": max(abre, preco) + r.uniform(0, 0.4), "baixa": min(abre, preco) - r.uniform(0, 0.4),
                      "fech": preco})
    return saida


def _diarias(n=30, fim="2026-10-22", alta=11.0, baixa=9.0, fech=10.0):
    ultimo = date.fromisoformat(fim)
    return [{"data": ultimo - timedelta(days=n - 1 - i), "abre": fech, "alta": alta, "baixa": baixa, "fech": fech}
            for i in range(n)]


def _meta_stop(stop, criada=CRIADA, movel=True, niveis=True):
    m = {"id": "meta-s", "ticker": "PETR4", "tipo": "Ação", "lote_id": "L1", "qtd": 100, "gatilho": "stop",
         "stop_inicial": stop, "stop_atual": stop, "movel": movel, "criada_em": criada}
    if niveis:
        m["niveis"] = [{"desde": criada[:10], "stop": stop, "calc_em": criada[:10]}]
    return m


def _caso_atualizar(nome, meta, barras, hoje):
    """Registra o caso; `meta` e `barras` são os objetos do Python (a meta é mutada pela chamada)."""
    entrada = {"meta": copy.deepcopy(meta), "barras": copy.deepcopy(barras), "hoje": hoje.isoformat()}
    mudou = mt.atualizar_stop_movel(meta, barras, hoje)
    return base.caso(nome, "atualizar_stop_movel", entrada, {"mudou": mudou, "meta": meta})


def _atualizar():
    out = []
    d25, d20 = date(2026, 10, 25), date(2026, 10, 20)
    out.append(_caso_atualizar("subida", _meta_stop(4.0), _diarias(), d25))
    out.append(_caso_atualizar("acima_do_chandelier", _meta_stop(7.0), _diarias(), d25))
    out.append(_caso_atualizar("hoje_igual_a_criacao", _meta_stop(4.0), _diarias(), d20))
    out.append(_caso_atualizar("poucos_pregoes", _meta_stop(4.0), _diarias(n=10), d25))
    out.append(_caso_atualizar("sem_barras", _meta_stop(4.0), [], d25))
    out.append(_caso_atualizar("nao_movel", _meta_stop(4.0, movel=False), _diarias(), d25))
    out.append(_caso_atualizar("sem_chave_movel", {k: v for k, v in _meta_stop(4.0).items() if k != "movel"},
                               _diarias(), d25))
    alvo = {"id": "meta-a", "ticker": "PETR4", "tipo": "Ação", "lote_id": "L1", "qtd": 100, "preco_alvo": 20.0,
            "criada_em": CRIADA}
    out.append(_caso_atualizar("meta_de_alvo", alvo, _diarias(), d25))
    out.append(_caso_atualizar("sem_chave_niveis_sobe", _meta_stop(4.0, niveis=False), _diarias(), d25))
    out.append(_caso_atualizar("sem_chave_niveis_nao_sobe", _meta_stop(7.0, niveis=False), _diarias(), d25))
    out.append(_caso_atualizar("criada_sem_fuso", _meta_stop(4.0, criada="2026-10-20T11:00:00"), _diarias(), d25))
    out.append(_caso_atualizar("criada_em_utc", _meta_stop(4.0, criada="2026-10-21T01:00:00+00:00"), _diarias(), d25))
    out.append(_caso_atualizar("criada_depois_dos_pregoes", _meta_stop(4.0, criada="2026-10-23T11:00:00-03:00"),
                               _diarias(), date(2026, 10, 30)))
    desordenadas = list(reversed(_diarias()))
    out.append(_caso_atualizar("barras_fora_de_ordem", _meta_stop(4.0), desordenadas, d25))
    out.append(_caso_atualizar("pregao_de_hoje_ignorado", _meta_stop(4.0), _diarias(),
                               date(2026, 10, 22)))
    out.append(_caso_atualizar("stop_atual_acima_dos_niveis", {**_meta_stop(4.0), "stop_atual": 5.5}, _diarias(), d25))
    grande = _diarias(n=40, alta=1000.0, baixa=900.0, fech=950.0)
    out.append(_caso_atualizar("precos_grandes", _meta_stop(4.0), grande, d25))
    sobe = [{"data": date(2026, 9, 1) + timedelta(days=i), "abre": 10.0 + i * 0.5, "alta": 11.0 + i * 0.5,
             "baixa": 9.0 + i * 0.5, "fech": 10.0 + i * 0.5} for i in range(40)]
    out.append(_caso_atualizar("tendencia_de_alta", _meta_stop(4.0, criada="2026-09-02T11:00:00-03:00"), sobe,
                               date(2026, 10, 15)))
    # Idempotência: a segunda chamada sobre a mesma meta.
    meta = _meta_stop(4.0)
    barras = _diarias()
    mt.atualizar_stop_movel(meta, barras, d25)
    out.append(_caso_atualizar("segunda_chamada", meta, barras, d25))
    # Barras aleatórias (Random(7)): exportadas e usadas com três inícios.
    barras = barras_aleatorias(120)
    for inicio, hoje in ((3.0, date(2026, 9, 20)), (8.0, date(2026, 9, 29)), (1.0, date(2026, 10, 1))):
        meta = _meta_stop(inicio, criada="2026-06-05T11:00:00-03:00")
        out.append(_caso_atualizar(f"aleatorias_{inicio}", meta, barras, hoje))
    return out


def _aleatorias():
    return [base.caso(f"barras_aleatorias_{n}", "barras_aleatorias", {"n": n}, {"barras": barras_aleatorias(n)})
            for n in (120, 60)]


def casos():
    return (_achar_barra() + _niveis() + _achar_barra_stop() + _execucao() + _atualizar() + _aleatorias())
