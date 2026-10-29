import sys
import tempfile
import unittest
from datetime import datetime, timedelta
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import mercado as mk  # noqa: E402
import metas as mt  # noqa: E402
import nucleo as nc  # noqa: E402

FUSO = mt.FUSO


def dt(texto):
    return datetime.fromisoformat(texto).replace(tzinfo=FUSO)


def barra(texto, alta):
    d = dt(texto)
    return {"ts": int(d.timestamp()), "dt": d, "alta": alta}


def historico_fixo(barras):
    return lambda ticker, desde: {"barras": barras, "fonte": "Yahoo Finance", "intervalo": "1m"}


def historico_erro(ticker, desde):
    raise mk.SemDados("Sem dados para PETR4 no Yahoo Finance.")


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        nc.configurar(self.tmp.name)
        self.corretagem = nc.CORRETAGEM_POR_ORDEM
        self.cfg = nc.ler_config()
        d = nc.mes_vazio("2026-10")
        d["lotes"].append({"id": "L1", "ticker": "PETR4", "tipo": "Ação", "data_compra": "2026-10-01",
                           "qtd": 100, "preco": 10.0, "vendas": []})
        nc.salvar(d)
        self.criada = dt("2026-10-20T11:00:00")

    def tearDown(self):
        nc.CORRETAGEM_POR_ORDEM = self.corretagem
        self.tmp.cleanup()

    def lote(self, mes="2026-10", lid="L1"):
        return next(l for l in nc.carregar(mes)["lotes"] if l["id"] == lid)

    def criar(self, qtd=100, alvo=21.78):
        return mt.criar_meta(self.cfg, "L1", qtd, alvo, 1000, agora=self.criada)

    def verificar(self, barras, agora=None):
        return mt.verificar(self.cfg, historico_fixo(barras), agora or dt("2026-10-25T18:00:00"))


class TestPrecoAlvo(Base):
    def test_exemplo_de_referencia(self):
        r = mt.calcular_preco_alvo(self.lote(), 100, 1000)
        self.assertAlmostEqual(r["preco_exato"], 21.7743, places=3)
        self.assertEqual(r["preco"], 21.78)

    def conferir(self, qtd, lucro, day_trade, corretagem=0.0):
        nc.CORRETAGEM_POR_ORDEM = corretagem
        lote = self.lote()
        r = mt.calcular_preco_alvo(lote, qtd, lucro, day_trade)
        # com o preço exato, o lucro após imposto é exatamente o desejado
        p = mt.projetar(lote, qtd, r["preco_exato"], day_trade)
        self.assertAlmostEqual(p["lucro_apos_imposto"], lucro, delta=0.01)
        # com o preço arredondado para cima nunca fica abaixo do desejado
        self.assertGreaterEqual(r["lucro_apos_imposto"], lucro - 1e-9)
        self.assertLess(r["lucro_apos_imposto"] - lucro, qtd * 0.01 + 0.01)
        # coerente com o cálculo do app
        dia = lote["data_compra"] if day_trade else ""
        c = nc.calcular_venda(lote, {"qtd": qtd, "preco": r["preco"], "data": dia})
        self.assertAlmostEqual(c["liquido"], r["liquido"], places=9)
        return r

    def test_swing(self):
        r = self.conferir(100, 1000, False)
        self.assertFalse(r["dt"])
        self.assertAlmostEqual(r["imposto"], r["liquido"] * 0.15, places=9)

    def test_day_trade(self):
        r = self.conferir(100, 1000, True)
        self.assertTrue(r["dt"])
        self.assertAlmostEqual(r["imposto"], r["liquido"] * 0.20, places=9)
        swing = mt.calcular_preco_alvo(self.lote(), 100, 1000)
        self.assertGreater(r["preco_exato"], swing["preco_exato"])  # 20% de imposto exige lucro bruto maior

    def test_com_corretagem(self):
        sem = mt.calcular_preco_alvo(self.lote(), 50, 500)
        r = self.conferir(50, 500, False, corretagem=2.5)
        self.assertGreater(r["preco_exato"], sem["preco_exato"])
        self.assertAlmostEqual(r["corretagem"], 2.5 * (1 + 50 / 100))

    def test_lucro_zero_e_negativo(self):
        r0 = self.conferir(100, 0, False)
        self.assertLess(r0["imposto"], 0.15 * (100 * 0.01 + 0.01))  # só o arredondamento para cima do centavo
        self.assertGreater(r0["preco"], 10.0)  # cobre as taxas
        rn = self.conferir(100, -200, False)
        self.assertLess(rn["imposto"], 0.15 * (100 * 0.01 + 0.01))
        self.assertLess(rn["preco"], 10.0)
        with self.assertRaises(ValueError):
            mt.calcular_preco_alvo(self.lote(), 100, -5000)

    def test_irrf_nao_altera_preco_nem_imposto(self):
        lote = self.lote()
        r = mt.calcular_preco_alvo(lote, 100, 1000)
        self.assertEqual(r["irrf"], 0)  # 0,005% de R$ 2.178 = R$ 0,11: abaixo de R$ 1 não há retenção
        grande = {**lote, "qtd": 100000, "preco": 10.0}
        rg = mt.calcular_preco_alvo(grande, 100000, 1000000)
        self.assertGreater(rg["irrf"], 1)
        # com IRRF o imposto total é o mesmo da fórmula; o IRRF só abate o que sobra para a DARF
        self.assertAlmostEqual(rg["imposto"], rg["liquido"] * 0.15, places=6)
        self.assertAlmostEqual(rg["darf_estimado"], rg["imposto"] - rg["irrf"], places=6)
        pg = mt.projetar(grande, 100000, rg["preco_exato"], False)
        self.assertAlmostEqual(pg["lucro_apos_imposto"], 1000000, delta=0.01)

    def test_teto_centavo(self):
        self.assertEqual(mt.teto_centavo(21.7743), 21.78)
        self.assertEqual(mt.teto_centavo(21.77), 21.77)
        self.assertEqual(mt.teto_centavo(21.770000000001), 21.77)


class TestCriacao(Base):
    def test_criacao_valida(self):
        m = self.criar()
        self.assertEqual(m["status"], "ativa")
        self.assertTrue(m["id"].startswith("meta-"))
        self.assertTrue(m["criada_em"].endswith("-03:00"))
        self.assertEqual(nc.ler_config()["metas"][0]["id"], m["id"])

    def test_quantidade_insuficiente_bloqueada(self):
        with self.assertRaises(ValueError) as e:
            self.criar(qtd=101)
        self.assertIn("disponível", str(e.exception))
        self.assertEqual(self.cfg.get("metas", []), [])

    def test_quantidade_reservada_por_outra_meta(self):
        self.criar(qtd=80)
        with self.assertRaises(ValueError):
            self.criar(qtd=30)
        self.criar(qtd=20)

    def test_preco_e_lote_invalidos(self):
        for alvo in (0, -1, "x"):
            with self.assertRaises(ValueError):
                self.criar(alvo=alvo)
        with self.assertRaises(ValueError):
            mt.criar_meta(self.cfg, "inexistente", 10, 20.0)

    def test_cancelar(self):
        m = self.criar()
        mt.cancelar_meta(self.cfg, m["id"])
        self.assertEqual(self.cfg["metas"][0]["status"], "cancelada")
        self.assertIsNone(self.verificar([barra("2026-10-21T10:00:00", 30)]))
        self.assertEqual(nc.restante(self.lote()), 100)


class TestDeteccao(Base):
    def test_achar_barra(self):
        barras = [barra("2026-10-20T10:00:00", 25), barra("2026-10-20T11:00:00", 21.0),
                  barra("2026-10-20T12:00:00", 21.78), barra("2026-10-20T13:00:00", 30)]
        b = mt.achar_barra(barras, 21.78, self.criada)
        self.assertEqual(b["dt"], dt("2026-10-20T12:00:00"))  # igual ao alvo conta; 10:00 é anterior à criação

    def test_barra_anterior_ignorada(self):
        self.assertIsNone(mt.achar_barra([barra("2026-10-20T10:59:00", 99)], 21.78, self.criada))

    def test_barra_na_hora_da_criacao_vale(self):
        self.assertIsNotNone(mt.achar_barra([barra("2026-10-20T11:00:00", 22)], 21.78, self.criada))

    def test_sem_barra_atingindo(self):
        self.assertIsNone(mt.achar_barra([barra("2026-10-21T10:00:00", 21.77)], 21.78, self.criada))


