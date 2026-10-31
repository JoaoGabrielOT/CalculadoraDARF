"""Referências da mesclagem entre aparelhos (nucleo.py:977-1168).

Funções (campo `funcao` de cada caso); toda entrada é copiada antes da chamada, porque o Python devolve às vezes o
mesmo dicionário recebido ou o altera no lugar:
- mesclar_mes: entrada {local, remoto} (cada um pode ser null); saída {"mes": ...}.
- deduplicar_auto: entrada {meses}; saída {"alterados": [...], "meses": ...}.
- mesclar_lista: entrada {lista: "amigos"|"radar", local, remoto, excl, prefixo}; saída {"itens": [...]}.
- mesclar_metas: entrada {local, remoto}; saída {"metas": [...]}.
- unir_niveis: entrada {a, b}; saída {"niveis": [...]}.
- execucao_antes: entrada {a, b}; saída {"ordem": -1|0|1}.
- resolver_oco: entrada {meses, metas}; saída {"alterados", "meses", "metas", "avisos"} (relógio congelado).
"""
import copy
import itertools

from . import base

nc = base.nc

ALVO = {"id": "meta-a", "ticker": "PETR4", "tipo": "Ação", "lote_id": "L1", "qtd": 100, "preco_alvo": 20.0,
        "criada_em": "2026-10-20T11:00:00-03:00", "status": "ativa", "mod": 1.5}
STOP = {"id": "meta-a", "ticker": "PETR4", "tipo": "Ação", "lote_id": "L1", "qtd": 100, "gatilho": "stop",
        "stop_inicial": 5.0, "movel": True, "stop_atual": 5.0, "niveis": [], "criada_em": "2026-10-20T11:00:00-03:00",
        "status": "ativa", "mod": 1.5}
N0 = {"desde": "2026-10-20", "stop": 5.0, "calc_em": "2026-10-20"}


def _c(x):
    return copy.deepcopy(x)


# ------------------------------------------------------------------ mesclar_mes

def _v(i, data="2026-10-05", qtd=10, preco=11.0, mod=10.0):
    return {"id": i, "data": data, "qtd": qtd, "preco": preco, "mod": mod}


def _l(i, vendas=(), ticker="PETR4", qtd=100, preco=10.0, mod=10.0, **extra):
    l = {"id": i, "ticker": ticker, "tipo": "Ação", "data_compra": "2026-10-01", "qtd": qtd, "preco": preco,
         "vendas": list(vendas), "mod": mod}
    l.update(extra)
    return l


def _m(lotes=(), mod=10.0, fechado=False, darf=0.0, excl=None, **extra):
    d = {"mes": "2026-10", "fechado": fechado, "darf_anterior": darf, "lotes": list(lotes),
         "excluidos": excl or {}, "mod": mod}
    d.update(extra)
    return d


RESUMO = {"vendas_acoes_st": 100.0, "isento": False, "bruto": 10.0, "custos": 1.0, "imp_st": 1.8, "imp_dt": 0.0,
          "imposto_total": 1.8, "irrf": 0.0, "lucro_liquido": 7.2, "darf_mes": 1.8, "darf_anterior": 0.0,
          "darf": 1.8}


def _mes_base():
    return _m([_l("L1", [_v("v1"), _v("v2", data="2026-10-06")]), _l("L2", ticker="VALE3")])


