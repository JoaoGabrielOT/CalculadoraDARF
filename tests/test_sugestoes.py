import sys
import tempfile
import unittest
from datetime import date, timedelta
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import mercado as mk  # noqa: E402
import metas as mt  # noqa: E402
import nucleo as nc  # noqa: E402
import sugestoes as sg  # noqa: E402


def barras_planas(n=30, alta=11.0, baixa=9.0, fech=10.0, fim=date(2026, 10, 28)):
    """n pregões consecutivos terminando em `fim` (sem se preocupar com fins de semana)."""
    return [{"data": fim - timedelta(days=n - 1 - i), "abre": fech, "alta": alta, "baixa": baixa, "fech": fech}
            for i in range(n)]


def lote(preco=10.0, data="2026-10-01", qtd=100, vendas=None):
    return {"id": "L1", "ticker": "PETR4", "tipo": "Ação", "data_compra": data, "qtd": qtd, "preco": preco,
            "vendas": vendas or []}


class TestIndicadores(unittest.TestCase):
    def test_atr_de_barras_planas(self):
        b = barras_planas()
        h, l, c = [x["alta"] for x in b], [x["baixa"] for x in b], [x["fech"] for x in b]
        self.assertAlmostEqual(mk.calcular_atr(h, l, c, 14), 2.0)
        self.assertAlmostEqual(mk.calcular_atr(h, l, c, 22), 2.0)

    def test_pivos(self):
        p = mk.calcular_pivos(12, 9, 10.5)
        self.assertAlmostEqual(p["pp"], 10.5)
        self.assertAlmostEqual(p["r1"], 12.0)
        self.assertAlmostEqual(p["s1"], 9.0)

    def test_chandelier(self):
        self.assertAlmostEqual(mk.calcular_chandelier(barras_planas()), 5.0)   # 11 - 3*2
        self.assertIsNone(mk.calcular_chandelier(barras_planas(22)))           # precisa de 23 barras
        self.assertIsNotNone(mk.calcular_chandelier(barras_planas(23)))

    def test_piso_e_teto_de_centavo(self):
        self.assertEqual(mt.piso_centavo(5.999999999), 6.0)
        self.assertEqual(mt.piso_centavo(5.989), 5.98)
        self.assertEqual(mt.teto_centavo(5.981), 5.99)