class TestExecucao(Base):
    def test_executa_no_preco_alvo_e_data_da_barra(self):
        m = self.criar()
        rel = self.verificar([barra("2026-10-21T10:30:00", 21.9)])
        self.assertEqual(len(rel["executadas"]), 1)
        meta = nc.ler_config()["metas"][0]
        self.assertEqual(meta["status"], "executada")
        ex = meta["execucao"]
        self.assertEqual((ex["data"], ex["hora"], ex["preco_usado"]), ("2026-10-21", "10:30", 21.78))
        self.assertEqual(ex["venda_id"], "auto-" + m["id"])
        self.assertIn("21,90", ex["motivo"])
        self.assertIn("1m", ex["origem"])
        v = self.lote()["vendas"][0]
        self.assertEqual((v["id"], v["data"], v["qtd"], v["preco"]), ("auto-" + m["id"], "2026-10-21", 100, 21.78))
        self.assertEqual(nc.restante(self.lote()), 0)
        self.assertEqual(len(nc.apurar(nc.carregar("2026-10"))["ops"]), 1)

    def test_segunda_verificacao_nao_duplica(self):
        self.criar()
        barras = [barra("2026-10-21T10:30:00", 22)]
        self.verificar(barras)
        self.assertIsNone(self.verificar(barras))  # nada mais ativo
        self.assertEqual(len(self.lote()["vendas"]), 1)

    def test_meta_executada_nao_reexecuta_mesmo_forcada(self):
        self.criar()
        barras = [barra("2026-10-21T10:30:00", 22)]
        self.verificar(barras)
        rel = mt.aplicar(self.cfg, {"PETR4": ("ok", historico_fixo(barras)("PETR4", None))})
        self.assertEqual(rel["executadas"], [])
        self.assertEqual(len(self.lote()["vendas"]), 1)

    def test_reinicio_reconcilia_sem_duplicar(self):
        m = self.criar()
        # simula o app fechado entre a gravação da venda e a do status
        d = nc.carregar("2026-10")
        d["lotes"][0]["vendas"].append({"id": "auto-" + m["id"], "data": "2026-10-21", "qtd": 100, "preco": 21.78})
        nc.salvar(d)
        cfg2 = nc.ler_config()
        self.assertEqual(cfg2["metas"][0]["status"], "ativa")
        rel = mt.verificar(cfg2, historico_fixo([barra("2026-10-22T10:00:00", 40)]), dt("2026-10-25T18:00:00"))
        self.assertEqual(len(rel["reconciliadas"]), 1)
        self.assertEqual(cfg2["metas"][0]["status"], "executada")
        self.assertEqual(nc.ler_config()["metas"][0]["status"], "executada")
        self.assertEqual(len(self.lote()["vendas"]), 1)
        self.assertEqual(self.lote()["vendas"][0]["data"], "2026-10-21")

    def test_app_fechado_dias_depois(self):
        self.criar()
        barras = [barra("2026-10-22T14:20:00", 21.0), barra("2026-10-23T10:05:00", 21.80),
                  barra("2026-10-24T10:05:00", 25)]
        self.verificar(barras, agora=dt("2026-10-29T09:00:00"))
        self.assertEqual(self.lote()["vendas"][0]["data"], "2026-10-23")
        self.assertEqual(self.cfg["metas"][0]["execucao"]["hora"], "10:05")

    def test_sem_atingir_permanece_ativa_sem_erro(self):
        self.criar()
        self.verificar([barra("2026-10-21T10:00:00", 20)])
        self.assertEqual(self.cfg["metas"][0]["status"], "ativa")
        self.assertNotIn("ultimo_erro", self.cfg["metas"][0])
        self.assertEqual(self.lote()["vendas"], [])

    def test_quantidade_insuficiente_na_execucao_invalida(self):
        self.criar()
        d = nc.carregar("2026-10")
        d["lotes"][0]["vendas"].append({"id": "manual", "data": "2026-10-19", "qtd": 60, "preco": 12})
        nc.salvar(d)
        rel = self.verificar([barra("2026-10-21T10:00:00", 30)])
        self.assertEqual(len(rel["invalidas"]), 1)
        meta = self.cfg["metas"][0]
        self.assertEqual(meta["status"], "inválida")
        self.assertIn("Quantidade insuficiente", meta["ultimo_erro"])
        self.assertEqual([v["id"] for v in self.lote()["vendas"]], ["manual"])  # venda manual intacta

    def test_falha_de_fonte_mantem_ativa_com_erro(self):
        self.criar()
        rel = mt.verificar(self.cfg, historico_erro, dt("2026-10-25T18:00:00"))
        self.assertEqual(len(rel["erros"]), 1)
        meta = nc.ler_config()["metas"][0]
        self.assertEqual(meta["status"], "ativa")
        self.assertIn("Sem dados", meta["ultimo_erro"])
        self.assertEqual(self.lote()["vendas"], [])
        # a próxima verificação com sucesso limpa o erro
        self.verificar([barra("2026-10-21T10:00:00", 20)])
        self.assertNotIn("ultimo_erro", self.cfg["metas"][0])

    def test_falha_generica_vira_mensagem(self):
        self.criar()

        def quebra(t, d):
            raise ConnectionError("x")
        mt.verificar(self.cfg, quebra)
        self.assertEqual(self.cfg["metas"][0]["ultimo_erro"], "Sem conexão com a internet.")

    def test_trava_concorrente(self):
        self.criar()
        self.assertTrue(mt._VERIFICANDO.acquire(blocking=False))
        try:
            self.assertIsNone(self.verificar([barra("2026-10-21T10:00:00", 99)]))
        finally:
            mt._VERIFICANDO.release()
        self.assertEqual(self.lote()["vendas"], [])

    def test_alvo_em_mes_seguinte_aguarda_fechamento_e_executa_depois(self):
        self.criar()
        barras = [barra("2026-11-03T10:00:00", 30)]
        rel = self.verificar(barras, agora=dt("2026-11-04T09:00:00"))
        self.assertEqual(len(rel["aguardando"]), 1)
        self.assertEqual(self.cfg["metas"][0]["status"], "ativa")
        self.assertIn("Feche o mês", self.cfg["metas"][0]["ultimo_erro"])
        self.assertEqual(self.lote()["vendas"], [])
        nc.fechar_mes(nc.carregar("2026-10"))
        self.verificar(barras, agora=dt("2026-11-04T09:00:00"))
        self.assertEqual(self.cfg["metas"][0]["status"], "executada")
        self.assertEqual(nc.carregar("2026-10")["lotes"][0]["vendas"], [])
        carregado = nc.carregar("2026-11")["lotes"][0]
        self.assertEqual(carregado["vendas"][0]["data"], "2026-11-03")

    def test_mes_fechado_invalida(self):
        self.criar()
        nc.fechar_mes(nc.carregar("2026-10"))
        self.verificar([barra("2026-10-21T10:00:00", 30)], agora=dt("2026-11-04T09:00:00"))
        self.assertEqual(self.cfg["metas"][0]["status"], "inválida")
        self.assertIn("fechado", self.cfg["metas"][0]["ultimo_erro"])


class TestMesclagem(Base):
    def meta(self, **kw):
        m = {"id": "meta-1", "ticker": "PETR4", "tipo": "Ação", "lote_id": "L1", "qtd": 100, "preco_alvo": 21.78,
             "criada_em": "2026-10-20T11:00:00-03:00", "status": "ativa", "mod": 10}
        m.update(kw)
        return m

    def test_executada_vence_ativa_mesmo_mais_antiga(self):
        ex = self.meta(status="executada", mod=5, execucao={"venda_id": "auto-meta-1"})
        r = nc.mesclar_metas([self.meta(mod=99)], [ex])
        self.assertEqual(len(r), 1)
        self.assertEqual(r[0]["status"], "executada")
        r = nc.mesclar_metas([ex], [self.meta(mod=99)])
        self.assertEqual(r[0]["status"], "executada")

    def test_mais_recente_vence_nos_demais(self):
        r = nc.mesclar_metas([self.meta(mod=1)], [self.meta(status="cancelada", mod=2)])
        self.assertEqual(r[0]["status"], "cancelada")

    def test_mesclar_tudo_nao_duplica_venda_nem_meta(self):
        m = self.criar()
        self.verificar([barra("2026-10-21T10:00:00", 30)])
        local = nc.ler_config()
        linhas = nc.montar_linhas(nc.listar_meses(), local)
        self.assertEqual(len(linhas["Metas"]), 1)
        remoto_metas = nc.reconstruir_metas(linhas)
        self.assertEqual(remoto_metas[0]["execucao"]["venda_id"], "auto-" + m["id"])
        mudou = nc.mesclar_tudo(nc.reconstruir(linhas), local, metas_r=remoto_metas)
        self.assertFalse(mudou)
        self.assertEqual(len(self.lote()["vendas"]), 1)
        self.assertEqual(len(local["metas"]), 1)

    def test_aparelho_com_meta_ativa_recebe_executada(self):
        m = self.criar()
        self.verificar([barra("2026-10-21T10:00:00", 30)])
        linhas = nc.montar_linhas(nc.listar_meses(), nc.ler_config())
        remoto = nc.reconstruir(linhas)
        remoto_metas = nc.reconstruir_metas(linhas)
        # estado do segundo aparelho: meta ainda ativa (alterada depois) e sem a venda
        d = nc.carregar("2026-10")
        d["lotes"][0]["vendas"] = []
        d["excluidos"] = {}
        nc.salvar(d, carimbar=False)  # aparelho que nunca viu a venda (não é uma exclusão)
        ativa = {k: v for k, v in m.items() if k != "execucao"}
        ativa.update(status="ativa", mod=9e9)
        outro = {**nc.ler_config(), "metas": [ativa]}
        self.assertTrue(nc.mesclar_tudo(remoto, outro, metas_r=remoto_metas))
        self.assertEqual(outro["metas"][0]["status"], "executada")
        self.assertEqual(len(self.lote()["vendas"]), 1)

    def test_planilha_ida_e_volta(self):
        m = self.criar()
        m["ultimo_erro"] = "Sem conexão com a internet."
        linhas = nc.montar_linhas(nc.listar_meses(), self.cfg)
        volta = nc.reconstruir_metas(linhas)[0]
        for k in ("id", "ticker", "lote_id", "qtd", "preco_alvo", "criada_em", "status", "lucro_desejado",
                  "ultimo_erro"):
            self.assertEqual(volta[k], m[k], k)

    def test_aba_metas_no_google(self):
        import google_sync as gs
        self.assertIn("Metas", gs.ABAS)
        self.assertEqual(len(gs.ABAS["Metas"]["colunas"]), 14)