def _casos_mes():
    out = []

    def caso(nome, local, remoto):
        entrada = {"local": _c(local), "remoto": _c(remoto)}
        saida = {"mes": nc.mesclar_mes(_c(local), _c(remoto))}
        out.append(base.caso(nome, "mesclar_mes", entrada, saida))

    b = _mes_base()
    caso("identicos", b, b)
    caso("local_nulo", None, b)
    caso("remoto_nulo", b, None)
    caso("ambos_nulos", None, None)
    caso("local_nulo_com_retroativo", None, _m([_l("L1")], retroativo=True))
    # edição de lote: mod diferente (local mais novo / remoto mais novo / empate)
    for nome, ml, mr in (("local_mais_novo", 20.0, 15.0), ("remoto_mais_novo", 15.0, 20.0), ("empate_local_vence", 15.0, 15.0)):
        loc = _m([_l("L1", [_v("v1")], qtd=200, mod=ml)], mod=ml)
        rem = _m([_l("L1", [_v("v1")], qtd=300, mod=mr)], mod=mr, darf=5.0, fechado=True)
        caso("lote_editado_" + nome, loc, rem)
    # edição de venda
    for nome, ml, mr in (("local_mais_novo", 20.0, 15.0), ("remoto_mais_novo", 15.0, 20.0), ("empate_local_vence", 15.0, 15.0)):
        loc = _m([_l("L1", [_v("v1", preco=12.0, mod=ml)])])
        rem = _m([_l("L1", [_v("v1", preco=13.0, mod=mr)])])
        caso("venda_editada_" + nome, loc, rem)
    # exclusões: exclusão maior, igual e menor que o mod do registro
    for nome, t in (("maior", 11.0), ("igual", 10.0), ("menor", 9.0)):
        loc = _m([_l("L1", [_v("v1")]), _l("L2")])
        rem = _m([_l("L1", [_v("v1")])], excl={"L2": t, "v1": t})
        caso("exclusao_remota_" + nome, loc, rem)
        caso("exclusao_local_" + nome, rem, loc)
    # lote excluído num lado e editado no outro
    caso("exclusao_menor_que_edicao",
         _m([_l("L1", [_v("v1")], mod=30.0)]), _m([], excl={"L1": 20.0, "v1": 20.0}))
    caso("exclusao_maior_que_edicao",
         _m([_l("L1", [_v("v1")], mod=30.0)]), _m([], excl={"L1": 40.0, "v1": 40.0}))
    # exclusões dos dois lados: vale o maior carimbo de cada id
    caso("exclusoes_dos_dois_lados",
         _m([_l("L1")], excl={"a": 5.0, "b": 9.0, "c": 1.0}), _m([_l("L1")], excl={"a": 7.0, "b": 2.0, "d": 3.0}))
    caso("exclusoes_so_no_remoto", _m([_l("L1")]), _m([_l("L1")], excl={"x": 4.5}))
    # lote só em um dos lados (ordem: locais primeiro, depois os só do remoto)
    caso("lotes_em_lados_diferentes",
         _m([_l("L3"), _l("L1")]), _m([_l("L2"), _l("L1"), _l("L4")]))
    # venda trocando de lote
    for nome, ml, mr in (("local_mais_novo", 20.0, 15.0), ("remoto_mais_novo", 15.0, 20.0), ("empate", 15.0, 15.0)):
        loc = _m([_l("L1", [_v("v1", mod=ml)]), _l("L2")])
        rem = _m([_l("L1"), _l("L2", [_v("v1", mod=mr)])])
        caso("venda_troca_de_lote_" + nome, loc, rem)
    # a venda vai para um lote excluído
    caso("venda_em_lote_excluido",
         _m([_l("L1", [_v("v1", mod=20.0)])]), _m([_l("L1", mod=5.0)], excl={"L1": 6.0}))
    # ordenação das vendas: data e id (inclusive fora do plano básico)
    caso("vendas_ordenadas",
         _m([_l("L1", [_v("b", data="2026-10-09"), _v("a", data="2026-10-09"), _v("z", data="2026-10-01")])]),
         _m([_l("L1", [_v("c", data="2026-10-09"), _v("A", data="2026-10-09")])]))
    caso("vendas_ids_unicode",
         _m([_l("L1", [_v("\U0001F600"), _v("｡"), _v("é")])]), _m([_l("L1", [_v("e")])]))
    # metadados do mês: fica o do lado de maior mod; resumo só se fechado
    for nome, loc, rem in (
            ("resumo_aberto_descartado", _m([_l("L1")], mod=20.0, resumo=RESUMO), _m([_l("L1")], mod=10.0)),
            ("resumo_fechado_mantido", _m([_l("L1")], mod=20.0, fechado=True, resumo=RESUMO),
             _m([_l("L1")], mod=10.0)),
            ("resumo_do_perdedor_nao_vem", _m([_l("L1")], mod=20.0, fechado=True),
             _m([_l("L1")], mod=10.0, fechado=True, resumo=RESUMO)),
            ("resumo_do_remoto_vencedor", _m([_l("L1")], mod=10.0), _m([_l("L1")], mod=20.0, fechado=True,
                                                                         resumo=RESUMO)),
            ("resumo_fechado_empate_local", _m([_l("L1")], mod=10.0, fechado=True, resumo=RESUMO, darf=3.5),
             _m([_l("L1")], mod=10.0, fechado=True, resumo={**RESUMO, "darf": 9.0}, darf=7.0)),
            ("darf_anterior_do_vencedor", _m([_l("L1")], mod=10.0, darf=1.25), _m([_l("L1")], mod=11.0, darf=2.5)),
            ("retroativo_nao_sai", _m([_l("L1")], mod=10.0, retroativo=True), _m([_l("L1")], mod=5.0))):
        caso(nome, loc, rem)
    caso("fechado_so_no_remoto_mais_novo", _m([_l("L1")], mod=5.0), _m([_l("L1")], mod=6.0, fechado=True))
    caso("origem_do_lote_mantida",
         _m([_l("L1~2026-11", [_v("v1")], origem="L1", mod=3.0)]), _m([_l("L1~2026-11", origem="L1", mod=4.0)]))
    return out