class TestSugestoes(unittest.TestCase):
    def test_swing(self):
        s = sg.sugestao_swing(10.0, barras_planas())
        self.assertAlmostEqual(s["stop_inicial"], 6.0)
        self.assertAlmostEqual(s["chandelier"], 5.0)
        self.assertEqual(s["stop"], 6.0)
        self.assertEqual(s["alvo"], 18.0)
        self.assertEqual(s["modo"], "swing")

    def test_swing_chandelier_maior_vence(self):
        b = barras_planas()
        for x in b[-5:]:
            x["alta"] = 20.0
        s = sg.sugestao_swing(10.0, b)
        self.assertGreater(s["chandelier"], s["stop_inicial"])
        self.assertEqual(s["stop"], mt.piso_centavo(s["chandelier"]))
        self.assertEqual(s["alvo"], mt.teto_centavo(10.0 + 2 * (10.0 - s["stop_inicial"])))   # alvo pelo stop inicial

    def test_swing_historico_curto_sem_movel(self):
        s = sg.sugestao_swing(10.0, barras_planas(18))
        self.assertIsNone(s["chandelier"])
        self.assertFalse(s["movel_disponivel"])
        self.assertEqual(s["stop"], 6.0)

    def test_day_trade(self):
        dia = {"data": date(2026, 10, 28), "alta": 12.0, "baixa": 9.0, "fech": 10.5}
        s = sg.sugestao_day_trade(10.0, dia, 2.0)
        self.assertEqual((s["stop"], s["alvo"]), (9.0, 12.0))
        s = sg.sugestao_day_trade(11.5, dia, 2.0)
        self.assertEqual((s["stop"], s["alvo"]), (9.5, 15.5))
        s = sg.sugestao_day_trade(8.5, dia, 2.0)
        self.assertEqual((s["stop"], s["alvo"]), (6.5, 12.0))
        self.assertAlmostEqual((s["pp"], s["r1"], s["s1"])[1], 12.0)

    def test_volatilidade_zero(self):
        planas = barras_planas(alta=10.0, baixa=10.0, fech=10.0)
        with self.assertRaises(sg.SemSugestao):
            sg.sugestao_swing(10.0, planas)
        with self.assertRaises(sg.SemSugestao):
            sg.sugestao_day_trade(10.0, planas[-1], 0.0)

    def test_sugerir_usa_so_pregoes_fechados(self):
        b = barras_planas(30)   # termina em 28/10
        hoje = date(2026, 10, 28)
        sug = sg.sugerir(lote(), b, hoje, 10.5)
        self.assertEqual(sug["base_data"], date(2026, 10, 27))   # a barra de hoje é parcial e fica de fora
        self.assertEqual(sug["modo"], "swing")

    def test_sugerir_day_trade_quando_comprou_hoje(self):
        hoje = date(2026, 10, 28)
        sug = sg.sugerir(lote(data="2026-10-28"), barras_planas(30), hoje, 10.0)
        self.assertEqual(sug["modo"], "day_trade")
        self.assertTrue(any("swing" in a for a in sug["avisos"]))

    def test_sem_dados_ou_historico_curto(self):
        hoje = date(2026, 10, 28)
        with self.assertRaises(sg.SemSugestao):
            sg.sugerir(lote(), [], hoje, 10.0)
        with self.assertRaises(sg.SemSugestao):
            sg.sugerir(lote(), barras_planas(14, fim=date(2026, 10, 27)), hoje, 10.0)
        sg.sugerir(lote(), barras_planas(15, fim=date(2026, 10, 27)), hoje, 10.0)   # 15 barras fechadas bastam

    def test_desdobramento_ou_grupamento(self):
        hoje = date(2026, 10, 28)
        with self.assertRaises(sg.SemSugestao):
            sg.sugerir(lote(preco=40.0), barras_planas(), hoje, 10.0)     # compra > 3x a cotação
        with self.assertRaises(sg.SemSugestao):
            sg.sugerir(lote(preco=3.0), barras_planas(), hoje, 10.0)      # compra < 1/3 da cotação

    def test_avisos_stop_e_alvo(self):
        hoje = date(2026, 10, 28)
        sug = sg.sugerir(lote(), barras_planas(), hoje, 5.0)    # cotação abaixo do stop 6,00
        self.assertFalse(sug["stop_valido"])
        self.assertTrue(sug["alvo_imediato"] is False)
        sug = sg.sugerir(lote(), barras_planas(), hoje, 20.0)   # cotação acima do alvo 18,00
        self.assertTrue(sug["stop_valido"])
        self.assertTrue(sug["alvo_imediato"])


class TestAvaliacaoERisco(unittest.TestCase):
    def test_stop_swing_liquido(self):
        sug = sg.sugestao_swing(10.0, barras_planas())
        av = sg.avaliar(lote(), 100, sug, 10.0, False)
        self.assertAlmostEqual(av["perda_stop"], -400.48, places=2)
        self.assertEqual(av["proj_stop"]["imposto"], 0)
        self.assertEqual(av["proj_alvo"]["venda"], 1800.0)
        self.assertAlmostEqual(av["rr_preco"], 2.0)
        self.assertGreater(av["lucro_alvo"], 0)
        self.assertAlmostEqual(av["dist_stop_pct"], -40.0)

    def test_alerta_de_2_porcento(self):
        self.assertTrue(sg.alerta_risco(-400.48, 11000)["excede"])     # limite 220
        self.assertFalse(sg.alerta_risco(-400.48, 30000)["excede"])    # limite 600
        self.assertAlmostEqual(sg.alerta_risco(-400.48, 11000)["limite"], 220.0)
        self.assertTrue(sg.alerta_risco(-1, 0)["excede"])