class TestCorrecoesRevisao(Base):
    def test_reserva_atravessa_virada_de_mes(self):
        self.criar(qtd=100)
        nc.fechar_mes(nc.carregar("2026-10"))
        copia = self.lote("2026-11", "L1~2026-11")
        self.assertEqual(copia["origem"], "L1")
        self.assertEqual(mt.reservado(self.cfg, copia["id"]), 100)
        self.assertEqual(mt.lotes_para_meta(self.cfg), [])  # 0 livres
        with self.assertRaises(ValueError):
            mt.criar_meta(self.cfg, copia["id"], 100, 25.0, agora=self.criada)
        self.assertEqual(len(self.cfg["metas"]), 1)

    def test_fechar_mes_com_verificacao_falha_e_bloqueado(self):
        self.criar()
        res = mt.preparar_fechamento(self.cfg, "2026-10", historico_erro, dt("2026-10-31T18:00:00"))
        self.assertIn("Sem dados", res["bloqueio"])
        self.assertEqual(self.cfg["metas"][0]["status"], "ativa")

    def test_fechar_mes_registra_meta_atingida_antes(self):
        self.criar()
        res = mt.preparar_fechamento(self.cfg, "2026-10", historico_fixo([barra("2026-10-21T10:00:00", 30)]),
                                     dt("2026-10-31T18:00:00"))
        self.assertIsNone(res["bloqueio"])
        self.assertEqual(len(res["executadas"]), 1)
        self.assertEqual(self.cfg["metas"][0]["status"], "executada")
        self.assertEqual(len(self.lote()["vendas"]), 1)

    def test_fechar_mes_sem_metas_nao_consulta(self):
        def nao_chama(t, d):
            raise AssertionError("não deveria consultar")
        res = mt.preparar_fechamento(self.cfg, "2026-10", nao_chama)
        self.assertIsNone(res["bloqueio"])

    def test_fechar_mes_com_verificacao_em_andamento_bloqueia(self):
        self.criar()
        self.assertTrue(mt._VERIFICANDO.acquire(blocking=False))
        try:
            res = mt.preparar_fechamento(self.cfg, "2026-10", historico_fixo([]))
        finally:
            mt._VERIFICANDO.release()
        self.assertIn("em andamento", res["bloqueio"])

    def test_valores_nao_finitos(self):
        inf, nan = float("inf"), float("nan")
        for qtd, lucro in ((inf, 1000), (nan, 1000), (100, inf), (100, nan), (100, -inf)):
            with self.assertRaises(ValueError):
                mt.calcular_preco_alvo(self.lote(), qtd, lucro)
        for qtd, alvo, lucro in ((inf, 20, None), (nan, 20, None), (100, inf, None), (100, nan, None),
                                 (100, 20, inf), (100, 20, nan)):
            with self.assertRaises(ValueError):
                mt.criar_meta(self.cfg, "L1", qtd, alvo, lucro)
        self.assertEqual(self.cfg.get("metas", []), [])


class TestMesclagemEntreMeses(Base):
    def test_venda_auto_em_meses_diferentes_fica_so_no_mais_antigo(self):
        v = {"id": "auto-meta-x", "data": "2026-10-31", "qtd": 50, "preco": 20.0}
        d10 = nc.carregar("2026-10")
        d10["lotes"][0]["vendas"].append(dict(v))
        nc.salvar(d10)
        d11 = nc.mes_vazio("2026-11")
        d11["lotes"].append({"id": "L1~2026-11", "origem": "L1", "ticker": "PETR4", "tipo": "Ação",
                             "data_compra": "2026-10-01", "qtd": 100, "preco": 10.0,
                             "vendas": [{**v, "data": "2026-11-01"}]})
        nc.salvar(d11)
        remoto = ({}, [], [], {})
        self.assertTrue(nc.mesclar_tudo(remoto, self.cfg))
        self.assertEqual([x["id"] for x in self.lote()["vendas"]], ["auto-meta-x"])
        self.assertEqual(self.lote("2026-11", "L1~2026-11")["vendas"], [])


class TestHistoricoMercado(unittest.TestCase):
    def test_intervalos(self):
        self.assertEqual(mk.intervalos_historico(3)[0], "1m")
        self.assertEqual(mk.intervalos_historico(30)[0], "5m")
        self.assertEqual(mk.intervalos_historico(200)[0], "1h")
        self.assertEqual(mk.intervalos_historico(1000), ["1d"])

    def test_historico_desde_usa_chart_e_fuso(self):
        chamadas = []
        original = mk._get_chart

        def falso(ticker, params):
            chamadas.append(params)
            if params["interval"] == "1m":
                raise mk.SemDados("sem 1m")
            return {"meta": {"gmtoffset": -10800}, "timestamp": [1761051600, 1761055200],
                    "indicators": {"quote": [{"high": [21.5, None]}]}}
        mk._get_chart = falso
        try:
            agora = datetime(2026, 10, 22, 12, tzinfo=FUSO)
            h = mk.historico_desde("PETR4", datetime(2026, 10, 20, 11), agora)
        finally:
            mk._get_chart = original
        self.assertEqual([c["interval"] for c in chamadas], ["1m", "5m"])
        self.assertEqual(h["intervalo"], "5m")
        self.assertEqual(len(h["barras"]), 1)
        self.assertEqual(h["barras"][0]["dt"].utcoffset(), timedelta(hours=-3))

    def test_sem_barras_levanta(self):
        original = mk._get_chart
        mk._get_chart = lambda t, p: {"meta": {}, "timestamp": [], "indicators": {"quote": [{}]}}
        try:
            with self.assertRaises(mk.SemDados):
                mk.historico_desde("PETR4", datetime(2026, 10, 20, 11), datetime(2026, 10, 22, 12, tzinfo=FUSO))
        finally:
            mk._get_chart = original


def barra_s(texto, alta, baixa, abre=None):
    d = dt(texto)
    return {"ts": int(d.timestamp()), "dt": d, "alta": alta, "baixa": baixa, "abre": abre}


def dia(texto, alta, baixa, fech, abre=None):
    return {"data": datetime.fromisoformat(texto).date(), "abre": abre if abre is not None else fech,
            "alta": alta, "baixa": baixa, "fech": fech}


