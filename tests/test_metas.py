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
        self.assertEqual(len(gs.ABAS["Metas"]["colunas"]), 12)


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


if __name__ == "__main__":
    unittest.main()