class TestStopAcimaDaCompra(unittest.TestCase):
    """Item 6: com o stop acima da compra o resultado no stop é lucro (após imposto), não perda."""

    def diarias(self):
        return {"barras": barras_planas(alta=20.0, baixa=18.0, fech=19.0), "hoje": date(2026, 10, 28),
                "preco": 19.0, "fonte": "Yahoo Finance"}

    def test_avaliar_usa_o_lucro_apos_imposto(self):
        sug = sg.sugestao_swing(10.0, barras_planas(alta=20.0, baixa=18.0, fech=19.0))
        self.assertGreater(sug["stop"], 10.0)
        av = sg.avaliar(lote(), 100, sug, 19.0, False)
        ps = av["proj_stop"]
        self.assertGreater(ps["imposto"], 0)
        self.assertAlmostEqual(av["perda_stop"], ps["lucro_apos_imposto"])
        self.assertLess(av["perda_stop"], ps["liquido"])

    def test_sem_alerta_e_com_rotulo_de_lucro_protegido(self):
        item = sg.montar_item(lote(), 100, self.diarias(), {"valor": 1000.0}, hoje=date(2026, 10, 28))
        self.assertFalse(item["alerta"]["excede"])
        rotulos = [l[0] for l in sg.linhas_card(item)]
        self.assertNotIn("Alerta de risco", rotulos)
        self.assertNotIn("Risco do stop", rotulos)
        self.assertIn("Lucro protegido no stop", rotulos)
        stop = next(l for l in sg.linhas_card(item) if l[0] == "Stop sugerido")
        self.assertNotIn("perda", stop[1])

    def test_stop_abaixo_da_compra_continua_alertando_a_perda(self):
        item = sg.montar_item(lote(), 100, {"barras": barras_planas(), "hoje": date(2026, 10, 28), "preco": 10.0,
                                            "fonte": "Yahoo Finance"}, {"valor": 11000.0}, hoje=date(2026, 10, 28))
        self.assertTrue(item["alerta"]["excede"])
        rotulos = [l[0] for l in sg.linhas_card(item)]
        self.assertIn("Alerta de risco", rotulos)
        self.assertNotIn("Lucro protegido no stop", rotulos)

    def test_alerta_so_para_resultado_negativo(self):
        self.assertFalse(sg.alerta_risco(400.0, 1000)["excede"])
        self.assertFalse(sg.alerta_risco(0.0, 0)["excede"])
        self.assertTrue(sg.alerta_risco(-400.0, 1000)["excede"])