class TestStop(Base):
    def stop(self, preco=9.0, qtd=100, **kw):
        return mt.criar_stop(self.cfg, "L1", qtd, preco, agora=self.criada, **kw)

    def test_criacao(self):
        m = self.stop(movel=True, sugestao={"modo": "swing", "atr14": 1.0, "atr22": 1.1, "compra": 10.0})
        self.assertEqual((m["gatilho"], m["stop_inicial"], m["stop_atual"], m["movel"]), ("stop", 9.0, 9.0, True))
        self.assertEqual(m["niveis"][0]["stop"], 9.0)
        self.assertNotIn("preco_alvo", m)
        self.assertEqual(mt.gatilho(m), "stop")
        self.assertEqual(mt.preco_gatilho(m), 9.0)
        self.assertEqual(nc.ler_config()["metas"][0]["id"], m["id"])

    def test_meta_sem_gatilho_e_alvo(self):
        m = self.criar()
        self.assertNotIn("gatilho", m)
        self.assertEqual(mt.gatilho(m), "alvo")
        self.assertEqual(mt.preco_gatilho(m), 21.78)

    def test_validacoes(self):
        for preco in (0, -1, "x", float("inf"), float("nan")):
            with self.assertRaises(ValueError):
                self.stop(preco)
        with self.assertRaises(ValueError):
            self.stop(10.0, preco_atual=10.0)      # stop >= cotação
        with self.assertRaises(ValueError):
            self.stop(qtd=101)
        self.stop(9.99, preco_atual=10.0)
        self.assertEqual(len(self.cfg["metas"]), 1)

    def test_dispara_com_minima_igual_ao_stop(self):
        niveis = [{"desde": "2026-10-20", "stop": 9.0, "calc_em": "2026-10-20"}]
        b = mt.achar_barra_stop([barra_s("2026-10-21T10:00:00", 10, 9.01), barra_s("2026-10-21T11:00:00", 10, 9.00)],
                                niveis, self.criada)
        self.assertEqual(b[0]["dt"], dt("2026-10-21T11:00:00"))
        self.assertIsNone(mt.achar_barra_stop([barra_s("2026-10-21T10:00:00", 10, 9.01)], niveis, self.criada))
        self.assertIsNone(mt.achar_barra_stop([barra_s("2026-10-20T10:00:00", 10, 1)], niveis, self.criada))

    def test_maxima_acima_do_alvo_nao_dispara_stop(self):
        self.stop(9.0)
        self.verificar([barra_s("2026-10-21T10:00:00", 50, 9.5, 10)])
        self.assertEqual(self.cfg["metas"][0]["status"], "ativa")
        self.assertEqual(self.lote()["vendas"], [])

    def test_execucao_no_stop(self):
        m = self.stop(9.0)
        rel = self.verificar([barra_s("2026-10-21T10:30:00", 10, 8.95, 9.5)])
        self.assertEqual(len(rel["executadas"]), 1)
        ex = self.cfg["metas"][0]["execucao"]
        self.assertEqual((ex["preco_usado"], ex["gatilho"], ex["data"]), (9.0, "stop", "2026-10-21"))
        self.assertIn("mínima 8,95 ≤ stop 9,00", ex["motivo"])
        self.assertEqual(self.lote()["vendas"][0]["preco"], 9.0)
        self.assertEqual(self.lote()["vendas"][0]["id"], "auto-" + m["id"])
        self.assertEqual(nc.apurar(nc.carregar("2026-10"))["ops"][0]["imposto"], 0)

    def test_gap_de_baixa_usa_a_abertura(self):
        self.stop(9.0)
        self.verificar([barra_s("2026-10-21T10:00:00", 9.0, 8.4, 8.5)])
        ex = self.cfg["metas"][0]["execucao"]
        self.assertEqual(ex["preco_usado"], 8.5)
        self.assertIn("abertura em gap 8,50", ex["motivo"])

    def test_abertura_acima_do_stop_executa_no_stop(self):
        self.stop(9.0)
        self.verificar([barra_s("2026-10-21T10:00:00", 9.5, 8.9, 9.2)])
        self.assertEqual(self.cfg["metas"][0]["execucao"]["preco_usado"], 9.0)


class TestStopMovel(Base):
    def movel(self, preco=5.0):
        return mt.criar_stop(self.cfg, "L1", 100, preco, movel=True, agora=self.criada)

    def barras(self, n=30, fim="2026-10-22", alta=11.0, baixa=9.0, fech=10.0):
        ultimo = datetime.fromisoformat(fim).date()
        return [{"data": ultimo - timedelta(days=n - 1 - i), "abre": fech, "alta": alta, "baixa": baixa, "fech": fech}
                for i in range(n)]

    def test_subida_acrescenta_nivel_a_partir_do_dia_seguinte(self):
        m = self.movel(4.0)
        subiu = mt.atualizar_stop_movel(m, self.barras(), datetime(2026, 10, 25).date())
        self.assertTrue(subiu)
        self.assertEqual(m["stop_atual"], 5.0)      # 11 - 3*2
        novo = m["niveis"][1]
        self.assertEqual((novo["desde"], novo["calc_em"], novo["stop"]), ("2026-10-21", "2026-10-20", 5.0))

    def test_idempotente_e_nunca_desce(self):
        m = self.movel(4.0)
        hoje = datetime(2026, 10, 25).date()
        mt.atualizar_stop_movel(m, self.barras(), hoje)
        antes = [dict(n) for n in m["niveis"]]
        self.assertFalse(mt.atualizar_stop_movel(m, self.barras(), hoje))
        self.assertEqual(m["niveis"], antes)
        # volatilidade maior derrubaria o Chandelier: o stop continua onde estava
        piores = self.barras(baixa=1.0)
        self.assertFalse(mt.atualizar_stop_movel(m, piores, hoje))
        self.assertEqual(m["stop_atual"], 5.0)

    def test_stop_acima_do_chandelier_nao_muda(self):
        m = self.movel(7.0)
        self.assertFalse(mt.atualizar_stop_movel(m, self.barras(), datetime(2026, 10, 25).date()))
        self.assertEqual(len(m["niveis"]), 1)

    def test_so_pregoes_fechados_e_desde_a_criacao(self):
        m = self.movel(4.0)
        # hoje = 20/10 (dia da criação): ainda não há pregão fechado a partir da criação
        self.assertFalse(mt.atualizar_stop_movel(m, self.barras(), datetime(2026, 10, 20).date()))
        self.assertEqual(m["stop_atual"], 4.0)

    def test_nivel_com_desde_posterior_nao_vale(self):
        niveis = [{"desde": "2026-10-20", "stop": 5.0, "calc_em": "x"}, {"desde": "2026-10-22", "stop": 9.0, "calc_em": "x"}]
        self.assertIsNone(mt.achar_barra_stop([barra_s("2026-10-21T10:00:00", 10, 8.0)], niveis, self.criada))
        self.assertIsNotNone(mt.achar_barra_stop([barra_s("2026-10-22T10:00:00", 10, 8.0)], niveis, self.criada))

    def test_falha_de_dados_mantem_o_stop(self):
        m = self.movel(4.0)

        def historico(t, d):
            return {"barras": [barra_s("2026-10-21T10:00:00", 10, 9.0)], "fonte": "Yahoo", "intervalo": "1h"}

        def quebra(t, d):
            raise mk.SemDados("sem dados")
        mt.verificar(self.cfg, historico, dt("2026-10-25T18:00:00"), quebra)
        self.assertEqual(self.cfg["metas"][0]["stop_atual"], 4.0)
        self.assertEqual(self.cfg["metas"][0]["status"], "ativa")

    def test_verificar_sobe_o_stop_e_depois_dispara(self):
        m = self.movel(4.0)
        horario = [barra_s("2026-10-21T10:00:00", 10, 5.5, 6.0), barra_s("2026-10-22T10:00:00", 10, 4.9, 6.0)]

        def historico(t, d):
            return {"barras": horario, "fonte": "Yahoo", "intervalo": "1h"}

        def diarias(t, d):
            return {"barras": self.barras(fim="2026-10-22"), "hoje": datetime(2026, 10, 23).date()}
        rel = mt.verificar(self.cfg, historico, dt("2026-10-23T09:00:00"), diarias)
        self.assertEqual(len(rel["executadas"]), 1)
        meta = self.cfg["metas"][0]
        self.assertEqual(meta["stop_atual"], 5.0)
        self.assertEqual(meta["execucao"]["data"], "2026-10-22") 