# ------------------------------------------------------------------ deduplicar_auto

def _casos_dedup():
    out = []

    def caso(nome, meses):
        entrada = {"meses": _c(meses)}
        m = _c(meses)
        alterados = nc.deduplicar_auto(m)
        out.append(base.caso(nome, "deduplicar_auto", entrada, {"alterados": alterados, "meses": m}))

    def mes(nome, lotes):
        return {**_m(lotes), "mes": nome}

    a1 = _v("auto-meta-1")
    caso("sem_automaticas", {"2026-09": mes("2026-09", [_l("L1", [_v("v1")])]),
                             "2026-10": mes("2026-10", [_l("L1", [_v("v1")])])})
    caso("fica_a_do_mes_mais_antigo", {"2026-10": mes("2026-10", [_l("L1", [_v("auto-meta-1", mod=1.0)])]),
                                       "2026-09": mes("2026-09", [_l("L1", [_v("auto-meta-1", mod=2.0)])])})
    caso("tres_meses", {"2026-11": mes("2026-11", [_l("L1", [a1])]), "2026-09": mes("2026-09", [_l("L1", [a1])]),
                        "2026-10": mes("2026-10", [_l("L1", [a1, _v("auto-meta-2")])])})
    caso("duas_no_mesmo_lote", {"2026-10": mes("2026-10", [_l("L1", [a1, a1, _v("v1")])])})
    caso("em_lotes_do_mesmo_mes", {"2026-10": mes("2026-10", [_l("L1", [a1]), _l("L2", [a1, _v("auto-meta-2")])])})
    caso("ids_comuns_repetidos_ficam", {"2026-09": mes("2026-09", [_l("L1", [_v("v1")])]),
                                        "2026-10": mes("2026-10", [_l("L1", [_v("v1")])])})
    caso("prefixo_parecido_nao_conta", {"2026-09": mes("2026-09", [_l("L1", [_v("auto_x"), _v("Auto-x")])]),
                                        "2026-10": mes("2026-10", [_l("L1", [_v("auto_x"), _v("Auto-x")])])})
    caso("so_um_mes_alterado", {"2026-08": mes("2026-08", [_l("L1", [a1])]),
                                "2026-09": mes("2026-09", [_l("L1", [_v("v9")])]),
                                "2026-10": mes("2026-10", [_l("L1", [a1])])})
    caso("sem_meses", {})
    return out


# ------------------------------------------------------------------ mesclar_lista

