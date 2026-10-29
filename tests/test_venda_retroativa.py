import sys
import tempfile
import unittest
from datetime import date
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import nucleo as nc  # noqa: E402


class TestVendaRetroativa(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        nc.configurar(Path(self.tmp.name))
        self.d = nc.mes_vazio("2026-10")
        self.d["lotes"].append({"id": "L1", "ticker": "T1TW34", "tipo": "BDR", "data_compra": "2026-05-05",
                                "qtd": 58, "preco": 9.0, "vendas": []})
        nc.salvar(self.d)

    def tearDown(self):
        self.tmp.cleanup()

    def test_meses_livres_e_bloqueados(self):
        self.assertTrue(nc.mes_aceita_venda_retroativa("2026-07", "2026-10"))
        self.assertFalse(nc.mes_aceita_venda_retroativa("2026-10", "2026-10"))   # mês atual: fluxo normal
        set_ = {**nc.mes_vazio("2026-09"), "fechado": True}                       # mês normal com compra levada
        set_["lotes"].append({"id": "S1", "ticker": "X", "tipo": "Ação", "data_compra": "2026-09-01", "qtd": 5,
                              "preco": 1.0, "vendas": []})
        nc.salvar(set_)
        self.assertFalse(nc.mes_aceita_venda_retroativa("2026-09", "2026-10"))
        nc.salvar({**nc.mes_vazio("2026-08")})                                   # mês aberto
        self.assertFalse(nc.mes_aceita_venda_retroativa("2026-08", "2026-10"))

    def test_mes_retroativo_vale_sem_a_marcacao(self):
        nc.registrar_venda_retroativa(self.d, "L1", {"data": "2026-07-15", "qtd": 20, "preco": 10.0})
        jul = nc.carregar("2026-07")
        jul.pop("retroativo")                     # a planilha não guarda essa marcação
        nc.salvar(jul)
        self.assertTrue(nc.mes_aceita_venda_retroativa("2026-07", "2026-10"))

    def test_grava_no_mes_da_venda_e_reduz_compra_atual(self):
        venda = {"data": "2026-07-15", "qtd": 20, "preco": 10.0}
        mes = nc.registrar_venda_retroativa(self.d, "L1", venda)
        self.assertEqual(mes, "2026-07")
        jul = nc.carregar("2026-07")
        self.assertTrue(jul["fechado"])
        self.assertTrue(jul["retroativo"])
        self.assertEqual(len(jul["lotes"]), 1)
        l = jul["lotes"][0]
        self.assertEqual((l["ticker"], l["data_compra"], l["qtd"], l["preco"]), ("T1TW34", "2026-05-05", 20, 9.0))
        self.assertEqual([(v["data"], v["qtd"], v["preco"]) for v in l["vendas"]], [("2026-07-15", 20, 10.0)])
        self.assertAlmostEqual(jul["resumo"]["darf"], nc.apurar(jul)["darf"])
        self.assertEqual(nc.carregar("2026-10")["lotes"][0]["qtd"], 38)
        self.assertTrue(nc.mes_aceita_venda_retroativa("2026-07", "2026-10"))   # outra venda de julho continua possível
        self.assertEqual(nc.mes_inicial(), "2026-10")

    def test_venda_total_remove_compra_do_mes_atual(self):
        nc.registrar_venda_retroativa(self.d, "L1", {"data": "2026-07-15", "qtd": 58, "preco": 10.0})
        self.assertEqual(nc.carregar("2026-10")["lotes"], [])

    def test_segunda_venda_no_mesmo_mes(self):
        nc.registrar_venda_retroativa(self.d, "L1", {"data": "2026-07-15", "qtd": 20, "preco": 10.0})
        nc.registrar_venda_retroativa(self.d, "L1", {"data": "2026-07-20", "qtd": 8, "preco": 11.0})
        jul = nc.carregar("2026-07")
        self.assertEqual(sum(l["qtd"] for l in jul["lotes"]), 28)
        self.assertEqual(nc.carregar("2026-10")["lotes"][0]["qtd"], 30)

    def test_recusa_compra_com_venda_no_mes_atual(self):
        # reduzir a quantidade mudaria a corretagem (e a DARF) da venda já feita no mês atual
        self.d["lotes"][0]["vendas"].append({"id": "V1", "data": "2026-10-10", "qtd": 10, "preco": 10.0})
        with self.assertRaises(ValueError):
            nc.registrar_venda_retroativa(self.d, "L1", {"data": "2026-07-15", "qtd": 20, "preco": 10.0})
        self.assertFalse(nc.arquivo("2026-07").exists())
        self.assertEqual(self.d["lotes"][0]["qtd"], 58)

    def test_darf_pequena_vai_para_o_mes_aberto(self):
        # lucro pequeno: DARF de julho < R$ 10 entra como darf_anterior de outubro
        nc.registrar_venda_retroativa(self.d, "L1", {"data": "2026-07-15", "qtd": 10, "preco": 10.0})
        darf_jul = nc.carregar("2026-07")["resumo"]["darf"]
        self.assertTrue(0 < darf_jul < nc.DARF_MINIMO)
        self.assertAlmostEqual(nc.carregar("2026-10")["darf_anterior"], darf_jul)
        # segunda venda em julho: DARF passa de R$ 10, sai de outubro e fica em julho
        nc.registrar_venda_retroativa(self.d, "L1", {"data": "2026-07-20", "qtd": 30, "preco": 12.0})
        self.assertGreaterEqual(nc.carregar("2026-07")["resumo"]["darf"], nc.DARF_MINIMO)
        self.assertAlmostEqual(nc.carregar("2026-10")["darf_anterior"], 0.0)

    def test_lote_levado_nao_gera_novo_debito(self):
        self.d["lotes"][0]["origem"] = "L0"
        nc.salvar(self.d)
        antes = sum(i["valor"] for i in nc.lancamentos_caixa() if i["tipo"] == "Compra")
        nc.registrar_venda_retroativa(self.d, "L1", {"data": "2026-07-15", "qtd": 20, "preco": 10.0})
        depois = sum(i["valor"] for i in nc.lancamentos_caixa() if i["tipo"] == "Compra")
        self.assertAlmostEqual(antes, depois)

    def test_caixa_nao_duplica_compra(self):
        antes = sum(i["valor"] for i in nc.lancamentos_caixa() if i["tipo"] == "Compra")
        nc.registrar_venda_retroativa(self.d, "L1", {"data": "2026-07-15", "qtd": 20, "preco": 10.0})
        depois = sum(i["valor"] for i in nc.lancamentos_caixa() if i["tipo"] == "Compra")
        self.assertAlmostEqual(antes, depois)


if __name__ == "__main__":
    unittest.main()