class TestOCO(Base):
    def par(self, qtd=100, alvo=21.78, stop=9.0):
        a = mt.criar_meta(self.cfg, "L1", qtd, alvo, agora=self.criada)
        s = mt.criar_stop(self.cfg, "L1", qtd, stop, oco_com=a["id"], agora=self.criada)
        return a, s

    def metas(self):
        return {m["id"]: m for m in nc.ler_config()["metas"]}

    def test_par_compartilha_o_mesmo_oco_e_a_reserva_conta_uma_vez(self):
        a, s = self.par()
        self.assertTrue(a["oco"].startswith("oco-"))
        self.assertEqual(a["oco"], s["oco"])
        self.assertEqual(mt.reservado(self.cfg, "L1"), 100)
        with self.assertRaises(ValueError):
            mt.criar_meta(self.cfg, "L1", 1, 30.0, agora=self.criada)
        self.assertEqual(mt.lotes_para_meta(self.cfg), [])

    def test_posicoes_abertas_mostra_livre_zero(self):
        self.par()
        mes, lote, restante, livre, ativas = mt.posicoes_abertas(self.cfg)[0]
        self.assertEqual((mes, restante, livre, len(ativas)), ("2026-10", 100, 0, 2))

    def test_alvo_executa_e_cancela_o_stop(self):
        a, s = self.par()
        rel = self.verificar([barra_s("2026-10-21T10:00:00", 30, 15, 16)])
        self.assertEqual([m["id"] for m in rel["executadas"]], [a["id"]])
        m = self.metas()
        self.assertEqual((m[a["id"]]["status"], m[s["id"]]["status"]), ("executada", "cancelada"))
        self.assertEqual(m[s["id"]]["cancelada_por"], a["id"])
        self.assertIn("Cancelada automaticamente (OCO): alvo executado em 21/10", m[s["id"]]["cancelada_detalhe"])
        self.assertEqual([v["id"] for v in self.lote()["vendas"]], ["auto-" + a["id"]])

    def test_stop_executa_e_cancela_o_alvo(self):
        a, s = self.par()
        self.verificar([barra_s("2026-10-21T10:00:00", 12, 8.5, 9.5)])
        m = self.metas()
        self.assertEqual((m[a["id"]]["status"], m[s["id"]]["status"]), ("cancelada", "executada"))
        self.assertIn("stop executado", m[a["id"]]["cancelada_detalhe"])
        self.assertEqual([v["id"] for v in self.lote()["vendas"]], ["auto-" + s["id"]])

    def test_mesma_barra_vence_o_stop(self):
        a, s = self.par()
        self.verificar([barra_s("2026-10-21T10:00:00", 30, 8.0, 15)])
        m = self.metas()
        self.assertEqual((m[a["id"]]["status"], m[s["id"]]["status"]), ("cancelada", "executada"))
        self.assertEqual(len(self.lote()["vendas"]), 1)

    def test_barras_diferentes_vence_a_mais_cedo(self):
        a, s = self.par()
        self.verificar([barra_s("2026-10-21T10:00:00", 30, 15, 16), barra_s("2026-10-22T10:00:00", 12, 8.0, 9.5)])
        self.assertEqual(self.metas()[a["id"]]["status"], "executada")
        self.assertEqual(self.metas()[s["id"]]["status"], "cancelada")

    def test_stop_antes_do_alvo(self):
        a, s = self.par()
        self.verificar([barra_s("2026-10-21T10:00:00", 12, 8.0, 9.5), barra_s("2026-10-22T10:00:00", 30, 15, 16)])
        self.assertEqual(self.metas()[s["id"]]["status"], "executada")
        self.assertEqual(self.metas()[a["id"]]["status"], "cancelada")

    def test_recusas(self):
        a = mt.criar_meta(self.cfg, "L1", 100, 21.78, agora=self.criada)
        with self.assertRaises(ValueError):
            mt.criar_stop(self.cfg, "L1", 50, 9.0, oco_com=a["id"], agora=self.criada)      # quantidade diferente
        with self.assertRaises(ValueError):
            mt.criar_meta(self.cfg, "L1", 100, 25.0, oco_com=a["id"], agora=self.criada)    # mesmo gatilho
        with self.assertRaises(ValueError):
            mt.criar_stop(self.cfg, "L1", 100, 9.0, oco_com="meta-inexistente", agora=self.criada)
        s = mt.criar_stop(self.cfg, "L1", 100, 9.0, oco_com=a["id"], agora=self.criada)
        with self.assertRaises(ValueError):
            mt.criar_stop(self.cfg, "L1", 100, 8.0, oco_com=a["id"], agora=self.criada)     # alvo já tem par
        self.assertEqual(len(self.cfg["metas"]), 2)
        self.assertIsNone(mt.parceira_oco(self.cfg, "L1", "stop"))
        mt.cancelar_meta(self.cfg, s["id"])
        self.assertEqual(mt.parceira_oco(self.cfg, "L1", "stop")["id"], a["id"])             # ficou sem par ativo

    def test_parceira_oco_pelo_gatilho_oposto(self):
        a = mt.criar_meta(self.cfg, "L1", 100, 21.78, agora=self.criada)
        self.assertEqual(mt.parceira_oco(self.cfg, "L1", "stop")["id"], a["id"])
        self.assertIsNone(mt.parceira_oco(self.cfg, "L1", "alvo"))

    def test_resolver_oco_com_as_duas_executadas(self):
        a = {"id": "meta-a", "ticker": "PETR4", "tipo": "Ação", "lote_id": "L1", "qtd": 50, "preco_alvo": 20.0,
             "criada_em": "2026-10-20T11:00:00-03:00", "status": "executada", "oco": "oco-1",
             "execucao": {"data": "2026-10-22", "hora": "10:00", "venda_id": "auto-meta-a"}}
        s = {"id": "meta-s", "ticker": "PETR4", "tipo": "Ação", "lote_id": "L1", "qtd": 50, "gatilho": "stop",
             "stop_inicial": 9.0, "stop_atual": 9.0, "movel": False, "niveis": [], "oco": "oco-1",
             "criada_em": "2026-10-20T11:00:00-03:00", "status": "executada",
             "execucao": {"data": "2026-10-21", "hora": "10:00", "venda_id": "auto-meta-s"}}
        d = nc.carregar("2026-10")
        d["lotes"][0]["vendas"] += [{"id": "auto-meta-a", "data": "2026-10-22", "qtd": 50, "preco": 20.0},
                                    {"id": "auto-meta-s", "data": "2026-10-21", "qtd": 50, "preco": 9.0}]
        alterados = nc.resolver_oco({"2026-10": d}, [a, s])
        self.assertEqual(alterados, {"2026-10"})
        self.assertEqual((a["status"], s["status"]), ("cancelada", "executada"))     # o stop foi o mais cedo
        self.assertEqual([v["id"] for v in d["lotes"][0]["vendas"]], ["auto-meta-s"])
        self.assertIn("auto-meta-a", d["excluidos"])
        self.assertEqual(a["cancelada_por"], "meta-s")

    def test_mesclar_tudo_resolve_oco_duplo(self):
        a, s = self.par()
        # aparelho 1 executou o alvo, aparelho 2 executou o stop
        d = nc.carregar("2026-10")
        d["lotes"][0]["vendas"] += [{"id": "auto-" + a["id"], "data": "2026-10-22", "qtd": 100, "preco": 21.78}]
        nc.salvar(d)
        remoto_metas = [{**m, "status": "executada", "mod": 5e9, "execucao": {
            "data": "2026-10-21", "hora": "10:00", "venda_id": "auto-" + m["id"], "preco_usado": 9.0}}
            for m in self.cfg["metas"] if m["id"] == s["id"]]
        local = nc.ler_config()
        for m in local["metas"]:
            if m["id"] == a["id"]:
                m.update(status="executada", execucao={"data": "2026-10-22", "hora": "10:00",
                                                       "venda_id": "auto-" + a["id"], "preco_usado": 21.78})
        remoto_mes = nc.mes_vazio("2026-10")
        remoto_mes["lotes"].append({**self.lote(), "vendas": [
            {"id": "auto-" + s["id"], "data": "2026-10-21", "qtd": 100, "preco": 9.0, "mod": 9e9}]})
        self.assertTrue(nc.mesclar_tudo(({"2026-10": remoto_mes}, [], [], {}), local, metas_r=remoto_metas))
        ids = [v["id"] for v in self.lote()["vendas"]]
        self.assertEqual(ids, ["auto-" + s["id"]])
        por_id = {m["id"]: m for m in local["metas"]}
        self.assertEqual((por_id[a["id"]]["status"], por_id[s["id"]]["status"]), ("cancelada", "executada"))