def _casos_lista():
    out = []

    def caso(nome, lista, local, remoto, excl):
        chave, prefixo = ("email", "amigos") if lista == "amigos" else ("ticker", "radar")
        entrada = {"lista": lista, "local": _c(local), "remoto": _c(remoto), "excl": _c(excl), "prefixo": prefixo}
        saida = {"itens": nc.mesclar_lista(_c(local), _c(remoto), chave, _c(excl), prefixo)}
        out.append(base.caso(nome, "mesclar_lista", entrada, saida))

    def am(email, mod, desde="2026-09-01"):
        return {"email": email, "desde": desde, "mod": mod}

    def rd(t, mod, nome="", pos=None, desde="2026-08-01"):
        r = {"ticker": t, "nome": nome or t, "desde": desde, "mod": mod}
        if pos is not None:
            r["pos"] = pos
        return r

    caso("amigos_vazios", "amigos", [], [], {})
    caso("amigos_so_local", "amigos", [am("a@x", 1.0)], [], {})
    caso("amigos_so_remoto", "amigos", [], [am("a@x", 1.0)], {})
    caso("amigos_local_mais_novo", "amigos", [am("a@x", 2.0, "2026-10-01")], [am("a@x", 1.0)], {})
    caso("amigos_remoto_mais_novo", "amigos", [am("a@x", 1.0)], [am("a@x", 2.0, "2026-10-01")], {})
    caso("amigos_empate_local_vence", "amigos", [am("a@x", 1.0, "2026-10-01")], [am("a@x", 1.0)], {})
    caso("amigos_ordem", "amigos", [am("c@x", 1.0), am("a@x", 1.0)], [am("b@x", 1.0), am("a@x", 0.5), am("d@x", 1.0)], {})
    for nome, t in (("maior", 5.0), ("igual", 3.0), ("menor", 2.0)):
        caso("amigos_exclusao_" + nome, "amigos", [am("a@x", 3.0), am("b@x", 3.0)], [am("c@x", 3.0)],
             {"amigos:a@x": t, "amigos:c@x": t, "radar:b@x": 99.0})
    caso("amigos_mod_zero_e_exclusao_zero", "amigos", [am("a@x", 0)], [], {"amigos:a@x": 0})
    caso("radar_vazio", "radar", [], [], {})
    caso("radar_edicao_local", "radar", [rd("PETR4", 5.0, "Nova", pos=1)], [rd("PETR4", 4.0, "Velha", pos=0)], {})
    caso("radar_edicao_remota", "radar", [rd("PETR4", 4.0, "Velha", pos=0)], [rd("PETR4", 5.0, "Nova")], {})
    caso("radar_empate", "radar", [rd("PETR4", 4.0, "Local", pos=3)], [rd("PETR4", 4.0, "Remoto", pos=4)], {})
    caso("radar_ordem", "radar", [rd("VALE3", 1.0), rd("ITUB4", 1.0), rd("PETR4", 1.0)],
         [rd("PETR4", 0.5), rd("WEGE3", 1.0), rd("ABEV3", 1.0)], {})
    for nome, t in (("maior", 5.0), ("igual", 3.0), ("menor", 2.0)):
        caso("radar_exclusao_" + nome, "radar", [rd("PETR4", 3.0, pos=0), rd("VALE3", 3.0)], [rd("WEGE3", 3.0, pos=2)],
             {"radar:PETR4": t, "radar:WEGE3": t, "amigos:VALE3": 99.0})
    caso("radar_exclusao_vence_so_a_do_escolhido", "radar", [rd("PETR4", 1.0)], [rd("PETR4", 6.0)],
         {"radar:PETR4": 4.0})
    return out


# ------------------------------------------------------------------ mesclar_metas

def _rica(base_, **kw):
    """Registro da versão nova: com OCO, níveis e motivo de cancelamento."""
    m = _c(base_)
    m.update(oco="oco-1", sugestao={"stop": 5.0, "atr": 0.5})
    if base_.get("gatilho") == "stop":
        m.update(niveis=[N0, {"desde": "2026-10-22", "stop": 7.0, "calc_em": "2026-10-21"}], stop_atual=7.0)
    m.update(kw)
    return m


def _pobre(base_, **kw):
    """Registro de um aparelho antigo: só as 12 colunas (sem gatilho, stop, níveis, OCO...)."""
    m = {k: v for k, v in base_.items() if k not in ("gatilho", "stop_inicial", "stop_atual", "movel", "niveis")}
    m.setdefault("preco_alvo", 20.0)
    m.update(kw)
    return m