class TestPatrimonio(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        nc.configurar(self.tmp.name)
        self.cfg = nc.ler_config()
        d = nc.mes_vazio("2026-10")
        d["lotes"].append(lote())
        nc.salvar(d)

    def tearDown(self):
        self.tmp.cleanup()

    def test_caixa_mais_posicoes(self):
        hoje = date(2026, 10, 28)
        nc.definir_saldo(self.cfg, 10000.0, hoje)
        p = sg.patrimonio(self.cfg, {"PETR4": 10.0}, hoje)
        self.assertTrue(p["caixa_definido"])
        self.assertAlmostEqual(p["posicoes"], 1000.0)
        self.assertAlmostEqual(p["valor"], 11000.0)   # a compra de 01/10 já liquidou: não entra no projetado
        self.assertTrue(sg.alerta_risco(-400.48, p)["excede"])
        nc.definir_saldo(self.cfg, 30000.0, hoje)
        p = sg.patrimonio(self.cfg, {"PETR4": 10.0}, hoje)
        self.assertAlmostEqual(p["valor"], 31000.0)
        self.assertFalse(sg.alerta_risco(-400.48, p)["excede"])

    def test_caixa_nao_definido_so_posicoes(self):
        p = sg.patrimonio(self.cfg, {"PETR4": 10.0}, date(2026, 10, 28))
        self.assertFalse(p["caixa_definido"])
        self.assertEqual(p["caixa"], 0.0)
        self.assertAlmostEqual(p["valor"], 1000.0)

    def test_sem_cotacao_fica_de_fora(self):
        p = sg.patrimonio(self.cfg, {}, date(2026, 10, 28))
        self.assertEqual(p["sem_cotacao"], ["PETR4"])
        self.assertEqual(p["posicoes"], 0.0)

    def test_cadeia_de_copias_conta_uma_vez(self):
        d = nc.mes_vazio("2026-11")
        d["lotes"].append({**lote(), "id": "L1~2026-11", "origem": "L1"})
        nc.salvar(d)    # as duas ficam abertas: só a cópia (mês mais recente) conta
        p = sg.patrimonio(self.cfg, {"PETR4": 10.0}, date(2026, 10, 28))
        self.assertAlmostEqual(p["posicoes"], 1000.0)

    def test_resultado_do_mes(self):
        d = nc.carregar("2026-10")
        d["lotes"][0]["vendas"].append({"id": "v1", "data": "2026-10-10", "qtd": 100, "preco": 12.0})
        r = sg.resultado_mes({"2026-10": d}, "2026-10")
        self.assertAlmostEqual(r, nc.calcular_venda(d["lotes"][0], d["lotes"][0]["vendas"][0])["liquido"])
        self.assertEqual(sg.resultado_mes({}, "2026-10"), 0)


class TestTextos(unittest.TestCase):
    def diarias(self, preco=10.0, n=30):
        return {"barras": barras_planas(n), "hoje": date(2026, 10, 28), "preco": preco, "fonte": "Yahoo Finance"}

    def test_item_e_linhas(self):
        item = sg.montar_item(lote(), 100, self.diarias(), {"valor": 11000.0}, hoje=date(2026, 10, 28))
        self.assertIsNone(item["erro"])
        linhas = sg.linhas_card(item)
        rotulos = [l[0] for l in linhas]
        for r in ("Alvo sugerido", "Stop inicial", "Stop móvel", "Stop sugerido", "Risco/retorno", "Alerta de risco"):
            self.assertIn(r, rotulos)

    def test_sem_dados_vira_mensagem(self):
        item = sg.montar_item(lote(), 100, mk.SemDados("Sem dados para PETR4 no Yahoo Finance."))
        self.assertIn("Sem dados", item["erro"])
        self.assertEqual(sg.linhas_card(item)[0][0], "Sugestão")
        item = sg.montar_item(lote(), 100, self.diarias(n=5), hoje=date(2026, 10, 28))
        self.assertIn("insuficiente", item["erro"])

    def test_rodape(self):
        pat = {"valor": 11000.0, "caixa": 10000.0, "posicoes": 1000.0, "caixa_definido": True, "sem_cotacao": []}
        linhas = sg.linhas_rodape(pat, -800.0)
        self.assertEqual(linhas[-1][2], "danger")    # perda do mês acima de 6% (660)
        self.assertIsNone(sg.linhas_rodape(pat, -100.0)[-1][2])


class TestBarrasDiarias(unittest.TestCase):
    def setUp(self):
        self.original = mk._get_chart
        mk._DIARIAS.clear()

    def tearDown(self):
        mk._get_chart = self.original
        mk._DIARIAS.clear()

    def test_barras_data_e_cache(self):
        chamadas = []

        def falso(ticker, params):
            chamadas.append(params)
            return {"meta": {"gmtoffset": -10800, "regularMarketTime": 1761685200, "regularMarketPrice": 10.4},
                    "timestamp": [1761051600, 1761138000, 1761224400],
                    "indicators": {"quote": [{"open": [10, None, 10.2], "high": [11, 11, 11], "low": [9, 9, None],
                                              "close": [10, 10, 10]}]}}
        mk._get_chart = falso
        r = mk.barras_diarias("PETR4")
        self.assertEqual(len(r["barras"]), 2)     # a barra sem mínima é descartada
        self.assertEqual(r["barras"][0]["data"], date(2025, 10, 21))
        self.assertEqual(r["barras"][0]["abre"], 10.0)
        self.assertEqual(r["preco"], 10.4)
        self.assertEqual(r["hoje"], date(2025, 10, 28))
        self.assertEqual(chamadas[0]["range"], "6mo")
        mk.barras_diarias("PETR4")
        self.assertEqual(len(chamadas), 1)        # segunda chamada vem do cache
        mk.barras_diarias("PETR4", desde=date.today() - timedelta(days=300))
        self.assertIn(chamadas[-1]["range"], ("1y", "2y"))

    def test_sem_barras_levanta(self):
        mk._get_chart = lambda t, p: {"meta": {}, "timestamp": [], "indicators": {"quote": [{}]}}
        with self.assertRaises(mk.SemDados):
            mk.barras_diarias("PETR4")

    def test_range_pelo_alcance(self):
        hoje = date.today()
        self.assertEqual(mk._range_diarias(None), "6mo")
        self.assertEqual(mk._range_diarias(hoje - timedelta(days=100)), "6mo")
        self.assertEqual(mk._range_diarias(hoje - timedelta(days=200)), "1y")
        self.assertEqual(mk._range_diarias(hoje - timedelta(days=500)), "2y")
        self.assertEqual(mk._range_diarias(hoje - timedelta(days=900)), "5y")


if __name__ == "__main__":
    unittest.main()