class TestCompatibilidadeStop(Base):
    def test_planilha_ida_e_volta_do_stop(self):
        m = mt.criar_stop(self.cfg, "L1", 100, 9.0, movel=True, agora=self.criada,
                          sugestao={"modo": "swing", "atr14": 0.5, "atr22": 0.6, "compra": 10.0})
        m["niveis"].append({"desde": "2026-10-22", "stop": 9.4, "calc_em": "2026-10-21"})
        m["stop_atual"] = 9.4
        m["oco"] = "oco-x"
        linhas = nc.montar_linhas(nc.listar_meses(), self.cfg)["Metas"]
        self.assertEqual(len(linhas[0]), 14)
        self.assertEqual(linhas[0][5], "")          # Preço-alvo vazio no stop
        self.assertEqual(linhas[0][12], "stop")
        volta = nc.reconstruir_metas({"Metas": linhas})[0]
        for k in ("id", "ticker", "lote_id", "qtd", "gatilho", "stop_inicial", "stop_atual", "movel", "niveis",
                  "oco", "criada_em", "status", "sugestao"):
            self.assertEqual(volta[k], m[k], k)
        self.assertNotIn("preco_alvo", volta)

    def test_detalhes_de_outro_id_sao_ignorados(self):
        mt.criar_stop(self.cfg, "L1", 100, 9.0, agora=self.criada)
        linha = nc.montar_linhas(nc.listar_meses(), self.cfg)["Metas"][0]
        linha[0] = "meta-outro"        # linha reordenada/colada: os detalhes são de outra meta
        self.assertEqual(nc.reconstruir_metas({"Metas": [linha]}), [])      # stop sem detalhes válidos não vira meta
        mt.cancelar_meta(self.cfg, self.cfg["metas"][0]["id"])
        alvo = self.criar()
        alvo["oco"] = "oco-z"
        linha = next(l for l in nc.montar_linhas(nc.listar_meses(), self.cfg)["Metas"] if l[0] == alvo["id"])
        linha[0] = "meta-trocada"
        volta = nc.reconstruir_metas({"Metas": [linha]})[0]
        self.assertNotIn("oco", volta)
        self.assertEqual(volta["preco_alvo"], 21.78)

    def test_linha_de_12_colunas_e_alvo(self):
        m = self.criar()
        linha = nc.montar_linhas(nc.listar_meses(), self.cfg)["Metas"][0][:12]
        volta = nc.reconstruir_metas({"Metas": [linha]})[0]
        self.assertEqual((volta["id"], volta["preco_alvo"]), (m["id"], 21.78))
        self.assertEqual(mt.gatilho(volta), "alvo")

    def test_parser_antigo_de_12_colunas_pula_o_stop(self):
        mt.criar_stop(self.cfg, "L1", 100, 9.0, agora=self.criada)
        linha = nc.montar_linhas(nc.listar_meses(), self.cfg)["Metas"][0][:12]
        with self.assertRaises(ValueError):
            float(linha[5])        # é o que o parser antigo faz com o Preço-alvo vazio: pula a linha

    def test_planilha_tem_14_colunas_na_aba_metas(self):
        import google_sync as gs
        self.assertEqual(len(gs.ABAS["Metas"]["colunas"]), 14)
        self.assertEqual([c[0] for c in gs.ABAS["Metas"]["colunas"][-2:]], ["Gatilho", "Detalhes"])

    def test_mesclagem_do_stop_movel_fica_com_o_maior(self):
        base = {"id": "meta-s", "ticker": "PETR4", "tipo": "Ação", "lote_id": "L1", "qtd": 100, "gatilho": "stop",
                "stop_inicial": 5.0, "movel": True, "criada_em": "2026-10-20T11:00:00-03:00", "status": "ativa"}
        n0 = {"desde": "2026-10-20", "stop": 5.0, "calc_em": "2026-10-20"}
        local = {**base, "mod": 1, "stop_atual": 7.0,
                 "niveis": [n0, {"desde": "2026-10-22", "stop": 7.0, "calc_em": "2026-10-21"}]}
        remoto = {**base, "mod": 2, "stop_atual": 6.0,
                  "niveis": [n0, {"desde": "2026-10-21", "stop": 6.0, "calc_em": "2026-10-20"},
                             {"desde": "2026-10-22", "stop": 6.5, "calc_em": "2026-10-21"}]}
        r = nc.mesclar_metas([local], [remoto])[0]
        self.assertEqual(r["stop_atual"], 7.0)
        self.assertEqual([(n["desde"], n["stop"]) for n in r["niveis"]],
                         [("2026-10-20", 5.0), ("2026-10-21", 6.0), ("2026-10-22", 7.0)])
        r = nc.mesclar_metas([remoto], [local])[0]
        self.assertEqual(r["stop_atual"], 7.0)

    def test_mesclagem_nao_une_stop_executado(self):
        base = {"id": "meta-s", "ticker": "PETR4", "tipo": "Ação", "lote_id": "L1", "qtd": 100, "gatilho": "stop",
                "stop_inicial": 5.0, "movel": True, "criada_em": "2026-10-20T11:00:00-03:00", "mod": 1,
                "niveis": [], "stop_atual": 5.0}
        r = nc.mesclar_metas([{**base, "status": "executada", "stop_atual": 5.0}],
                             [{**base, "status": "ativa", "stop_atual": 8.0}])[0]
        self.assertEqual((r["status"], r["stop_atual"]), ("executada", 5.0))

    def test_descricao_do_stop(self):
        a = mt.criar_meta(self.cfg, "L1", 100, 12.0, agora=self.criada)
        s = mt.criar_stop(self.cfg, "L1", 100, 9.0, movel=True, oco_com=a["id"], agora=self.criada)
        d = mt.descricao(s, self.cfg["metas"])
        self.assertEqual(d["titulo"], "PETR4 · 100 un. · stop R$ 9,00 (móvel)")
        self.assertIn("OCO com alvo R$ 12,00", d["detalhe"])
        self.assertIn("OCO com stop R$ 9,00", mt.descricao(a, self.cfg["metas"])["detalhe"])


BASE_ALVO = {"id": "meta-a", "ticker": "PETR4", "tipo": "Ação", "lote_id": "L1", "qtd": 100, "preco_alvo": 20.0,
             "criada_em": "2026-10-20T11:00:00-03:00"}
BASE_STOP = {"id": "meta-s", "ticker": "PETR4", "tipo": "Ação", "lote_id": "L1", "qtd": 100, "gatilho": "stop",
             "stop_inicial": 5.0, "stop_atual": 5.0, "movel": True, "niveis": [], "criada_em": "2026-10-20T11:00:00-03:00"}


class TestRevisaoMesclagem(Base):
    """Itens 1a, 3 e 11 da revisão de "Sugestões de alvo e stop"."""

    def test_aparelho_antigo_nao_apaga_o_oco_na_mesclagem(self):
        novo = {**BASE_ALVO, "status": "ativa", "mod": 1, "oco": "oco-1", "cancelada_por": "x"}
        antigo = {**BASE_ALVO, "status": "executada", "mod": 2,
                  "execucao": {"data": "2026-10-22", "hora": "10:00", "venda_id": "auto-meta-a"}}
        for local, remoto in (([antigo], [novo]), ([novo], [antigo])):
            r = nc.mesclar_metas(local, remoto)[0]
            self.assertEqual(r["status"], "executada")
            self.assertEqual(r["oco"], "oco-1")
            self.assertNotIn("cancelada_por", r)       # só vale numa meta cancelada

    def test_campos_novos_do_perdedor_em_meta_cancelada(self):
        novo = {**BASE_STOP, "status": "cancelada", "mod": 1, "oco": "oco-1", "cancelada_por": "meta-a",
                "cancelada_detalhe": "Cancelada automaticamente (OCO): alvo executado em 22/10"}
        antigo = {**BASE_ALVO, "id": "meta-s", "status": "cancelada", "mod": 2}
        r = nc.mesclar_metas([antigo], [novo])[0]
        self.assertEqual((r["oco"], r["cancelada_por"]), ("oco-1", "meta-a"))
        self.assertIn("cancelada_detalhe", r)

    def test_stop_nao_vira_alvo_nem_alvo_vira_stop_na_uniao(self):
        stop = {**BASE_STOP, "id": "meta-x", "status": "ativa", "mod": 1}
        alvo = {**BASE_ALVO, "id": "meta-x", "status": "ativa", "mod": 2}
        r = nc.mesclar_metas([alvo], [stop])[0]
        self.assertNotIn("gatilho", r)
        self.assertNotIn("stop_atual", r)

    def test_stop_de_12_colunas_vencedor_recupera_os_campos_do_outro(self):
        # registro vencedor de um stop sem os campos novos (reescrito por aparelho antigo): recupera tudo do outro
        novo = {**BASE_STOP, "status": "ativa", "mod": 1, "oco": "oco-1", "stop_atual": 7.0,
                "niveis": [{"desde": "2026-10-20", "stop": 7.0, "calc_em": "2026-10-20"}]}
        pobre = {k: v for k, v in BASE_ALVO.items() if k != "preco_alvo"}
        pobre.update(id="meta-s", status="executada", mod=2)
        r = nc.mesclar_metas([pobre], [novo])[0]
        self.assertEqual((r["gatilho"], r["oco"], r["stop_atual"]), ("stop", "oco-1", 7.0))

    def test_cancelada_vence_ativa_mesmo_mais_antiga(self):
        n0 = {"desde": "2026-10-20", "stop": 5.0, "calc_em": "2026-10-20"}
        n1 = {"desde": "2026-10-22", "stop": 7.0, "calc_em": "2026-10-21"}
        cancelada = {**BASE_STOP, "status": "cancelada", "mod": 1, "niveis": [n0]}
        ativa = {**BASE_STOP, "status": "ativa", "mod": 9, "niveis": [n0, n1], "stop_atual": 7.0}
        for local, remoto in (([cancelada], [ativa]), ([ativa], [cancelada])):
            r = nc.mesclar_metas(local, remoto)[0]
            self.assertEqual(r["status"], "cancelada")
            self.assertEqual(r["stop_atual"], 7.0)         # os níveis continuam unidos
            self.assertEqual(len(r["niveis"]), 2)

    def test_subida_do_stop_movel_nao_carimba_mod(self):
        m = mt.criar_stop(self.cfg, "L1", 100, 4.0, movel=True, agora=self.criada)
        m["mod"] = 1.0
        nc.gravar_config(self.cfg, carimbar=False)
        barras = [{"data": datetime(2026, 10, 22).date() - timedelta(days=29 - i), "abre": 10.0, "alta": 11.0,
                   "baixa": 9.0, "fech": 10.0} for i in range(30)]
        self.assertTrue(mt.atualizar_stop_movel(m, barras, datetime(2026, 10, 25).date()))
        nc.gravar_config(self.cfg)
        gravada = nc.ler_config()["metas"][0]
        self.assertEqual(gravada["stop_atual"], 5.0)
        self.assertEqual(gravada["mod"], 1.0)
        self.assertEqual(gravada["status"], "ativa")
        m["status"] = "cancelada"                       # outra mudança continua carimbando
        nc.gravar_config(self.cfg)
        self.assertGreater(nc.ler_config()["metas"][0]["mod"], 1.0)

    def test_lotes_abertos_escolhe_a_ultima_copia_antes_de_filtrar(self):
        d = nc.mes_vazio("2026-11")
        d["lotes"].append({"id": "L1~2026-11", "origem": "L1", "ticker": "PETR4", "tipo": "Ação",
                           "data_compra": "2026-10-01", "qtd": 100, "preco": 10.0,
                           "vendas": [{"id": "v1", "data": "2026-11-03", "qtd": 100, "preco": 12.0}]})
        nc.salvar(d)
        self.assertEqual(mt._lotes_abertos(mt._carregar_meses()), [])