def _casos_metas():
    out = []

    def caso(nome, local, remoto):
        entrada = {"local": _c(local), "remoto": _c(remoto)}
        out.append(base.caso(nome, "mesclar_metas", entrada, {"metas": nc.mesclar_metas(_c(local), _c(remoto))}))

    status = ("ativa", "cancelada", "executada")
    execucao = {"venda_id": "auto-meta-a", "data": "2026-10-22", "hora": "10:00"}

    def com_status(m, st, mod, rico):
        extra = {"status": st, "mod": mod}
        if st == "executada":
            extra["execucao"] = execucao
        if st == "cancelada" and rico:
            extra.update(cancelada_por="meta-x", cancelada_detalhe="Cancelada automaticamente (OCO): alvo executado em 22/10")
        return extra

    pares_gatilho = {"alvo_alvo": (ALVO, ALVO), "stop_stop": (STOP, STOP), "alvo_stop": (ALVO, STOP),
                     "stop_alvo": (STOP, ALVO)}
    for (sl, sr), (nm, mods), (ng, (bl, br)), rico_local in itertools.product(
            itertools.product(status, status),
            (("local_novo", (9.0, 3.0)), ("empate", (5.0, 5.0)), ("remoto_novo", (3.0, 9.0))),
            pares_gatilho.items(), (True, False)):
        # o lado "rico" é o da versão nova; o outro vem de um aparelho antigo (12 colunas)
        mk_l = (_rica if rico_local else _pobre)
        mk_r = (_pobre if rico_local else _rica)
        local = mk_l(bl, **com_status(bl, sl, mods[0], rico_local))
        remoto = mk_r(br, **com_status(br, sr, mods[1], not rico_local))
        caso(f"matriz_{sl}_{sr}_{nm}_{ng}_{'rico_local' if rico_local else 'rico_remoto'}", [local], [remoto])

    # stop móvel nos dois lados
    n1 = {"desde": "2026-10-21", "stop": 6.0, "calc_em": "2026-10-20"}
    n2l = {"desde": "2026-10-22", "stop": 7.0, "calc_em": "2026-10-21"}
    n2r = {"desde": "2026-10-22", "stop": 6.5, "calc_em": "2026-10-21"}
    loc = {**STOP, "mod": 1, "stop_atual": 7.0, "niveis": [N0, n2l]}
    rem = {**STOP, "mod": 2, "stop_atual": 6.0, "niveis": [N0, n1, n2r]}
    caso("stop_movel_dos_dois_lados", [loc], [rem])
    caso("stop_movel_dos_dois_lados_invertido", [rem], [loc])
    caso("stop_movel_nivel_maior_que_stop_atual", [{**loc, "stop_atual": 5.0}], [{**rem, "stop_atual": 5.5}])
    caso("stop_movel_niveis_ausentes_nos_dois", [{**STOP, "mod": 1, "stop_atual": 6.0}], [{**STOP, "mod": 2}])
    caso("stop_movel_nivel_ausente_no_local", [{k: v for k, v in loc.items() if k != "niveis"}], [rem])
    caso("stop_movel_nivel_vazio_e_cheio", [{**loc, "niveis": []}], [rem])
    caso("stop_movel_executado_no_local", [{**loc, "status": "executada", "execucao": execucao}], [rem])
    caso("stop_movel_executado_no_remoto", [loc], [{**rem, "status": "executada", "execucao": execucao}])
    caso("stop_movel_cancelado_no_local", [{**loc, "status": "cancelada", "mod": 0.5}], [rem])
    caso("stop_movel_so_um_movel", [loc], [{**rem, "movel": False}])
    caso("stop_movel_nenhum_movel", [{**loc, "movel": False}], [{**rem, "movel": False}])
    caso("stop_movel_mesma_data_stop_maior_no_remoto", [{**loc, "niveis": [n2r]}], [{**rem, "niveis": [n2l]}])
    caso("stop_movel_mesma_data_stop_igual", [{**loc, "niveis": [{**n2l, "calc_em": "L"}]}],
         [{**rem, "niveis": [{**n2l, "calc_em": "R"}]}])
    # várias metas
    caso("varias_metas_ordenadas_por_criacao_e_id",
         [{**ALVO, "id": "m3", "criada_em": "2026-10-22T10:00:00-03:00"}, {**ALVO, "id": "m1"}, {**ALVO, "id": "m2"}],
         [{**ALVO, "id": "m2", "mod": 9.0, "qtd": 7}, {**ALVO, "id": "m0", "criada_em": "2026-10-25T10:00:00-03:00"},
          {**ALVO, "id": "m4"}])
    caso("vazias", [], [])
    caso("so_remoto", [], [ALVO])
    caso("so_local", [ALVO], [])
    # campos que só o perdedor tem
    caso("gatilho_vazio_no_perdedor_nao_copia", [{**ALVO, "mod": 9.0}], [{**ALVO, "oco": "", "sugestao": None}])
    caso("movel_falso_do_perdedor_e_copiado",
         [{k: v for k, v in STOP.items() if k not in ("movel", "niveis")} | {"mod": 9.0}],
         [{**STOP, "movel": False, "mod": 1.0}])
    caso("niveis_vazio_do_perdedor_e_copiado",
         [{k: v for k, v in STOP.items() if k not in ("niveis",)} | {"mod": 9.0}], [{**STOP, "mod": 1.0}])
    caso("alvo_vencedor_nao_recebe_stop", [{**ALVO, "mod": 9.0}], [{**STOP, "id": "meta-a", "mod": 1.0}])
    caso("chave_desconhecida_preservada", [{**ALVO, "mod": 9.0, "futuro": {"a": [1, 2]}}], [{**ALVO, "oco": "o"}])
    caso("ultimo_erro_do_vencedor", [{**ALVO, "mod": 9.0, "ultimo_erro": "falhou"}], [{**ALVO, "oco": "o"}])
    return out