class TestRevisaoReconstruir(Base):
    """Item 2."""

    def linha_stop(self):
        mt.criar_stop(self.cfg, "L1", 100, 9.0, movel=True, agora=self.criada)
        return nc.montar_linhas(nc.listar_meses(), self.cfg)["Metas"][0]

    def test_gatilho_stop_com_detalhes_invalidos_e_preco_valido_vira_alvo(self):
        linha = self.linha_stop()
        linha[5] = 12.5
        linha[13] = "{isto não é json"
        volta = nc.reconstruir_metas({"Metas": [linha]})
        self.assertEqual(len(volta), 1)
        self.assertEqual((volta[0]["preco_alvo"], mt.gatilho(volta[0])), (12.5, "alvo"))
        self.assertNotIn("stop_atual", volta[0])

    def test_detalhes_sem_campos_de_stop_nunca_levantam_keyerror(self):
        linha = self.linha_stop()
        linha[13] = '{"id": "%s", "gatilho": "stop"}' % linha[0]
        self.assertEqual(nc.reconstruir_metas({"Metas": [list(linha)]}), [])          # sem preço-alvo: descartada
        linha[5] = 12.5
        volta = nc.reconstruir_metas({"Metas": [linha]})
        self.assertEqual((volta[0]["preco_alvo"], mt.gatilho(volta[0])), (12.5, "alvo"))

    def test_detalhes_de_niveis_malformados(self):
        linha = self.linha_stop()
        linha[13] = ('{"id": "%s", "gatilho": "stop", "stop_inicial": 9, "stop_atual": 9, "niveis": [{"x": 1}]}'
                     % linha[0])
        self.assertEqual(nc.reconstruir_metas({"Metas": [linha]}), [])

    def test_stop_valido_continua_stop(self):
        volta = nc.reconstruir_metas({"Metas": [self.linha_stop()]})[0]
        self.assertEqual((mt.gatilho(volta), volta["stop_atual"]), ("stop", 9.0))


class TestRevisaoOco(Base):
    """Itens 1b, 4, 5, 7 e 8."""

    def setUp(self):
        super().setUp()
        d = nc.carregar("2026-10")
        d["lotes"][0]["qtd"] = 200
        nc.salvar(d)

    def par(self, qtd=100):
        a = mt.criar_meta(self.cfg, "L1", qtd, 21.78, agora=self.criada)
        s = mt.criar_stop(self.cfg, "L1", qtd, 9.0, oco_com=a["id"], agora=self.criada)
        return a, s

    def vendas(self):
        return [v["id"] for v in self.lote()["vendas"]]

    def registrar_venda(self, meta, data, preco, hora="10:00", oco=True):
        d = nc.carregar("2026-10")
        d["lotes"][0]["vendas"].append({"id": "auto-" + meta["id"], "data": data, "qtd": meta["qtd"], "preco": preco})
        nc.salvar(d)
        meta["status"] = "executada"
        meta["execucao"] = {"venda_id": "auto-" + meta["id"], "data": data, "hora": hora, "preco_usado": preco,
                            "origem": "teste", "barra_ts": 0, "motivo": "teste"}
        if not oco:
            meta.pop("oco", None)
        nc.gravar_config(self.cfg)

    # --- item 1b
    def test_alvo_executado_sem_oco_cancela_o_stop_com_oco(self):
        a, s = self.par()
        self.registrar_venda(a, "2026-10-21", 21.78, oco=False)        # aparelho antigo perdeu o "oco" do alvo
        rel = self.verificar([barra_s("2026-10-22T10:00:00", 10, 8.5, 9.5)])
        self.assertEqual(rel["executadas"], [])
        por_id = {m["id"]: m for m in self.cfg["metas"]}
        self.assertEqual(por_id[s["id"]]["status"], "cancelada")
        self.assertEqual(por_id[s["id"]]["cancelada_por"], a["id"])
        self.assertEqual(self.vendas(), ["auto-" + a["id"]])
        self.assertTrue(rel["mudou"])

    def test_stop_executado_sem_oco_cancela_o_alvo_com_oco(self):
        a, s = self.par()
        self.registrar_venda(s, "2026-10-21", 9.0, oco=False)
        rel = self.verificar([barra("2026-10-22T10:00:00", 30.0)])
        self.assertEqual(rel["executadas"], [])
        por_id = {m["id"]: m for m in self.cfg["metas"]}
        self.assertEqual(por_id[a["id"]]["status"], "cancelada")
        self.assertEqual(self.vendas(), ["auto-" + s["id"]])

    def test_stop_de_outro_par_nao_e_cancelado(self):
        # alvo avulso executado; o stop tem como parceiro outro alvo ativo: é outro OCO, não pode ser cancelado
        avulso = mt.criar_meta(self.cfg, "L1", 100, 25.0, agora=self.criada)
        d = nc.carregar("2026-10")
        d["lotes"][0]["qtd"] = 300
        nc.salvar(d)
        a2, s2 = self.par()
        self.registrar_venda(avulso, "2026-10-21", 25.0)
        self.verificar([barra_s("2026-10-22T10:00:00", 10, 8.5, 9.5)])
        por_id = {m["id"]: m for m in self.cfg["metas"]}
        self.assertEqual(por_id[s2["id"]]["status"], "executada")
        self.assertEqual(por_id[a2["id"]]["status"], "cancelada")

    def test_quantidade_diferente_nao_cancela(self):
        a = mt.criar_meta(self.cfg, "L1", 50, 21.78, agora=self.criada)
        s = mt.criar_stop(self.cfg, "L1", 100, 9.0, agora=self.criada)
        s["oco"] = "oco-solto"
        self.registrar_venda(a, "2026-10-21", 21.78, oco=False)
        self.verificar([barra_s("2026-10-22T10:00:00", 10, 8.5, 9.5)])
        self.assertEqual({m["id"]: m for m in self.cfg["metas"]}[s["id"]]["status"], "executada")

    # --- item 4
    def test_resolver_oco_mes_fechado_nao_apaga_a_venda(self):
        a, s = self.par()
        self.registrar_venda(a, "2026-10-22", 21.78)
        self.registrar_venda(s, "2026-10-21", 9.0)
        d = nc.carregar("2026-10")
        d["fechado"] = True
        avisos = []
        alterados = nc.resolver_oco({"2026-10": d}, self.cfg["metas"], avisos)
        self.assertEqual(alterados, set())
        self.assertEqual([v["id"] for v in d["lotes"][0]["vendas"]], ["auto-" + a["id"], "auto-" + s["id"]])
        self.assertNotIn("auto-" + a["id"], d["excluidos"])
        self.assertEqual(a["status"], "cancelada")
        self.assertIn("fechado", a["cancelada_detalhe"])
        self.assertIn("ajuste manual", a["cancelada_detalhe"])
        self.assertEqual(len(avisos), 1)
        self.assertIn(a["ticker"], avisos[0])

    def test_mesclar_tudo_devolve_aviso_de_mes_fechado(self):
        a, s = self.par()
        self.registrar_venda(a, "2026-10-22", 21.78)
        self.registrar_venda(s, "2026-10-21", 9.0)
        d = nc.carregar("2026-10")
        d["fechado"] = True
        nc.salvar(d)
        avisos = []
        nc.mesclar_tudo(({}, [], [], {}), self.cfg, metas_r=[], avisos=avisos)
        self.assertEqual(len(avisos), 1)
        self.assertEqual(self.vendas(), ["auto-" + a["id"], "auto-" + s["id"]])

    # --- item 5
    def test_reconciliacao_com_as_duas_vendas_remove_a_perdedora(self):
        a, s = self.par()
        d = nc.carregar("2026-10")
        d["lotes"][0]["vendas"] += [{"id": "auto-" + a["id"], "data": "2026-10-22", "qtd": 100, "preco": 21.78},
                                    {"id": "auto-" + s["id"], "data": "2026-10-21", "qtd": 100, "preco": 9.0}]
        nc.salvar(d)           # as duas vendas existem, mas as duas metas ainda estão ativas (queda no meio)
        rel = self.verificar([barra("2026-10-22T10:00:00", 1.0)])
        por_id = {m["id"]: m for m in self.cfg["metas"]}
        self.assertEqual((por_id[a["id"]]["status"], por_id[s["id"]]["status"]), ("cancelada", "executada"))
        self.assertEqual(self.vendas(), ["auto-" + s["id"]])
        self.assertIn("auto-" + a["id"], nc.carregar("2026-10")["excluidos"])
        self.assertTrue(rel["mudou"])

    def test_reconciliacao_com_as_duas_vendas_em_mes_fechado_avisa(self):
        a, s = self.par()
        d = nc.carregar("2026-10")
        d["lotes"][0]["vendas"] += [{"id": "auto-" + a["id"], "data": "2026-10-22", "qtd": 100, "preco": 21.78},
                                    {"id": "auto-" + s["id"], "data": "2026-10-21", "qtd": 100, "preco": 9.0}]
        d["fechado"] = True
        nc.salvar(d)
        rel = self.verificar([barra("2026-10-22T10:00:00", 1.0)])
        self.assertEqual(len(self.vendas()), 2)
        self.assertEqual(len(rel["avisos"]), 1)

    # --- item 7
    def exec_(self, base, **ex):
        return {**base, "status": "executada", "oco": "oco-1", "execucao": ex}

    def test_empate_de_data_com_hora_vazia_prefere_o_stop(self):
        alvo = self.exec_(BASE_ALVO, data="2026-10-22", hora="", venda_id="auto-meta-a")
        stop = self.exec_(BASE_STOP, data="2026-10-22", hora="10:00", venda_id="auto-meta-s")
        nc.resolver_oco({}, [alvo, stop])
        self.assertEqual((alvo["status"], stop["status"]), ("cancelada", "executada"))
        alvo = self.exec_(BASE_ALVO, data="2026-10-22", hora="10:00", venda_id="auto-meta-a")
        stop = self.exec_(BASE_STOP, data="2026-10-22", hora="", venda_id="auto-meta-s")
        nc.resolver_oco({}, [alvo, stop])
        self.assertEqual((alvo["status"], stop["status"]), ("cancelada", "executada"))

    def test_barra_ts_desempata_quando_disponivel(self):
        alvo = self.exec_(BASE_ALVO, data="2026-10-22", hora="10:00", barra_ts=100, venda_id="auto-meta-a")
        stop = self.exec_(BASE_STOP, data="2026-10-22", hora="10:00", barra_ts=200, venda_id="auto-meta-s")
        nc.resolver_oco({}, [alvo, stop])
        self.assertEqual((alvo["status"], stop["status"]), ("executada", "cancelada"))

    def test_data_mais_cedo_continua_vencendo(self):
        alvo = self.exec_(BASE_ALVO, data="2026-10-21", hora="", venda_id="auto-meta-a")
        stop = self.exec_(BASE_STOP, data="2026-10-22", hora="10:00", venda_id="auto-meta-s")
        nc.resolver_oco({}, [alvo, stop])
        self.assertEqual((alvo["status"], stop["status"]), ("executada", "cancelada"))

    # --- item 8
    def test_meta_cancelada_pelo_oco_recebe_mod_novo(self):
        alvo = {**self.exec_(BASE_ALVO, data="2026-10-22", hora="10:00", venda_id="auto-meta-a"), "mod": 1.0}
        stop = {**self.exec_(BASE_STOP, data="2026-10-21", hora="10:00", venda_id="auto-meta-s"), "mod": 1.0}
        nc.resolver_oco({}, [alvo, stop])
        self.assertGreater(alvo["mod"], 1.0)
        self.assertEqual(stop["mod"], 1.0)


class TestRevisaoStopMovel(Base):
    """Itens 9 e 10."""

    def barras_aleatorias(self, n=120):
        import random
        r = random.Random(7)
        preco, saida = 10.0, []
        for i in range(n):
            abre = preco
            preco = max(1.0, preco + r.uniform(-0.6, 0.7))
            saida.append({"data": datetime(2026, 6, 1).date() + timedelta(days=i), "abre": abre,
                          "alta": max(abre, preco) + r.uniform(0, 0.4), "baixa": min(abre, preco) - r.uniform(0, 0.4),
                          "fech": preco})
        return saida

    def referencia(self, meta, barras, hoje):
        """Algoritmo anterior: recalcula o Chandelier de todo o prefixo a cada pregão."""
        criada = mt._dt(meta["criada_em"]).date()
        fechadas = sorted((b for b in barras if b["data"] < hoje), key=lambda b: b["data"])
        niveis = meta.setdefault("niveis", [])
        ultimo = max([n["stop"] for n in niveis] + [meta["stop_atual"]])
        for i, b in enumerate(fechadas):
            if b["data"] < criada:
                continue
            c = mk.calcular_chandelier(fechadas[:i + 1])
            if c is None:
                continue
            novo = mt.piso_centavo(c)
            if novo > ultimo + 1e-9:
                niveis.append({"desde": (b["data"] + timedelta(days=1)).isoformat(), "stop": novo,
                               "calc_em": b["data"].isoformat()})
                ultimo = novo
        meta["stop_atual"] = ultimo

    def test_passada_incremental_equivale_ao_recalculo_completo(self):
        barras = self.barras_aleatorias()
        for inicio, hoje in ((3.0, datetime(2026, 9, 20)), (8.0, datetime(2026, 9, 29)), (1.0, datetime(2026, 10, 1))):
            a = mt.criar_stop(self.cfg, "L1", 100, inicio, movel=True, agora=dt("2026-06-05T11:00:00"))
            b = {**a, "niveis": [dict(n) for n in a["niveis"]]}
            self.cfg["metas"].clear()
            mt.atualizar_stop_movel(a, barras, hoje.date())
            self.referencia(b, barras, hoje.date())
            self.assertEqual(a["niveis"], b["niveis"])
            self.assertEqual(a["stop_atual"], b["stop_atual"])
            self.assertGreater(len(a["niveis"]), 1)

    def test_serie_chandelier_igual_ao_calculo_por_prefixo(self):
        barras = self.barras_aleatorias(60)
        serie = mk.serie_chandelier(barras)
        self.assertEqual(len(serie), len(barras))
        for i, valor in enumerate(serie):
            self.assertEqual(valor, mk.calcular_chandelier(barras[:i + 1]))

    def test_nao_recalcula_o_atr_a_cada_pregao(self):
        m = mt.criar_stop(self.cfg, "L1", 100, 1.0, movel=True, agora=dt("2026-06-05T11:00:00"))
        original, chamadas = mk.calcular_atr, []
        mk.calcular_atr = lambda *a, **k: chamadas.append(1) or original(*a, **k)
        try:
            mt.atualizar_stop_movel(m, self.barras_aleatorias(), datetime(2026, 10, 1).date())
        finally:
            mk.calcular_atr = original
        self.assertLessEqual(len(chamadas), 2)

    def test_hoje_do_stop_movel_nao_fica_atras_do_relogio(self):
        m = mt.criar_stop(self.cfg, "L1", 100, 4.0, movel=True, agora=self.criada)
        barras = [{"data": datetime(2026, 10, 22).date() - timedelta(days=29 - i), "abre": 10.0, "alta": 11.0,
                   "baixa": 9.0, "fech": 10.0} for i in range(29)]
        barras.append({"data": datetime(2026, 10, 22).date(), "abre": 19.0, "alta": 20.0, "baixa": 19.0, "fech": 20.0})
        cache_velho = {"barras": barras, "hoje": datetime(2026, 10, 22).date()}      # cache de 22/10 lido em 25/10
        hist = {"barras": [barra_s("2026-10-23T10:00:00", 30.0, 25.0, 26.0)], "diarias": cache_velho}
        mt.aplicar(self.cfg, {"PETR4": ("ok", hist)}, agora=dt("2026-10-25T18:00:00"))
        self.assertGreater(m["stop_atual"], 12.0)      # o pregão de 22/10 já estava fechado


class TestHistoricoComBaixaEAbertura(unittest.TestCase):
    def test_barras_trazem_baixa_e_abre(self):
        original = mk._get_chart
        mk._get_chart = lambda t, p: {"meta": {"gmtoffset": -10800}, "timestamp": [1761051600, 1761055200],
                                      "indicators": {"quote": [{"high": [21.5, None], "low": [20.9, 20.0],
                                                                "open": [None, 21.0]}]}}
        try:
            h = mk.historico_desde("PETR4", datetime(2026, 10, 20, 11), datetime(2026, 10, 22, 12, tzinfo=FUSO))
        finally:
            mk._get_chart = original
        self.assertEqual(len(h["barras"]), 1)
        b = h["barras"][0]
        self.assertEqual((b["alta"], b["baixa"], b["abre"]), (21.5, 20.9, None))

    def test_baixa_ausente_fica_none(self):
        original = mk._get_chart
        mk._get_chart = lambda t, p: {"meta": {}, "timestamp": [1761051600], "indicators": {"quote": [{"high": [21.5]}]}}
        try:
            h = mk.historico_desde("PETR4", datetime(2026, 10, 20, 11), datetime(2026, 10, 22, 12, tzinfo=FUSO))
        finally:
            mk._get_chart = original
        self.assertEqual((h["barras"][0]["baixa"], h["barras"][0]["abre"]), (None, None))


if __name__ == "__main__":
    unittest.main()