# ------------------------------------------------------------------ unir_niveis

def _casos_niveis():
    out = []

    def caso(nome, a, b):
        out.append(base.caso(nome, "unir_niveis", {"a": _c(a), "b": _c(b)}, {"niveis": nc._unir_niveis(_c(a), _c(b))}))

    def n(desde, stop, calc="2026-10-20"):
        return {"desde": desde, "stop": stop, "calc_em": calc}

    caso("ambos_nulos", None, None)
    caso("ambos_vazios", [], [])
    caso("a_nulo", None, [n("2026-10-21", 6.0), n("2026-10-20", 5.0)])
    caso("b_nulo", [n("2026-10-21", 6.0)], None)
    caso("maior_stop_na_mesma_data", [n("2026-10-21", 6.0, "A")], [n("2026-10-21", 6.5, "B")])
    caso("maior_stop_na_mesma_data_invertido", [n("2026-10-21", 6.5, "A")], [n("2026-10-21", 6.0, "B")])
    caso("stop_igual_fica_o_primeiro", [n("2026-10-21", 6.0, "A")], [n("2026-10-21", 6.0, "B")])
    caso("ordena_por_data", [n("2026-10-23", 8.0), n("2026-10-20", 5.0)], [n("2026-10-22", 7.0), n("2026-10-21", 6.0)])
    caso("duplicado_dentro_do_mesmo_lado", [n("2026-10-21", 6.0, "A"), n("2026-10-21", 7.0, "B")], [])
    return out


# ------------------------------------------------------------------ execucao_antes

def _casos_execucao_antes():
    out = []

    def caso(nome, a, b):
        out.append(base.caso(nome, "execucao_antes", {"a": _c(a), "b": _c(b)}, {"ordem": nc._execucao_antes(_c(a), _c(b))}))

    def al(ex=None, id_="meta-a", **kw):
        m = {**ALVO, "id": id_, **kw}
        if ex is not None:
            m["execucao"] = ex
        return m

    def st(ex=None, id_="meta-s", **kw):
        m = {**STOP, "id": id_, **kw}
        if ex is not None:
            m["execucao"] = ex
        return m

    caso("data_do_a_mais_cedo", al({"data": "2026-10-21"}), st({"data": "2026-10-22"}))
    caso("data_do_a_mais_tarde", al({"data": "2026-10-23"}), st({"data": "2026-10-22"}))
    caso("data_vence_a_barra", al({"data": "2026-10-21", "barra_ts": 900}), st({"data": "2026-10-22", "barra_ts": 100}))
    caso("barra_ts_menor_no_a", al({"data": "2026-10-22", "barra_ts": 100, "hora": "15:00"}),
         st({"data": "2026-10-22", "barra_ts": 200, "hora": "09:00"}))
    caso("barra_ts_menor_no_b", al({"data": "2026-10-22", "barra_ts": 300}), st({"data": "2026-10-22", "barra_ts": 200}))
    caso("barra_ts_flutuante", al({"data": "2026-10-22", "barra_ts": 100.5}), st({"data": "2026-10-22", "barra_ts": 100.25}))
    caso("barra_ts_so_em_um_lado_usa_a_hora", al({"data": "2026-10-22", "barra_ts": 100, "hora": "10:00"}),
         st({"data": "2026-10-22", "hora": "11:00"}))
    caso("barra_ts_zero_usa_a_hora", al({"data": "2026-10-22", "barra_ts": 0, "hora": "12:00"}),
         st({"data": "2026-10-22", "barra_ts": 50, "hora": "11:00"}))
    caso("barra_ts_negativo_usa_a_hora", al({"data": "2026-10-22", "barra_ts": -5, "hora": "10:00"}),
         st({"data": "2026-10-22", "barra_ts": -9, "hora": "11:00"}))
    caso("hora_menor_no_a", al({"data": "2026-10-22", "hora": "10:00"}), st({"data": "2026-10-22", "hora": "10:30"}))
    caso("hora_menor_no_b", al({"data": "2026-10-22", "hora": "10:45"}), st({"data": "2026-10-22", "hora": "10:30"}))
    caso("hora_vazia_no_a_stop_vence", al({"data": "2026-10-22", "hora": ""}), st({"data": "2026-10-22", "hora": "10:00"}))
    caso("hora_vazia_no_b_stop_vence", al({"data": "2026-10-22", "hora": "10:00"}), st({"data": "2026-10-22", "hora": ""}))
    caso("stop_antes_do_alvo_no_empate", al({"data": "2026-10-22", "hora": "10:00"}), st({"data": "2026-10-22", "hora": "10:00"}))
    caso("alvo_depois_do_stop_no_empate", st({"data": "2026-10-22", "hora": "10:00"}), al({"data": "2026-10-22", "hora": "10:00"}))
    caso("dois_alvos_desempata_pelo_id", al({"data": "2026-10-22"}, id_="b"), al({"data": "2026-10-22"}, id_="a"))
    caso("dois_alvos_desempata_pelo_id_invertido", al({"data": "2026-10-22"}, id_="a"), al({"data": "2026-10-22"}, id_="b"))
    caso("dois_stops_desempata_pelo_id", st({"data": "2026-10-22"}, id_="b"), st({"data": "2026-10-22"}, id_="a"))
    caso("mesmo_id_empata", al({"data": "2026-10-22"}, id_="a"), al({"data": "2026-10-22"}, id_="a"))
    caso("id_unicode", al({"data": "2026-10-22"}, id_="\U0001F600"), al({"data": "2026-10-22"}, id_="｡"))
    caso("sem_execucao_nos_dois", al(None, id_="a"), st(None, id_="b"))
    caso("execucao_nula", al(None, id_="a", execucao=None), st({"data": "2026-10-22"}, id_="b"))
    caso("execucao_vazia", al({}, id_="a"), st({"data": ""}, id_="b"))
    caso("data_ausente_no_a", al({"hora": "10:00"}), st({"data": "2026-10-22", "hora": "10:00"}))
    return out


# ------------------------------------------------------------------ resolver_oco

def _casos_oco():
    out = []

    def caso(nome, meses, metas):
        entrada = {"meses": _c(meses), "metas": _c(metas)}
        m, ms, avisos = _c(meses), _c(metas), []
        with base.congelar():
            alterados = nc.resolver_oco(m, ms, avisos)
        out.append(base.caso(nome, "resolver_oco", entrada,
                             {"alterados": alterados, "meses": m, "metas": ms, "avisos": avisos}))

    def ex(base_, id_, data="2026-10-22", hora="10:00", oco="oco-1", status="executada", **extra):
        m = {**base_, "id": id_, "status": status, "oco": oco, "mod": 1.0,
             "execucao": {"data": data, "hora": hora, "venda_id": "auto-" + id_}}
        m.update(extra)
        return m

    def mes(nome, lotes, fechado=False, excl=None):
        return {**_m(lotes, fechado=fechado, excl=excl), "mes": nome}

    def auto(id_, data="2026-10-22", qtd=50, preco=20.0):
        return _v("auto-" + id_, data=data, qtd=qtd, preco=preco)

    a, s = ex(ALVO, "meta-a"), ex(STOP, "meta-s", data="2026-10-21")
    ab = {"2026-10": mes("2026-10", [_l("L1", [auto("meta-a"), auto("meta-s", "2026-10-21", preco=9.0), _v("v1")])])}
    caso("mes_aberto_stop_mais_cedo", ab, [a, s])
    caso("mes_aberto_alvo_mais_cedo", ab, [ex(ALVO, "meta-a", data="2026-10-20"), s])
    caso("mes_aberto_com_ultimo_erro", ab, [{**a, "ultimo_erro": "falhou"}, {**s, "ultimo_erro": "x"}])
    fech = {"2026-10": mes("2026-10", [_l("L1", [auto("meta-a"), auto("meta-s", "2026-10-21", preco=9.0)])], fechado=True)}
    caso("mes_fechado_gera_aviso", fech, [a, s])
    # a venda do alvo está no mês fechado, e a do stop no aberto
    misto = {"2026-09": mes("2026-09", [_l("L1", [auto("meta-a")])], fechado=True),
             "2026-10": mes("2026-10", [_l("L1", [auto("meta-s", "2026-10-21")])])}
    caso("vendas_em_meses_diferentes_fechado_e_aberto", misto, [a, s])
    caso("vendas_em_meses_diferentes_perdedora_no_aberto",
         {"2026-09": mes("2026-09", [_l("L1", [auto("meta-s", "2026-10-21")])], fechado=True),
          "2026-10": mes("2026-10", [_l("L1", [auto("meta-a")])])}, [a, s])
    caso("venda_da_perdedora_em_dois_lotes",
         {"2026-10": mes("2026-10", [_l("L1", [auto("meta-a")]), _l("L2", [auto("meta-a")])])}, [a, s])
    caso("venda_em_dois_lotes_mes_fechado_aviso_duplo",
         {"2026-10": mes("2026-10", [_l("L1", [auto("meta-a")]), _l("L2", [auto("meta-a")])], fechado=True)}, [a, s])
    caso("sem_venda_registrada", {"2026-10": mes("2026-10", [_l("L1", [_v("v1")])])}, [a, s])
    caso("sem_meses", {}, [a, s])
    caso("exclusoes_existentes_preservadas", {"2026-10": mes("2026-10", [_l("L1", [auto("meta-a")])], excl={"x": 5.0})}, [a, s])
    caso("mes_sem_chave_excluidos",
         {"2026-10": {k: v for k, v in mes("2026-10", [_l("L1", [auto("meta-a")])]).items() if k != "excluidos"}}, [a, s])
    # nenhum grupo a resolver
    caso("so_uma_executada_no_grupo", ab, [a, {**s, "status": "ativa"}])
    caso("grupo_com_uma_meta", ab, [a])
    caso("metas_sem_oco", ab, [{k: v for k, v in a.items() if k != "oco"}, {k: v for k, v in s.items() if k != "oco"}])
    caso("oco_vazio", ab, [{**a, "oco": ""}, {**s, "oco": ""}])
    caso("canceladas_nao_entram", ab, [{**a, "status": "cancelada"}, {**s, "status": "cancelada"}])
    caso("grupos_diferentes_nao_se_misturam", ab, [a, ex(STOP, "meta-s", oco="oco-2")])
    # três ou mais no mesmo grupo
    t = ex(ALVO, "meta-t", data="2026-10-23")
    caso("tres_executadas_ficam_a_mais_cedo",
         {"2026-10": mes("2026-10", [_l("L1", [auto("meta-a"), auto("meta-s", "2026-10-21"), auto("meta-t", "2026-10-23")])])},
         [a, t, s])
    caso("dois_grupos_ao_mesmo_tempo",
         {"2026-10": mes("2026-10", [_l("L1", [auto("meta-a"), auto("meta-s", "2026-10-21"), auto("p"), auto("q")])])},
         [a, ex(ALVO, "p", oco="oco-9", data="2026-10-20"), s, ex(STOP, "q", oco="oco-9", data="2026-10-20", hora="09:00")])
    # detalhes do texto
    caso("vencedora_sem_data_vira_interrogacao", ab, [{**a, "execucao": {"venda_id": "auto-meta-a"}}, s])
    caso("vencedora_alvo_executada_em_dd_mm", ab, [ex(ALVO, "meta-a", data="2026-12-31"),
                                                    ex(STOP, "meta-s", data="2027-01-02")])
    caso("empate_total_pelo_id", ab, [ex(ALVO, "meta-b"), ex(ALVO, "meta-a")])
    caso("empate_barra_ts", ab, [ex(ALVO, "meta-a", barra_ts=100), ex(STOP, "meta-s", barra_ts=200)])
    caso("empate_hora_vazia_prefere_o_stop", ab, [ex(ALVO, "meta-a", hora=""), ex(STOP, "meta-s")])
    caso("perdedora_perde_execucao_e_erro_e_ganha_cancelamento", ab,
         [{**a, "ultimo_erro": "e", "cancelada_por": "velho"}, s])
    return out


def casos():
    return (_casos_mes() + _casos_dedup() + _casos_lista() + _casos_metas() + _casos_niveis()
            + _casos_execucao_antes() + _casos_oco())
