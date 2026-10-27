import base64
import calendar
import hashlib
import json
import queue
import re
import subprocess
import sys
import threading
import uuid
import webbrowser
from collections import Counter, defaultdict
from datetime import date, datetime, timedelta
from pathlib import Path
import tkinter as tk
from tkinter import ttk

import customtkinter as ctk

import atualizador as upd
import google_sync as gs
import nucleo as nc
import mercado as mk
import noticias as nt
from componentes import CampoData, SeletorMes
from tema import C, F, FONTE, botao, cor, estilo_botao
from nucleo import (DARF_MINIMO, LIMITE_ISENCAO, apurar, brl, carregar, fmt_data, fmt_mes, gravar_config,
                    historico_tickers, inferir_tipo, ler_config, limites_mes, listar_meses, mes_inicial, mes_vazio,
                    montar_linhas, parse_num, parse_qtd, preco_texto, proximo_mes, reconstruir, restante, salvar,
                    status_lote, vendido)
from versao import VERSAO

PAGINA_APURACAO = "Apuração / DARF"
PAGINA_RADAR = "Radar de Ações"
PAGINA_CAIXA = "Caixa"
PAGINA_NOTICIAS = "Notícias"
AUMID = "JoaoGabrielOT.CalculadoraDARF"  # identificação do app nas notificações do Windows

BASE = Path(sys.executable).parent if getattr(sys, "frozen", False) else Path(__file__).parent
DADOS = BASE / "dados"
nc.configurar(DADOS)


def recurso(nome):
    """Arquivo empacotado no .exe (PyInstaller) ou ao lado do script."""
    raiz = Path(getattr(sys, "_MEIPASS", Path(__file__).parent))
    return raiz / nome


class Janela(ctk.CTkToplevel):
    def __init__(self, master, titulo):
        super().__init__(master)
        self.master_ = master
        self.title(titulo)
        self.resizable(False, False)
        self.configure(fg_color=C["bg"])
        self.transient(master)
        self.resultado = None
        self.caixa = ctk.CTkFrame(self, fg_color=C["card"], corner_radius=14,
                                  border_width=1, border_color=C["borda"])
        self.caixa.pack(padx=14, pady=14, fill="both", expand=True)

    def mostrar(self):
        self.update_idletasks()
        m = self.master_
        x = m.winfo_rootx() + (m.winfo_width() - self.winfo_reqwidth()) // 2
        y = m.winfo_rooty() + (m.winfo_height() - self.winfo_reqheight()) // 3
        self.geometry(f"+{max(x, 0)}+{max(y, 0)}")
        self.after(80, self._focar)
        self.wait_window()

    def _focar(self):
        try:
            self.lift()
            self.grab_set()
            self.focus_force()
        except Exception:
            pass


class Mensagem(Janela):
    def __init__(self, master, titulo, texto, botoes):
        super().__init__(master, titulo)
        ctk.CTkLabel(self.caixa, text=titulo, font=F(17, "bold"), text_color=C["texto"]).pack(
            anchor="w", padx=22, pady=(20, 6))
        ctk.CTkLabel(self.caixa, text=texto, font=F(13), text_color=C["muted"], justify="left",
                     wraplength=380).pack(anchor="w", padx=22)
        barra = ctk.CTkFrame(self.caixa, fg_color="transparent")
        barra.pack(fill="x", padx=22, pady=(20, 20))
        for txt, valor, estilo in reversed(botoes):
            botao(barra, txt, lambda v=valor: self.escolher(v), estilo).pack(side="right", padx=(8, 0))
        self.bind("<Escape>", lambda e: self.destroy())
        self.bind("<Return>", lambda e: self.escolher(botoes[-1][1]))
        self.mostrar()

    def escolher(self, v):
        self.resultado = v
        self.destroy()


def confirmar(master, titulo, texto, sim="Sim", nao="Cancelar", perigo=False):
    m = Mensagem(master, titulo, texto, [(nao, False, "neutro"),
                                         (sim, True, "perigo_cheio" if perigo else "accent")])
    return bool(m.resultado)


def avisar(master, titulo, texto):
    Mensagem(master, titulo, texto, [("OK", True, "accent")])


class FormBase(Janela):
    LARGURA = 360

    def __init__(self, master, titulo, subtitulo=""):
        super().__init__(master, titulo)
        self.bts_chip = {}
        ctk.CTkLabel(self.caixa, text=titulo, font=F(18, "bold"), text_color=C["texto"]).pack(
            anchor="w", padx=24, pady=(22, 0))
        self.lb_sub = ctk.CTkLabel(self.caixa, text=subtitulo, font=F(12), text_color=C["muted"],
                                   wraplength=self.LARGURA, justify="left")
        self.lb_sub.pack(anchor="w", padx=24)

    def rotulo(self, texto):
        lb = ctk.CTkLabel(self.caixa, text=texto, font=F(12, "bold"), text_color=C["muted"])
        lb.pack(anchor="w", padx=24, pady=(14, 4))
        return lb

    def entrada(self, placeholder="", valor=""):
        w = ctk.CTkEntry(self.caixa, width=self.LARGURA, height=38, font=F(13), corner_radius=8,
                         border_color=C["borda"], fg_color=C["card2"], text_color=C["texto"],
                         placeholder_text=placeholder)
        if valor:
            w.insert(0, valor)
        w.pack(fill="x", padx=24)
        return w

    def chips(self, tickers, comando):
        if not tickers:
            return
        f = ctk.CTkFrame(self.caixa, fg_color="transparent")
        f.pack(fill="x", padx=24, pady=(8, 0))
        ctk.CTkLabel(f, text="Frequentes", font=F(11), text_color=C["muted"]).grid(
            row=0, column=0, columnspan=4, sticky="w", pady=(0, 4))
        for i, t in enumerate(tickers):
            b = botao(f, t, lambda t=t: comando(t), "chip", altura=28, fonte=12, width=82)
            b.grid(row=1 + i // 4, column=i % 4, padx=(0, 6), pady=(0, 6), sticky="w")
            self.bts_chip[t] = b

    def marcar_chip(self, ticker):
        for t, b in self.bts_chip.items():
            b.configure(**estilo_botao("chip_ativo" if t == ticker else "chip"))

    def rodape(self):
        self.lb_erro = ctk.CTkLabel(self.caixa, text="", font=F(12), text_color=C["danger"],
                                    wraplength=self.LARGURA, justify="left")
        self.lb_erro.pack(anchor="w", padx=24, pady=(10, 0))
        barra = ctk.CTkFrame(self.caixa, fg_color="transparent")
        barra.pack(fill="x", padx=24, pady=(6, 22))
        botao(barra, "Salvar", self.ok, "accent", width=110).pack(side="right")
        botao(barra, "Cancelar", self.destroy, "neutro", width=110).pack(side="right", padx=(0, 8))
        self.bind("<Return>", lambda e: self.ok())
        self.bind("<Escape>", lambda e: self.destroy())

    def erro(self, msg):
        self.lb_erro.configure(text=msg)

    def ok(self):
        raise NotImplementedError

    # --- resumo financeiro da ordem
    def montar_resumo(self):
        f = self.fr_resumo = ctk.CTkFrame(self.caixa, fg_color=C["card2"], corner_radius=10,
                                         border_width=1, border_color=C["borda"])
        f.pack(fill="x", padx=24, pady=(16, 0))
        ctk.CTkLabel(f, text="RESUMO FINANCEIRO DA ORDEM", font=F(11, "bold"), text_color=C["muted"]).pack(
            anchor="w", padx=14, pady=(10, 4))
        self.rs_linhas = {}
        for chave, titulo in (("bruto", "Valor bruto"), ("taxas", "Taxas B3 (estimadas)"), ("irrf", "IRRF retido")):
            linha = ctk.CTkFrame(f, fg_color="transparent")
            linha.pack(fill="x", padx=14)
            ctk.CTkLabel(linha, text=titulo, font=F(12), text_color=C["muted"]).pack(side="left")
            v = ctk.CTkLabel(linha, text="—", font=F(12, "bold"), text_color=C["texto"])
            v.pack(side="right")
            self.rs_linhas[chave] = (linha, v)
        self.rs_impacto = ctk.CTkLabel(f, text="", font=F(13, "bold"), text_color=C["texto"], justify="left",
                                       wraplength=self.LARGURA - 20)
        self.rs_impacto.pack(anchor="w", padx=14, pady=(8, 0))
        self.rs_liq = ctk.CTkLabel(f, text="", font=F(12, "bold"), text_color=C["texto"])
        self.rs_liq.pack(anchor="w", padx=14)
        self.rs_nota = ctk.CTkLabel(f, text="", font=F(11), text_color=C["muted"], justify="left",
                                    wraplength=self.LARGURA - 20)
        self.rs_nota.pack(anchor="w", padx=14, pady=(2, 10))

    def mostrar_resumo(self, res, nota=""):
        """res: resultado de nc.resumo_ordem ou None (campos incompletos)."""
        if res is None:
            for _, v in self.rs_linhas.values():
                v.configure(text="—")
            self.rs_impacto.configure(text="Preencha quantidade, preço e data.", text_color=C["muted"])
            self.rs_liq.configure(text="")
            self.rs_nota.configure(text=nota)
            return
        self.rs_linhas["bruto"][1].configure(text=brl(res["bruto"]))
        self.rs_linhas["taxas"][1].configure(text=brl(res["taxas"]))
        self.rs_linhas["irrf"][1].configure(text=brl(res["irrf"]) if res["irrf"] else "R$ 0,00")
        liq = res["liquido"]
        if liq < 0:
            self.rs_impacto.configure(text=f"Será debitado da conta: {brl(-liq)}", text_color=C["danger"])
        else:
            self.rs_impacto.configure(text=f"Será creditado na conta: {brl(liq)}", text_color=C["accent"])
        self.rs_liq.configure(text=f"📅 Liquidação financeira: {nc.fmt_liquidacao(res['liquidacao'])}")
        self.rs_nota.configure(text=nota)

    def valores_ordem(self):
        try:
            return parse_qtd(self.en_qtd.get()), parse_num(self.en_preco.get())
        except ValueError:
            return None


class FormCompra(FormBase):
    def __init__(self, master, sugestoes, tipos, iniciais=None, editar=None):
        ini = iniciais or {}
        self.editar = editar
        maximo = date.today()
        if editar:
            ini = {"ticker": editar["ticker"], "tipo": editar["tipo"], "qtd": str(editar["qtd"]),
                   "preco": nc.fmt_num(editar["preco"])}
            if editar["vendas"]:
                maximo = min(maximo, date.fromisoformat(min(v["data"] for v in editar["vendas"])))
            sub = f"Já vendidas: {vendido(editar)}" if editar["vendas"] else "Dados da compra"
            super().__init__(master, "Editar compra", sub)
        else:
            super().__init__(master, "Novo ativo", "Dados da compra")
        self.tipos = tipos
        self.rotulo("TICKER")
        self.en_ticker = self.entrada("Ex.: PETR4", ini.get("ticker", ""))
        self.en_ticker.bind("<KeyRelease>", lambda e: self.ticker_digitado())
        self.chips(sugestoes, self.escolher)
        self.lb_tipo = ctk.CTkLabel(self.caixa, text="", font=F(12, "bold"), text_color=C["muted"])
        self.lb_tipo.pack(anchor="w", padx=24, pady=(6, 0))
        self.mostrar_tipo(ini.get("ticker", ""))
        self.rotulo("DATA DA COMPRA")
        inicial = date.fromisoformat(editar["data_compra"]) if editar else date.today()
        self.data = CampoData(self.caixa, valor=inicial, maximo=maximo, ao_mudar=lambda d: self.atualizar_resumo())
        self.data.pack(fill="x", padx=24)
        self.rotulo("QUANTIDADE")
        self.en_qtd = self.entrada("Ex.: 100", ini.get("qtd", ""))
        self.rotulo("PREÇO UNITÁRIO (R$)")
        self.en_preco = self.entrada("Ex.: 32,50", ini.get("preco", ""))
        for en in (self.en_qtd, self.en_preco):
            en.bind("<KeyRelease>", lambda e: self.atualizar_resumo(), add="+")
        self.montar_resumo()
        self.atualizar_resumo()
        self.rodape()
        if ini.get("ticker"):
            self.marcar_chip(ini["ticker"])
        foco = self.en_qtd if ini.get("ticker") else self.en_ticker
        self.after(150, foco.focus_set)
        self.mostrar()

    def atualizar_resumo(self):
        v = self.valores_ordem()
        if not v or not self.data.valor:
            return self.mostrar_resumo(None)
        self.mostrar_resumo(nc.resumo_ordem("compra", v[0], v[1], self.data.valor),
                            "Se vender no mesmo dia (day trade), a B3 liquida só o resultado do dia.")

    def mostrar_tipo(self, ticker):
        t = (ticker or "").strip().upper()
        self.lb_tipo.configure(text=f"Tipo: {nc.tipo_por_ticker(t)} (identificado pelo ticker)" if len(t) >= 5 else "")

    def escolher(self, t):
        self.en_ticker.delete(0, "end")
        self.en_ticker.insert(0, t)
        self.mostrar_tipo(t)
        self.marcar_chip(t)
        self.en_qtd.focus_set()

    def ticker_digitado(self):
        t = self.en_ticker.get().strip().upper()
        self.marcar_chip(t)
        self.mostrar_tipo(t)

    def ok(self):
        ticker = self.en_ticker.get().strip().upper()
        if not ticker:
            return self.erro("Informe o ticker.")
        dc = self.data.valor
        if not dc:
            return self.erro("Selecione a data da compra.")
        if dc > date.today():
            return self.erro("A data da compra não pode ser futura.")
        try:
            q = parse_qtd(self.en_qtd.get())
        except ValueError:
            return self.erro("Quantidade inválida.")
        try:
            p = parse_num(self.en_preco.get())
        except ValueError:
            return self.erro("Preço inválido.")
        novo = {"ticker": ticker, "tipo": nc.tipo_por_ticker(ticker), "data_compra": dc.isoformat(), "qtd": q, "preco": p}
        if self.editar:
            msg = nc.erro_edicao_lote(self.editar, novo)
            if msg:
                return self.erro(msg)
        self.resultado = novo
        self.destroy()


class FormVenda(FormBase):
    def __init__(self, master, d, sugestoes, lote_inicial=None, ticker_inicial="", editar=None):
        """editar=(lote, venda): edita a venda; a compra fica fixa."""
        super().__init__(master, "Editar venda" if editar else "Registrar venda", f"Mês {fmt_mes(d['mes'])}")
        if editar:
            lote_inicial = nc.sem_venda(editar[0], editar[1]["id"])
            self.abertos = [lote_inicial]
            sugestoes = []
        else:
            self.abertos = [l for l in d["lotes"] if restante(l) > 0]
        self.inicio_mes, self.fim_mes = limites_mes(d["mes"])
        self.opcoes = {}
        self.lote = None
        self.ticker_atual = None
        self.editar = editar
        self.mercado = getattr(master, "mercado", None)
        self.preco_auto = ""     # último preço preenchido automaticamente
        self.pedido = None       # (ticker, data) da busca de preço em andamento

        self.rotulo("TICKER")
        self.en_ticker = self.entrada("Ex.: PETR4")
        self.en_ticker.bind("<KeyRelease>", lambda e: self.selecionar_ticker(self.en_ticker.get(), digitado=True))
        self.chips(sugestoes, self.selecionar_ticker)
        self.rotulo("COMPRA")
        self.om_lote = ctk.CTkOptionMenu(self.caixa, values=["-"], command=self.selecionar_lote,
                                         width=self.LARGURA, height=38, font=F(13), dropdown_font=F(13),
                                         corner_radius=8, fg_color=C["card2"], button_color=C["neutro_h"],
                                         button_hover_color=C["borda"], text_color=C["texto"],
                                         text_color_disabled=C["muted"])
        self.om_lote.pack(fill="x", padx=24)
        self.lb_info = ctk.CTkLabel(self.caixa, text="", font=F(12), text_color=C["muted"], justify="left",
                                    wraplength=self.LARGURA)
        self.lb_info.pack(anchor="w", padx=24, pady=(6, 0))
        self.rotulo("DATA DA VENDA")
        self.data = CampoData(self.caixa, minimo=self.inicio_mes, maximo=min(self.fim_mes, date.today()),
                              ao_mudar=lambda d: (self.sugerir_preco(), self.atualizar_resumo()))
        self.data.pack(fill="x", padx=24)
        self.lb_qtd = self.rotulo("QUANTIDADE")
        self.en_qtd = self.entrada()
        self.rotulo("PREÇO UNITÁRIO (R$)")
        self.en_preco = self.entrada("Ex.: 35,10")
        self.lb_preco = ctk.CTkLabel(self.caixa, text="", font=F(11), text_color=C["muted"])
        self.lb_preco.pack(anchor="w", padx=24, pady=(4, 0))
        for en in (self.en_qtd, self.en_preco):
            en.bind("<KeyRelease>", lambda e: self.atualizar_resumo(), add="+")
        self.montar_resumo()
        self.rodape()

        t = lote_inicial["ticker"] if lote_inicial else ticker_inicial
        self.selecionar_ticker(t or "", lote_inicial=lote_inicial)
        if editar:
            v = editar[1]
            self.en_ticker.configure(state="disabled")
            self.om_lote.configure(state="disabled")
            self.data.set(date.fromisoformat(v["data"]))
            self.en_qtd.delete(0, "end")
            self.en_qtd.insert(0, str(v["qtd"]))
            self.en_preco.insert(0, nc.fmt_num(v["preco"]))
        self.atualizar_resumo()
        self.after(150, (self.en_preco if t else self.en_ticker).focus_set)
        self.mostrar()

    def selecionar_ticker(self, t, digitado=False, lote_inicial=None):
        t = t.strip().upper()
        if not digitado:
            self.en_ticker.delete(0, "end")
            if t:
                self.en_ticker.insert(0, t)
        if t == self.ticker_atual and lote_inicial is None:
            return
        self.ticker_atual = t
        self.marcar_chip(t)
        self.opcoes = {}
        for l in (l for l in self.abertos if l["ticker"] == t):
            rot = base = f"{fmt_data(l['data_compra'])}  ·  {brl(l['preco'])}  ·  {restante(l)} disp."
            n = 2
            while rot in self.opcoes:
                rot = f"{base} ({n})"
                n += 1
            self.opcoes[rot] = l
        if self.opcoes:
            self.om_lote.configure(values=list(self.opcoes), state="normal")
            alvo = next((r for r, l in self.opcoes.items() if lote_inicial and l["id"] == lote_inicial["id"]),
                        next(iter(self.opcoes)))
            self.om_lote.set(alvo)
            self.selecionar_lote(alvo)
        else:
            msg = "Nenhuma compra em aberto desse ticker" if t else "Escolha um ticker"
            self.om_lote.configure(values=[msg], state="disabled")
            self.om_lote.set(msg)
            self.lote = None
            self.lb_info.configure(text="")
            self.lb_qtd.configure(text="QUANTIDADE")
            self.atualizar_resumo()

    def selecionar_lote(self, rotulo):
        l = self.opcoes.get(rotulo)
        if not l:
            return
        self.lote = l
        disp = restante(l)
        minimo = max(date.fromisoformat(l["data_compra"]), self.inicio_mes)
        maximo = min(self.fim_mes, date.today())
        info = f"{l['tipo']}  ·  Custo {brl(l['preco'])}  ·  Disponível: {disp}"
        if minimo > maximo:
            info += "\nNão há data válida para vender essa compra neste mês."
        self.lb_info.configure(text=info)
        self.lb_qtd.configure(text=f"QUANTIDADE (MÁX. {disp})")
        self.en_qtd.delete(0, "end")
        self.en_qtd.insert(0, str(disp))
        self.data.set_limites(minimo, maximo)
        hoje = date.today()
        if not self.data.valor and minimo <= hoje <= maximo:
            self.data.set(hoje)
        self.sugerir_preco()
        self.atualizar_resumo()

    def atualizar_resumo(self):
        if not hasattr(self, "rs_impacto"):
            return
        v = self.valores_ordem()
        if not v or not self.data.valor or not self.lote:
            return self.mostrar_resumo(None)
        dt = self.data.valor.isoformat() == self.lote["data_compra"]
        res = nc.resumo_ordem("venda", v[0], v[1], self.data.valor, preco_compra=self.lote["preco"], day_trade=dt)
        nota = ("Day trade (compra e venda no mesmo dia): a B3 liquida só o resultado, já com o IRRF de 1% "
                "sobre o lucro." if dt else "Swing trade: crédito do valor da venda menos as taxas da B3.")
        self.mostrar_resumo(res, nota)

    def preco_manual(self):
        """True se o usuário digitou um preço diferente do sugerido."""
        return self.en_preco.get().strip() not in ("", self.preco_auto)

    def sugerir_preco(self):
        """Preenche o preço com a cotação atual (venda hoje) ou o fechamento da data escolhida."""
        if self.editar or not self.lote or not self.data.valor or not self.mercado or self.preco_manual():
            return
        pedido = (self.lote["ticker"], self.data.valor)
        if pedido == self.pedido:
            return
        self.pedido = pedido
        self.lb_preco.configure(text="Buscando cotação…")
        res = {}

        def trabalho():
            try:
                res["ok"] = self.mercado.preco_venda(*pedido)
            except Exception as e:
                res["erro"] = e

        threading.Thread(target=trabalho, daemon=True).start()

        def esperar():
            try:
                if not self.winfo_exists():
                    return
            except Exception:
                return
            if not res:
                self.after(150, esperar)
                return
            if self.pedido != pedido or self.preco_manual():
                return
            if "ok" in res:
                valor, origem = res["ok"]
                self.preco_auto = preco_texto(valor)
                self.en_preco.delete(0, "end")
                self.en_preco.insert(0, self.preco_auto)
                self.lb_preco.configure(text=f"{origem} · pode alterar")
                self.atualizar_resumo()
            else:
                self.pedido = None
                self.lb_preco.configure(text="Não foi possível buscar a cotação. Informe o preço.")

        self.after(150, esperar)

    def ok(self):
        if not self.lote:
            return self.erro("Escolha o ticker e a compra que foi vendida.")
        dv = self.data.valor
        if not dv:
            return self.erro("Selecione a data da venda.")
        try:
            q = parse_qtd(self.en_qtd.get())
        except ValueError:
            return self.erro("Quantidade inválida.")
        disp = restante(self.lote)
        if q > disp:
            return self.erro(f"Quantidade maior que a disponível ({disp}).")
        try:
            p = parse_num(self.en_preco.get())
        except ValueError:
            return self.erro("Preço inválido.")
        self.resultado = {"lote_id": self.lote["id"], "data": dv.isoformat(), "qtd": q, "preco": p}
        self.destroy()


class FormSaldo(FormBase):
    """Define o saldo em conta de hoje ou registra um aporte/retirada sobre o saldo disponível."""
    MODOS = ["Definir saldo", "Aporte", "Retirada"]

    def __init__(self, master, disponivel, definido):
        sub = f"Saldo disponível hoje: {brl(disponivel)}" if definido else "Informe o saldo livre na conta da corretora hoje."
        super().__init__(master, "Saldo em conta", sub)
        self.rotulo("OPERAÇÃO")
        self.seg = ctk.CTkSegmentedButton(self.caixa, values=self.MODOS if definido else self.MODOS[:1], height=36,
                                          font=F(13), selected_color=C["accent"], selected_hover_color=C["accent_h"],
                                          command=lambda v: self.trocar_modo())
        self.seg.set(self.MODOS[0])
        self.seg.pack(fill="x", padx=24)
        self.lb_valor = self.rotulo("SALDO DISPONÍVEL HOJE (R$)")
        self.en_valor = self.entrada("Ex.: 10.000,00", nc.preco_texto(disponivel) if definido else "")
        self.lb_ajuda = ctk.CTkLabel(self.caixa, text="", font=F(11), text_color=C["muted"], justify="left",
                                     wraplength=self.LARGURA)
        self.lb_ajuda.pack(anchor="w", padx=24, pady=(6, 0))
        self.trocar_modo()
        self.rodape()
        self.after(150, self.en_valor.focus_set)
        self.mostrar()

    def trocar_modo(self):
        modo = self.seg.get()
        if modo == "Definir saldo":
            self.lb_valor.configure(text="SALDO DISPONÍVEL HOJE (R$)")
            self.lb_ajuda.configure(text="Use o saldo livre que a corretora mostra hoje, já com as liquidações de hoje.")
        else:
            self.lb_valor.configure(text=f"VALOR DO {modo.upper()} (R$)")
            self.lb_ajuda.configure(text="Soma ao saldo disponível." if modo == "Aporte"
                                    else "Desconta do saldo disponível.")
            self.en_valor.delete(0, "end")

    def ok(self):
        try:
            valor = nc.parse_valor(self.en_valor.get())
        except ValueError:
            return self.erro("Valor inválido.")
        modo = self.seg.get()
        if modo != "Definir saldo" and valor <= 0:
            return self.erro("Informe um valor maior que zero.")
        self.resultado = (modo, valor)
        self.destroy()


class CardKPI(ctk.CTkFrame):
    def __init__(self, pai, titulo, destaque=False):
        super().__init__(pai, fg_color=C["card"], corner_radius=14,
                         border_width=2 if destaque else 1,
                         border_color=C["accent"] if destaque else C["borda"])
        ctk.CTkLabel(self, text=titulo.upper(), font=F(11, "bold"), text_color=C["muted"]).pack(
            anchor="w", padx=20, pady=(16, 0))
        self.valor = ctk.CTkLabel(self, text="R$ 0,00", font=F(26, "bold"), text_color=C["texto"])
        self.valor.pack(anchor="w", padx=20)
        self.sub = ctk.CTkLabel(self, text="", font=F(12), text_color=C["muted"])
        self.sub.pack(anchor="w", padx=20, pady=(0, 16))

    def set(self, valor, sub="", cor_valor=None):
        self.valor.configure(text=valor, text_color=cor_valor or C["texto"])
        self.sub.configure(text=sub)


class Tabela(ctk.CTkFrame):
    """linhas: (iid, valores, tags, chaves) — chaves é um dict coluna -> valor usado na ordenação/filtro."""

    def __init__(self, pai, colunas, vazio, ordenaveis=()):
        super().__init__(pai, fg_color="transparent")
        self.grid_columnconfigure(0, weight=1)
        self.grid_rowconfigure(0, weight=1)
        self.titulos = {c[0]: c[1] for c in colunas}
        self.ordenaveis = set(ordenaveis)
        self.ordem = None
        self.filtro = None
        self.linhas = []
        self.visiveis = 0
        self.vazio = vazio
        self.ancoras = {c[0]: c[3] for c in colunas}
        self.cores_cel = {}  # iid -> {coluna: tag de cor}; o Treeview não colore células isoladas
        self.rotulos = []
        self.redesenho = None
        self.tv = ttk.Treeview(self, columns=[c[0] for c in colunas], show="headings",
                               selectmode="browse", style="D.Treeview")
        for chave, titulo, larg, ancora in colunas:
            kw = {"command": lambda c=chave: self.ordenar(c)} if chave in self.ordenaveis else {}
            self.tv.heading(chave, text=titulo, anchor=ancora, **kw)
            self.tv.column(chave, width=larg, minwidth=60, anchor=ancora)
        sb = ctk.CTkScrollbar(self, command=self.tv.yview)
        self.tv.configure(yscrollcommand=lambda *a: (sb.set(*a), self._agendar_cores()))
        for ev in ("<Configure>", "<<TreeviewSelect>>", "<ButtonRelease-1>", "<B1-Motion>"):
            self.tv.bind(ev, lambda e: self._agendar_cores(), add="+")
        self.tv.grid(row=0, column=0, sticky="nsew")
        sb.grid(row=0, column=1, sticky="ns")
        self.lb_vazio = ctk.CTkLabel(self, text=vazio, font=F(13), text_color=C["muted"])

    def ordenar(self, coluna):
        if self.ordem and self.ordem[0] == coluna:
            self.ordem = (coluna, not self.ordem[1])
        else:
            self.ordem = (coluna, False)
        self._render()

    def set_filtro(self, funcao):
        self.filtro = funcao
        self._render()

    def preencher(self, linhas):
        self.linhas = linhas
        self._render()

    def _render(self):
        sel = self.selecionado()
        linhas = [l for l in self.linhas if not self.filtro or self.filtro(l[3])]
        if self.ordem:
            col, desc = self.ordem

            def chave(l):
                v = l[3].get(col)
                return v.casefold() if isinstance(v, str) else v

            linhas.sort(key=chave, reverse=desc)
        for c, t in self.titulos.items():
            if self.ordem and self.ordem[0] == c:
                t += "  ▼" if self.ordem[1] else "  ▲"
            elif c in self.ordenaveis:
                t += "  ↕"
            self.tv.heading(c, text=t)
        self.tv.delete(*self.tv.get_children())
        self.cores_cel = {}
        for i, (iid, valores, tags, chaves) in enumerate(linhas):
            self.tv.insert("", "end", iid=iid, values=valores, tags=("impar" if i % 2 else "par", *tags))
            if chaves.get("_cores"):
                self.cores_cel[iid] = chaves["_cores"]
        self._agendar_cores()
        if sel and self.tv.exists(sel):
            self.tv.selection_set(sel)
        self.visiveis = len(linhas)
        if linhas:
            self.lb_vazio.place_forget()
        else:
            self.lb_vazio.configure(text=self.vazio if not self.linhas else "Nenhum item para esse filtro.")
            self.lb_vazio.place(relx=0.5, rely=0.55, anchor="center")

    def selecionado(self):
        s = self.tv.selection()
        return s[0] if s else None

    def _agendar_cores(self):
        if self.redesenho is None:
            self.redesenho = self.after_idle(self._desenhar_cores)

    def _rotulo(self, n):
        while len(self.rotulos) <= n:
            lb = tk.Label(self.tv, bd=0, highlightthickness=0, padx=4, font=(FONTE, 10))
            lb.bind("<Button-1>", lambda e, lb=lb: self._clique(lb))
            lb.bind("<Double-1>", lambda e, lb=lb: (self._clique(lb), self.tv.event_generate("<<Duplo>>")))
            lb.bind("<MouseWheel>", lambda e: self.tv.yview_scroll(int(-e.delta / 120), "units"))
            self.rotulos.append(lb)
        return self.rotulos[n]

    def _clique(self, lb):
        iid = getattr(lb, "iid", None)
        if iid and self.tv.exists(iid):
            self.tv.selection_set(iid)
            self.tv.focus(iid)
            self.tv.focus_set()

    def _desenhar_cores(self):
        self.redesenho = None
        n = 0
        selecionados = set(self.tv.selection())
        for i, iid in enumerate(self.tv.get_children()):
            for col, tag in self.cores_cel.get(iid, {}).items():
                caixa = self.tv.bbox(iid, col)
                if not caixa:
                    continue
                x, y, w, h = caixa
                if iid in selecionados:
                    fundo = cor("selecao")
                else:
                    fundo = cor("zebra" if i % 2 else "card")
                lb = self._rotulo(n)
                lb.iid = iid
                anc = self.ancoras.get(col, "w")
                lb.configure(text=self.tv.set(iid, col), bg=fundo, fg=cor(tag), anchor=anc)
                lb.place(x=x, y=y, width=w, height=h)
                n += 1
        for lb in self.rotulos[n:]:
            lb.place_forget()

    def aplicar_cores(self):
        self._agendar_cores()
        self.tv.tag_configure("par", background=cor("card"))
        self.tv.tag_configure("impar", background=cor("zebra"))
        self.tv.tag_configure("neg", foreground=cor("danger"))
        self.tv.tag_configure("pos", foreground=cor("accent"))
        self.tv.tag_configure("muted", foreground=cor("muted"))


def pilula(pai, texto, fundo, cor_texto, fonte=11):
    return ctk.CTkLabel(pai, text=f"  {texto}  ", font=F(fonte, "bold"), fg_color=fundo, text_color=cor_texto,
                        corner_radius=10, height=24)


COLUNAS_RADAR = [  # título, largura mínima, peso, alinhamento
    ("ATIVO", 230, 3, "w"), ("COTAÇÃO", 100, 1, "e"), ("MÉDIA 6 MESES", 110, 1, "e"), ("ATR (14)", 90, 1, "e"),
    ("ATR%", 70, 1, "e"), ("RISCO", 180, 1, "center"), ("", 240, 0, "e")]
ALINHAR = {"w": "w", "e": "e", "center": ""}


def colunas_radar(frame):
    for i, (_, minimo, peso, _) in enumerate(COLUNAS_RADAR):
        frame.grid_columnconfigure(i, minsize=minimo, weight=peso)


def cabecalho_radar(pai):
    f = ctk.CTkFrame(pai, fg_color=C["card2"], corner_radius=8)
    colunas_radar(f)
    for i, (titulo, _, _, alinhar) in enumerate(COLUNAS_RADAR):
        ctk.CTkLabel(f, text=titulo, font=F(11, "bold"), text_color=C["muted"]).grid(
            row=0, column=i, sticky=ALINHAR[alinhar], padx=12, pady=8)
    return f


class LinhaRadar(ctk.CTkFrame):
    def __init__(self, pai, ticker, ao_comprar, ao_vender, ao_remover, ao_arrastar=None, ao_importar=None):
        super().__init__(pai, fg_color=C["card"], corner_radius=8)
        self.ticker = ticker
        self.amigo = ao_importar is not None
        colunas_radar(self)
        ativo = ctk.CTkFrame(self, fg_color="transparent")
        ativo.grid(row=0, column=0, sticky="w", padx=(4 if ao_arrastar else 12, 12), pady=8)
        if ao_arrastar:  # alça para arrastar e mudar a posição do ativo no radar
            alca = ctk.CTkLabel(ativo, text="⠿", width=22, font=F(18, "bold"), text_color=C["muted"], cursor="fleur")
            alca.pack(side="left", padx=(0, 6))
            for evento, fase in (("<ButtonPress-1>", "ini"), ("<B1-Motion>", "mov"), ("<ButtonRelease-1>", "fim")):
                alca.bind(evento, lambda e, f=fase: ao_arrastar(f, ticker, e))
        self.lb_logo = selo_logo(ativo, ticker)
        self.lb_logo.pack(side="left", padx=(0, 10))
        txt = ctk.CTkFrame(ativo, fg_color="transparent")
        txt.pack(side="left")
        ctk.CTkLabel(txt, text=ticker, font=F(14, "bold"), text_color=C["texto"], anchor="w").pack(anchor="w")
        self.lb_nome = ctk.CTkLabel(txt, text="", font=F(11), text_color=C["muted"], anchor="w", justify="left",
                                    wraplength=180)
        self.lb_nome.pack(anchor="w")
        self.vals = {}
        for i, k in enumerate(("preco", "media6m", "atr", "atr_pct"), start=1):
            v = ctk.CTkLabel(self, text="—", font=F(14 if k == "preco" else 13, "bold"), text_color=C["texto"])
            v.grid(row=0, column=i, sticky="e", padx=12)
            self.vals[k] = v
        self.badge = ctk.CTkLabel(self, text="", font=F(11, "bold"), corner_radius=10, height=24,
                                  fg_color="transparent")
        self.badge.grid(row=0, column=5, padx=12)
        acoes = ctk.CTkFrame(self, fg_color="transparent")
        acoes.grid(row=0, column=6, sticky="e", padx=12)
        self.bt_vender = self.bt_importar = None
        if self.amigo:
            self.bt_importar = botao(acoes, "+  Meu radar", lambda: ao_importar(ticker), "accent", altura=30,
                                     fonte=12, width=234)
            self.bt_importar.pack(side="left")
            return
        botao(acoes, "Comprar", lambda: ao_comprar(ticker), "accent", altura=30, fonte=12, width=74).pack(side="left")
        self.bt_vender = botao(acoes, "Vender", lambda: ao_vender(ticker), "neutro", altura=30, fonte=12, width=74)
        self.bt_vender.pack(side="left", padx=6)
        botao(acoes, "Remover", lambda: ao_remover(ticker), "perigo", altura=30, fonte=12, width=74).pack(side="left")

    def limpar(self):
        for v in self.vals.values():
            v.configure(text="—")
        self.badge.configure(text="", fg_color="transparent")

    def set(self, dados, pode_vender, nome="", ja_tenho=False):
        if self.bt_vender is not None:
            self.bt_vender.configure(state="normal" if pode_vender else "disabled")
        if self.bt_importar is not None:
            self.bt_importar.configure(text="✓  No meu radar" if ja_tenho else "+  Meu radar",
                                       state="disabled" if ja_tenho else "normal")
        if dados is None:
            self.lb_nome.configure(text=nome or "Carregando…", text_color=C["muted"])
            self.limpar()
            return
        if dados.get("erro"):
            self.lb_nome.configure(text=dados["erro"], text_color=C["danger"])
            self.limpar()
            return
        self.lb_nome.configure(text=dados.get("nome") or nome or "", text_color=C["muted"])
        self.vals["preco"].configure(text=brl(dados["preco"]))
        self.vals["media6m"].configure(text=brl(dados["media6m"]))
        self.vals["atr"].configure(text=brl(dados["atr"]) if dados.get("atr") else "—")
        pct = dados.get("atr_pct")
        self.vals["atr_pct"].configure(text=f"{pct:.2f}%".replace(".", ",") if pct is not None else "—")
        if dados.get("risco"):
            rotulo, fundo, txt = dados["risco"]
            self.badge.configure(text=f"  {rotulo}  ", fg_color=fundo, text_color=txt)
        else:
            self.badge.configure(text="", fg_color="transparent")


TAM_LOGO = 36


def selo_logo(pai, ticker, tam=TAM_LOGO):
    """Quadrado com as iniciais do ativo; recebe a logo quando ela chega (ver App.imagem)."""
    return ctk.CTkLabel(pai, text=nt.iniciais(ticker), width=tam, height=tam, corner_radius=8, fg_color=C["neutro"],
                        text_color=C["muted"], font=F(10, "bold"))


def por_logo(rotulo, img):
    try:
        if rotulo.winfo_exists():
            rotulo.configure(image=img, text="", fg_color="transparent")
    except Exception:
        pass


def ligar_clique(w, acao):
    """Clique em qualquer parte do cartão (inclusive nos rótulos internos) executa a ação."""
    try:
        w.bind("<Button-1>", lambda e: acao(), add="+")
        w.configure(cursor="hand2")
    except Exception:
        pass
    for filho in w.winfo_children():
        ligar_clique(filho, acao)


def cortar(texto, n):
    texto = (texto or "").strip()
    if len(texto) <= n:
        return texto
    return texto[:n].rsplit(" ", 1)[0].rstrip(",.;:–-") + "…"


def linhas(texto, largura, px_letra):
    """Estimativa de quantas linhas o texto ocupa (para equilibrar as colunas do mural)."""
    por_linha = max(10, int(largura / px_letra))
    return max(1, -(-len(texto or "") // por_linha)) if texto else 0


ESTILOS_NOTICIA = {  # proporção da imagem (altura/largura), fonte do título, limite do resumo
    "destaque": (0.0, 22, 420),
    "grande": (0.6, 17, 260),
    "medio": (0.45, 15, 170),
    "texto": (0.0, 16, 320),
}


def estilo_noticia(item, det, indice):
    if not (det or {}).get("img"):
        return "texto"
    return "grande" if item["temas"] or indice < 2 else "medio"


def altura_noticia(item, det, estilo, largura):
    prop, fonte, limite = ESTILOS_NOTICIA[estilo]
    resumo = cortar((det or {}).get("resumo", ""), limite)
    interna = largura - 36
    return (largura * prop + 16 + linhas(item["titulo"], interna, fonte * 0.55) * fonte * 1.45
            + linhas(resumo, interna, 6.6) * 18 + 96)


class CardNoticia(ctk.CTkFrame):
    """Mini página da matéria original: imagem, fonte, título, resumo, ativos e temas."""

    def __init__(self, pai, app, item, det, nova, largura, estilo):
        super().__init__(pai, fg_color=C["card2"], corner_radius=16, border_width=1, border_color=C["borda"])
        det = det or {}
        self.link = det.get("url") or item["link"]
        prop, fonte, limite = ESTILOS_NOTICIA[estilo]
        if estilo == "destaque":
            larg_img = int(largura * 0.48) if det.get("img") else 0
            larg_txt = largura - larg_img - 56
            self.grid_columnconfigure(1, weight=1)
            if larg_img:
                alt = max(260, min(360, int(larg_img * 0.56)))
                self.foto(app, det["img"], larg_img, alt).grid(row=0, column=0, padx=(10, 0), pady=10, sticky="nw")
            corpo = ctk.CTkFrame(self, fg_color="transparent")
            corpo.grid(row=0, column=1, sticky="nsew", padx=24, pady=22)
            self.conteudo(corpo, app, item, det, nova, larg_txt, fonte, limite, destaque=True)
        else:
            larg_txt = largura - 36
            if prop:
                self.foto(app, det["img"], largura - 16, int((largura - 16) * prop)).pack(padx=8, pady=(8, 0))
            corpo = ctk.CTkFrame(self, fg_color="transparent")
            corpo.pack(fill="x", padx=18, pady=(14, 16))
            self.conteudo(corpo, app, item, det, nova, larg_txt, fonte, limite)
        ligar_clique(self, lambda: webbrowser.open(self.link))
        self.ligar_realce(self)

    def foto(self, app, url, larg, alt):
        rot = ctk.CTkLabel(self, text="", width=larg, height=alt, fg_color=C["neutro"], corner_radius=12)
        app.imagem_noticia(url, larg, alt, lambda img: por_logo(rot, img))
        return rot

    def conteudo(self, corpo, app, item, det, nova, larg, fonte, limite, destaque=False):
        topo = ctk.CTkFrame(corpo, fg_color="transparent")
        topo.pack(fill="x")
        fav = ctk.CTkLabel(topo, text="", width=16, height=16)
        fav.pack(side="left", padx=(0, 6))
        app.imagem("f:" + nt.dominio(item.get("fonte_url", "")), lambda: nt.favicon_png(item), 16,
                   lambda img: por_logo(fav, img))
        ctk.CTkLabel(topo, text=item["fonte"] or nt.dominio(self.link), font=F(12, "bold"),
                     text_color=C["texto"]).pack(side="left")
        ctk.CTkLabel(topo, text=f"  ·  {nt.tempo_relativo(item['data'])}", font=F(12),
                     text_color=C["muted"]).pack(side="left")
        if nova:
            pilula(topo, "Nova", C["accent"], "#ffffff", 10).pack(side="right")
        ctk.CTkLabel(corpo, text=item["titulo"], font=F(fonte, "bold"), text_color=C["texto"], anchor="w",
                     justify="left", wraplength=larg).pack(fill="x", pady=(10 if destaque else 8, 0))
        resumo = cortar(det.get("resumo", ""), limite)
        if resumo and nt.chave_titulo(resumo) != nt.chave_titulo(item["titulo"]):
            ctk.CTkLabel(corpo, text=resumo, font=F(13 if destaque else 12), text_color=C["muted"], anchor="w",
                         justify="left", wraplength=larg).pack(fill="x", pady=(8, 0))
        rodape = ctk.CTkFrame(corpo, fg_color="transparent")
        rodape.pack(fill="x", pady=(14 if destaque else 12, 0))
        for t in item["tickers"][:4]:
            chip = ctk.CTkFrame(rodape, fg_color=C["neutro"], corner_radius=12)
            chip.pack(side="left", padx=(0, 6))
            logo = selo_logo(chip, t, 20)
            logo.configure(font=F(7, "bold"), corner_radius=6)
            logo.pack(side="left", padx=(3, 4), pady=3)
            app.imagem("t:" + t, lambda t=t: nt.logo_png(t), 20, lambda img, l=logo: por_logo(l, img))
            ctk.CTkLabel(chip, text=t, font=F(11, "bold"), text_color=C["texto"]).pack(side="left", padx=(0, 9))
        for t in item["temas"][:2]:
            pilula(rodape, t, C["accent_bg"], C["accent"], 10).pack(side="left", padx=(0, 6))

    def ligar_realce(self, w):
        """Borda verde enquanto o mouse está sobre o cartão (efeito de cartão flutuante)."""
        try:
            w.bind("<Enter>", lambda e: self.configure(border_color=C["accent"]), add="+")
            w.bind("<Leave>", lambda e: self.after(30, self.conferir_saida), add="+")
        except Exception:
            pass
        for f in w.winfo_children():
            self.ligar_realce(f)

    def conferir_saida(self):
        try:
            x, y = self.winfo_pointerxy()
            dentro = self.winfo_containing(x, y)
            while dentro is not None and dentro is not self:
                dentro = dentro.master
            if dentro is None:
                self.configure(border_color=C["borda"])
        except Exception:
            pass


def registrar_notificacoes(icone):
    """Registra o nome e o ícone do app para as notificações do Windows (apenas no usuário atual)."""
    if sys.platform != "win32":
        return
    try:
        import winreg
        with winreg.CreateKey(winreg.HKEY_CURRENT_USER, rf"Software\Classes\AppUserModelId\{AUMID}") as k:
            winreg.SetValueEx(k, "DisplayName", 0, winreg.REG_SZ, "Calculadora DARF")
            if icone:
                winreg.SetValueEx(k, "IconUri", 0, winreg.REG_SZ, str(icone))
    except Exception:
        pass


def xml_attr(v):
    return (v.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace('"', "&quot;")
            .replace("'", "&apos;"))


def notificar_windows(titulo, corpo, link=""):
    """Notificação nativa do Windows 10/11; clicar abre o link da notícia no navegador."""
    if sys.platform != "win32":
        return
    abrir = f' activationType="protocol" launch="{xml_attr(link)}"' if link else ""
    xml = (f'<toast{abrir}><visual><binding template="ToastGeneric"><text>{xml_attr(titulo)}</text>'
           f'<text>{xml_attr(corpo)}</text></binding></visual></toast>')
    script = (
        "[void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, "
        "ContentType = WindowsRuntime];"
        "[void][Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime];"
        "$x = New-Object Windows.Data.Xml.Dom.XmlDocument;"
        f"$x.LoadXml('{xml.replace(chr(39), chr(39) * 2)}');"
        f"[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('{AUMID}')"
        ".Show([Windows.UI.Notifications.ToastNotification]::new($x))")
    try:
        subprocess.Popen(["powershell", "-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden",
                          "-EncodedCommand", base64.b64encode(script.encode("utf-16-le")).decode()],
                         creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception:
        pass


def erro_mercado(e):
    nome = type(e).__name__
    if isinstance(e, ImportError):
        return "Biblioteca yfinance não instalada."
    if isinstance(e, mk.SemDados):
        return str(e)
    if "RateLimit" in nome or "Too Many" in str(e):
        return "Limite de consultas do Yahoo atingido. Tente em alguns minutos."
    if "Connection" in nome or "Timeout" in nome or "resolve" in str(e).lower():
        return "Sem conexão com a internet."
    return f"Erro ao consultar: {str(e)[:120]}"


# ---------------------------------------------------------------- app

class App(ctk.CTk):
    def __init__(self):
        self.cfg = ler_config()
        if nc.corrigir_tipos():  # registros antigos com Ação/BDR errado
            self.cfg["pendente"] = True
            gravar_config(self.cfg)
        ctk.set_appearance_mode(self.cfg.get("tema", "Dark"))
        ctk.set_default_color_theme("green")
        super().__init__()
        self.title(f"Calculadora DARF {VERSAO}")
        self.geometry("1360x860")
        self.minsize(1150, 720)
        self.configure(fg_color=C["bg"])
        icone = recurso("assets/icone.ico")
        if sys.platform == "win32" and icone.exists():
            # o CustomTkinter troca o ícone ~200 ms após abrir; reaplica o nosso depois disso
            self.iconbitmap(str(icone))
            self.after(300, lambda: self.iconbitmap(str(icone)))
        if sys.platform == "win32":
            self.after(0, lambda: self.state("zoomed"))

        self.cfg.setdefault("amigos", [])
        self.cfg.setdefault("planilhas", {})
        self.cfg.setdefault("pendente", False)
        self.cfg.setdefault("radar", [])
        self.mes = mes_inicial()
        self.d = carregar(self.mes)

        self.g = gs.Google(DADOS, BASE)
        self.fila = queue.Queue()
        self.visao = None
        self.dados_amigo = {}
        self.amigo_radar, self.amigo_caixa = [], None
        self.lista_seletores = []
        self.radar_modo = None
        self.arraste = None
        self.sync_rodando = False
        self.resync = False
        self.sync_job = None
        self.carregando_token = False
        self.ultima_sync = None
        self.ultima_puxada = datetime.now()
        self.ultimo_erro = ""
        self.mercado = mk.Mercado()
        self.cotacoes = mk.Cotacoes(self.mercado)
        self.radar_dados = {}
        self.radar_cards = {}
        self.radar_rodando = False
        self.radar_espera = set()
        self.imagens = {}       # "t:TICKER" / "f:dominio" -> PhotoImage (None = sem imagem)
        self.esperando = {}
        self.noticias_rodando = False
        self.noticias_filtro = {"tema": "Todas", "ticker": "Todos os ativos"}
        self.det_noticias = nt.ler_detalhes()
        self.detalhando = False
        self.fotos = {}
        self.mural_largura = 0
        self.redim_job = None
        self.cfg.setdefault("noticias_notificar", True)
        self.pagina = "apuracao"

        self.grid_columnconfigure(0, weight=1)
        self.grid_rowconfigure(1, weight=1)
        self.pg_apuracao = ctk.CTkFrame(self, fg_color="transparent")
        self.pg_apuracao.grid(row=1, column=0, sticky="nsew")
        self.pg_apuracao.grid_columnconfigure(0, weight=1)
        self.pg_apuracao.grid_rowconfigure(2, weight=1)
        self.montar_cabecalho()
        self.montar_kpis()
        self.montar_corpo()
        self.montar_radar()
        self.montar_caixa()
        self.montar_noticias()
        self.estilizar_tabelas()
        self.atualizar()
        self.atualizar_caixa()
        self.atualizar_conta()
        self.status_sync("off")

        self.after(100, self.processar_fila)
        self.after(60000, self.tick_caixa)
        self.after(60000, self.tick_sync)
        self.after(60000, self.tick_radar)
        self.after(8000, self.tick_noticias)
        self.after(1500, self.preparar_notificacoes)
        if upd.pode_atualizar():
            upd.limpar_sobras()
            self.after(3000, self.verificar_atualizacao)
        if self.g.tem_token():
            self.conectar_token()

    # --- layout
    def montar_cabecalho(self):
        h = ctk.CTkFrame(self, fg_color="transparent")
        h.grid(row=0, column=0, sticky="ew", padx=24, pady=(20, 12))
        h.grid_columnconfigure(1, weight=1)

        tit = ctk.CTkFrame(h, fg_color="transparent")
        tit.grid(row=0, column=0, sticky="w")
        ctk.CTkLabel(tit, text="Calculadora DARF", font=F(24, "bold"), text_color=C["texto"]).pack(anchor="w")
        self.lb_sub = ctk.CTkLabel(tit, text="", font=F(13), text_color=C["muted"])
        self.lb_sub.pack(anchor="w")

        self.nav = ctk.CTkSegmentedButton(h, values=[PAGINA_APURACAO, PAGINA_CAIXA, PAGINA_RADAR, PAGINA_NOTICIAS],
                                          command=self.trocar_pagina,
                                          height=38, font=F(13, "bold"), corner_radius=10,
                                          fg_color=C["neutro"], selected_color=C["accent"],
                                          selected_hover_color=C["accent_h"], unselected_color=C["neutro"],
                                          unselected_hover_color=C["neutro_h"], text_color=C["texto"])
        self.nav.set(PAGINA_APURACAO)
        self.nav.grid(row=0, column=1)

        conta = ctk.CTkFrame(h, fg_color="transparent")
        conta.grid(row=0, column=2, sticky="e")
        self.bt_saldo = botao(conta, "Saldo: —", lambda: self.trocar_pagina(PAGINA_CAIXA), "neutro", width=170)
        self.bt_saldo.pack(side="left", padx=(0, 14))
        self.lb_sync = ctk.CTkLabel(conta, text="", font=F(12, "bold"), text_color=C["muted"])
        self.lb_sync.pack(side="left", padx=(0, 14))
        self.bt_amigos = botao(conta, "Amigos", self.abrir_amigos, "neutro", width=100)
        self.bt_amigos.pack(side="left", padx=(0, 8))
        self.bt_conta = botao(conta, "Conectar Google", self.clicar_conta, "neutro", width=180)
        self.bt_conta.pack(side="left", padx=(0, 18))
        self.sw_tema = ctk.CTkSwitch(conta, text="Modo escuro", font=F(12), text_color=C["muted"],
                                     command=self.trocar_tema, progress_color=C["accent"])
        if ctk.get_appearance_mode() == "Dark":
            self.sw_tema.select()
        self.sw_tema.pack(side="left")

        barra = ctk.CTkFrame(self.pg_apuracao, fg_color="transparent")
        barra.grid(row=0, column=0, sticky="ew", padx=24, pady=(0, 16))
        ctk.CTkLabel(barra, text="Visualizando", font=F(12, "bold"), text_color=C["muted"]).pack(
            side="left", padx=(0, 8))
        self.om_visao = self.seletor_visao(barra)
        self.om_visao.pack(side="left")
        self.bt_recarregar = botao(barra, "Atualizar", self.recarregar_amigo, "neutro", width=100)
        self.bt_recarregar.pack(side="left", padx=8)

        self.bt_fechar = botao(barra, "Fechar mês", self.fechar_mes, "accent", width=130)
        self.bt_fechar.pack(side="right")
        self.badge = ctk.CTkLabel(barra, text="", font=F(12, "bold"), corner_radius=12, width=130, height=28)
        self.badge.pack(side="right", padx=12)
        self.bt_mes = botao(barra, "", self.abrir_seletor_mes, "neutro", width=130)
        self.bt_mes.pack(side="right")
        ctk.CTkLabel(barra, text="Mês", font=F(12, "bold"), text_color=C["muted"]).pack(side="right", padx=(0, 8))

    def montar_kpis(self):
        k = ctk.CTkFrame(self.pg_apuracao, fg_color="transparent")
        k.grid(row=1, column=0, sticky="ew", padx=24, pady=(0, 16))
        for i in range(4):
            k.grid_columnconfigure(i, weight=1, uniform="kpi")
        self.k_bruto = CardKPI(k, "Lucro bruto")
        self.k_liq = CardKPI(k, "Lucro líquido")
        self.k_imp = CardKPI(k, "Imposto devido")
        self.k_darf = CardKPI(k, "Total da DARF", destaque=True)
        for i, c in enumerate((self.k_bruto, self.k_liq, self.k_imp, self.k_darf)):
            c.grid(row=0, column=i, sticky="nsew", padx=(0 if i == 0 else 8, 0 if i == 3 else 8))

    def montar_corpo(self):
        corpo = ctk.CTkFrame(self.pg_apuracao, fg_color="transparent")
        corpo.grid(row=2, column=0, sticky="nsew", padx=24, pady=(0, 24))
        corpo.grid_columnconfigure(0, weight=1)
        corpo.grid_rowconfigure(0, weight=1)
        corpo.grid_rowconfigure(1, weight=1)

        # ativos
        c1 = self.card(corpo)
        c1.grid(row=0, column=0, sticky="nsew", pady=(0, 8))
        top = self.topo_card(c1, "Ativos comprados")
        self.lb_qtd_lotes = top[1]
        self.bt_excluir_lote = botao(top[0], "Excluir", self.excluir_lote, "perigo", width=90)
        self.bt_excluir_lote.pack(side="right")
        self.bt_editar_lote = botao(top[0], "Editar", self.editar_lote, "neutro", width=80)
        self.bt_editar_lote.pack(side="right", padx=(0, 8))
        self.bt_venda = botao(top[0], "Registrar venda", lambda: self.registrar_venda(), "neutro", width=140)
        self.bt_venda.pack(side="right", padx=(0, 8))
        self.bt_novo = botao(top[0], "+  Novo ativo", lambda: self.novo_ativo(), "accent", width=140)
        self.bt_novo.pack(side="right", padx=(0, 8))
        filtro = ctk.CTkFrame(c1, fg_color="transparent")
        filtro.pack(fill="x", padx=18, pady=(0, 10))
        ctk.CTkLabel(filtro, text="SITUAÇÃO", font=F(11, "bold"), text_color=C["muted"]).pack(side="left", padx=(0, 8))
        self.seg_filtro = ctk.CTkSegmentedButton(filtro, values=["Todos", "Em aberto", "Vendidos"],
                                                 command=self.filtrar_lotes, height=30, font=F(12, "bold"),
                                                 fg_color=C["neutro"], selected_color=C["accent"],
                                                 selected_hover_color=C["accent_h"], unselected_color=C["neutro"],
                                                 unselected_hover_color=C["neutro_h"], text_color=C["texto"])
        self.seg_filtro.set("Todos")
        self.seg_filtro.pack(side="left")
        ctk.CTkLabel(filtro, text="Clique nos títulos das colunas para ordenar", font=F(11),
                     text_color=C["muted"]).pack(side="right")
        self.t_lotes = Tabela(c1, [
            ("ticker", "TICKER", 90, "w"), ("tipo", "TIPO", 70, "w"), ("data", "COMPRA", 100, "center"),
            ("qtd", "QTD", 60, "e"), ("preco", "PREÇO", 100, "e"), ("atual", "ATUAL", 100, "e"),
            ("total", "TOTAL", 115, "e"), ("resultado", "GANHO/PERDA", 175, "e"),
            ("vendida", "VENDIDA", 75, "e"), ("restante", "RESTANTE", 80, "e"), ("status", "SITUAÇÃO", 120, "center")],
            "Nenhum ativo neste mês. Clique em  +  Novo ativo  para começar.",
            ordenaveis=("ticker", "data", "qtd", "preco", "atual", "total", "resultado", "restante"))
        self.t_lotes.pack(fill="both", expand=True, padx=16, pady=(0, 16))
        for ev in ("<Double-1>", "<<Duplo>>"):
            self.t_lotes.tv.bind(ev, lambda e: self.registrar_venda())

        # vendas
        c2 = self.card(corpo)
        c2.grid(row=1, column=0, sticky="nsew", pady=(8, 0))
        top = self.topo_card(c2, "Vendas do mês")
        self.lb_qtd_vendas = top[1]
        self.bt_excluir_venda = botao(top[0], "Excluir venda", self.excluir_venda, "perigo", width=120)
        self.bt_excluir_venda.pack(side="right")
        self.bt_editar_venda = botao(top[0], "Editar venda", self.editar_venda, "neutro", width=110)
        self.bt_editar_venda.pack(side="right", padx=(0, 8))
        self.t_vendas = Tabela(c2, [
            ("ticker", "TICKER", 80, "w"), ("tipo", "TIPO", 60, "w"), ("data", "VENDA", 95, "center"),
            ("qtd", "QTD", 60, "e"), ("preco", "PREÇO", 100, "e"), ("regime", "OPERAÇÃO", 120, "center"),
            ("taxas", "TAXAS B3", 90, "e"), ("bruto", "LUCRO BRUTO", 115, "e"),
            ("liquido", "APÓS TAXAS", 115, "e"), ("imposto", "IMPOSTO", 100, "e")],
            "Nenhuma venda registrada neste mês.",
            ordenaveis=("ticker", "data", "qtd", "preco", "taxas", "bruto", "liquido", "imposto"))
        self.t_vendas.pack(fill="both", expand=True, padx=16, pady=(0, 16))
        for ev in ("<Double-1>", "<<Duplo>>"):
            self.t_vendas.tv.bind(ev, lambda e: self.editar_venda())

        # lateral
        lat = self.card(corpo, width=340)
        lat.grid(row=0, column=1, rowspan=2, sticky="nsew", padx=(16, 0))
        lat.grid_propagate(False)
        lat.pack_propagate(False)
        ctk.CTkLabel(lat, text="Detalhamento", font=F(16, "bold"), text_color=C["texto"]).pack(
            anchor="w", padx=22, pady=(20, 14))

        ctk.CTkLabel(lat, text="LIMITE DE ISENÇÃO (AÇÕES · SWING)", font=F(11, "bold"),
                     text_color=C["muted"]).pack(anchor="w", padx=22)
        self.lb_limite = ctk.CTkLabel(lat, text="", font=F(14, "bold"), text_color=C["texto"])
        self.lb_limite.pack(anchor="w", padx=22, pady=(4, 6))
        self.pb_limite = ctk.CTkProgressBar(lat, height=10, corner_radius=5, fg_color=C["neutro"])
        self.pb_limite.pack(fill="x", padx=22)
        self.lb_isento = ctk.CTkLabel(lat, text="", font=F(12, "bold"))
        self.lb_isento.pack(anchor="w", padx=22, pady=(6, 10))

        self.separador(lat)
        self.l_custos = self.linha(lat, "Taxas B3 + corretagem")
        self.l_imp_st = self.linha(lat, "Imposto swing trade (15%)")
        self.l_imp_dt = self.linha(lat, "Imposto day trade (20%)")
        self.l_irrf = self.linha(lat, "IRRF retido (dedo-duro)")
        self.l_ant = self.linha(lat, "DARF de meses anteriores")
        self.separador(lat)
        self.l_darf = self.linha(lat, "Total a pagar", forte=True)
        self.lb_darf_info = ctk.CTkLabel(lat, text="", font=F(12), text_color=C["muted"],
                                         wraplength=290, justify="left")
        self.lb_darf_info.pack(anchor="w", padx=22, pady=(2, 0))

        rod = ctk.CTkFrame(lat, fg_color=C["card2"], corner_radius=10)
        rod.pack(side="bottom", fill="x", padx=16, pady=16)
        ctk.CTkLabel(rod, text="Código da DARF: 6015\nVencimento: último dia útil do mês seguinte\n"
                               "Taxas B3: 0,030% swing · 0,023% day trade",
                     font=F(11), text_color=C["muted"], justify="left").pack(anchor="w", padx=14, pady=12)

    def card(self, pai, **kw):
        return ctk.CTkFrame(pai, fg_color=C["card"], corner_radius=14, border_width=1,
                            border_color=C["borda"], **kw)

    def topo_card(self, card, titulo):
        f = ctk.CTkFrame(card, fg_color="transparent")
        f.pack(fill="x", padx=18, pady=(14, 10))
        ctk.CTkLabel(f, text=titulo, font=F(16, "bold"), text_color=C["texto"]).pack(side="left")
        cont = ctk.CTkLabel(f, text="0", font=F(11, "bold"), fg_color=C["neutro"], corner_radius=10,
                            text_color=C["muted"], width=30, height=22)
        cont.pack(side="left", padx=10)
        return f, cont

    def linha(self, pai, rotulo, forte=False):
        f = ctk.CTkFrame(pai, fg_color="transparent")
        f.pack(fill="x", padx=22, pady=5)
        ctk.CTkLabel(f, text=rotulo, font=F(14 if forte else 13, "bold" if forte else "normal"),
                     text_color=C["texto"] if forte else C["muted"]).pack(side="left")
        v = ctk.CTkLabel(f, text="R$ 0,00", font=F(16 if forte else 13, "bold"), text_color=C["texto"])
        v.pack(side="right")
        return v

    def separador(self, pai):
        ctk.CTkFrame(pai, height=1, fg_color=C["borda"]).pack(fill="x", padx=22, pady=10)

    def estilizar_tabelas(self):
        s = ttk.Style(self)
        s.theme_use("clam")
        bg, head = cor("card"), cor("card2")
        try:
            esc = ctk.ScalingTracker.get_widget_scaling(self)
        except Exception:
            esc = 1.0
        s.configure("D.Treeview", background=bg, fieldbackground=bg, foreground=cor("texto"),
                    rowheight=int(34 * esc), borderwidth=0, relief="flat", font=(FONTE, 10))
        s.configure("D.Treeview.Heading", background=head, foreground=cor("muted"),
                    font=(FONTE, 9, "bold"), borderwidth=0, relief="flat", padding=(8, 9))
        s.map("D.Treeview.Heading", background=[("active", head)], relief=[("active", "flat")])
        s.map("D.Treeview", background=[("selected", cor("selecao"))],
              foreground=[("selected", cor("texto"))])
        s.layout("D.Treeview", [("Treeview.treearea", {"sticky": "nswe"})])
        for t in (self.t_lotes, self.t_vendas, self.t_agenda):
            t.aplicar_cores()

    # --- eventos
    def trocar_tema(self):
        modo = "Dark" if self.sw_tema.get() else "Light"
        ctk.set_appearance_mode(modo)
        self.cfg["tema"] = modo
        gravar_config(self.cfg)
        self.estilizar_tabelas()
        self.atualizar()

    def filtrar_lotes(self, opcao):
        filtros = {"Todos": None, "Em aberto": lambda k: k["restante"] > 0, "Vendidos": lambda k: k["restante"] == 0}
        self.t_lotes.set_filtro(filtros[opcao])
        self.contar_lotes()

    def contar_lotes(self):
        t = self.t_lotes
        self.lb_qtd_lotes.configure(text=str(t.visiveis) if t.filtro is None else f"{t.visiveis}/{len(t.linhas)}")

    def trocar_mes(self, mes):
        self.mes = mes
        if self.visao:
            self.d = self.dados_amigo.get(self.mes) or mes_vazio(self.mes)
        else:
            self.d = carregar(self.mes)
        self.atualizar()

    def gravar(self):
        salvar(self.d)
        self.atualizar()
        self.atualizar_caixa()
        self.agendar_sync()

    def atualizar(self):
        if self.visao:
            self.lb_sub.configure(text=f"Dados de {self.visao} · somente leitura", text_color=C["aviso"])
        else:
            self.lb_sub.configure(text="Ações e BDRs · apuração mensal de IR", text_color=C["muted"])
        self.bt_mes.configure(text=f"{fmt_mes(self.mes)}  ▾")
        self.seletores("set", self.visao or "Meus dados")
        self.bt_recarregar.configure(state="normal" if self.visao else "disabled")

        fechado = self.d["fechado"]
        if self.visao:
            self.badge.configure(text="Somente leitura", fg_color=C["neutro"], text_color=C["aviso"])
        elif fechado:
            self.badge.configure(text="Fechado", fg_color=C["neutro"], text_color=C["muted"])
        else:
            self.badge.configure(text="● Aberto", fg_color=C["accent_bg"], text_color=C["accent"])
        estado = "disabled" if (fechado or self.visao) else "normal"
        for b in (self.bt_novo, self.bt_venda, self.bt_editar_lote, self.bt_excluir_lote, self.bt_editar_venda,
                  self.bt_excluir_venda, self.bt_fechar):
            b.configure(state=estado)

        linhas = []
        em_carteira = set()
        for l in self.d["lotes"]:
            st = status_lote(l)
            tags = ("muted",) if st == "Vendido" else ()
            atual = self.cotacoes.preco(l["ticker"]) if restante(l) > 0 else None
            if restante(l) > 0:
                em_carteira.add(l["ticker"])
            res = nc.resultado_aberto(l, atual)
            if restante(l) == 0:
                txt_atual = "—"
            else:
                txt_atual = brl(atual) if atual else ("…" if l["ticker"] not in self.cotacoes.precos else "—")
            linhas.append((l["id"], (l["ticker"], l["tipo"], fmt_data(l["data_compra"]), l["qtd"],
                                     brl(l["preco"]), txt_atual, brl(l["qtd"] * l["preco"]),
                                     ("▲ " if res and res[0] > 0.004 else "▼ " if res and res[0] < -0.004 else "")
                                     + nc.fmt_resultado(res), vendido(l), restante(l), st), tags,
                           {"ticker": l["ticker"], "data": l["data_compra"], "qtd": l["qtd"], "preco": l["preco"],
                            "atual": atual or float("-inf"), "total": l["qtd"] * l["preco"],
                            "resultado": res[0] if res else float("-inf"), "restante": restante(l),
                            "_cores": {"resultado": "accent" if res[0] > 0.004 else "danger"}
                            if res and abs(res[0]) > 0.004 else {}}))
        self.t_lotes.preencher(linhas)
        self.contar_lotes()
        self.cotacoes.atualizar(em_carteira, lambda: self.fila.put((lambda _: self.atualizar(), None, None)))

        r = apurar(self.d)
        linhas = []
        for o in sorted(r["ops"], key=lambda o: o["data"]):
            tag = ("neg",) if o["liquido"] < 0 else ()
            linhas.append((o["venda_id"], (o["ticker"], o["tipo"], fmt_data(o["data"]), o["qtd"],
                                           brl(o["preco"]), o["regime"], brl(o["taxas"] + o["corretagem"]),
                                           brl(o["bruto"]), brl(o["liquido"]), brl(o["imposto"])), tag,
                           {"ticker": o["ticker"], "data": o["data"], "qtd": o["qtd"], "preco": o["preco"],
                            "taxas": o["taxas"] + o["corretagem"], "bruto": o["bruto"], "liquido": o["liquido"],
                            "imposto": o["imposto"]}))
        self.t_vendas.preencher(linhas)
        self.lb_qtd_vendas.configure(text=str(len(linhas)))

        def cor_res(v):
            return C["danger"] if v < 0 else (C["accent"] if v > 0 else C["texto"])

        n = len(r["ops"])
        self.k_bruto.set(brl(r["bruto"]), f"{n} venda{'s' if n != 1 else ''} no mês", cor_res(r["bruto"]))
        self.k_liq.set(brl(r["lucro_liquido"]), "após taxas e impostos", cor_res(r["lucro_liquido"]))
        self.k_imp.set(brl(r["imposto_total"]), f"IRRF já retido: {brl(r['irrf'])}")
        if r["darf"] >= DARF_MINIMO:
            info = f"Código 6015 · vence no último dia útil de {fmt_mes(proximo_mes(self.mes))}"
        elif r["darf"] > 0:
            info = "Abaixo de R$ 10 · acumula para o próximo mês"
        else:
            info = "Nada a pagar neste mês"
        self.k_darf.set(brl(r["darf"]), info, C["accent"] if r["darf"] >= DARF_MINIMO else None)

        v = r["vendas_acoes_st"]
        self.lb_limite.configure(text=f"{brl(v)}  de  {brl(LIMITE_ISENCAO)}")
        self.pb_limite.set(min(v / LIMITE_ISENCAO, 1))
        if r["isento"]:
            self.pb_limite.configure(progress_color=C["accent"])
            self.lb_isento.configure(text="Isento de IR em swing trade de ações", text_color=C["accent"])
        else:
            self.pb_limite.configure(progress_color=C["danger"])
            self.lb_isento.configure(text="Acima do limite · lucro tributado em 15%", text_color=C["danger"])

        self.l_custos.configure(text=brl(r["custos"]))
        self.l_imp_st.configure(text=brl(r["imp_st"]))
        self.l_imp_dt.configure(text=brl(r["imp_dt"]))
        self.l_irrf.configure(text="- " + brl(r["irrf"]) if r["irrf"] else brl(0))
        self.l_ant.configure(text=brl(r["darf_anterior"]))
        self.l_darf.configure(text=brl(r["darf"]), text_color=C["accent"] if r["darf"] >= DARF_MINIMO else C["texto"])
        self.lb_darf_info.configure(text=info)

    def sugestoes(self, so_custodia=False):
        freq, tipos = historico_tickers()
        custodia = {l["ticker"] for l in self.d["lotes"] if restante(l) > 0}
        if so_custodia:
            lista = sorted(custodia, key=lambda t: (-freq[t], t))
        else:
            lista = sorted(set(freq) | custodia, key=lambda t: (-(freq[t] + (2 if t in custodia else 0)), t))
        return lista[:6], tipos

    def novo_ativo(self, iniciais=None):
        if self.visao or self.d["fechado"]:
            return
        sugestoes, tipos = self.sugestoes()
        f = FormCompra(self, sugestoes, tipos, iniciais)
        if not f.resultado:
            return
        lote = {"id": uuid.uuid4().hex, **f.resultado, "vendas": []}
        self.d["lotes"].append(lote)
        self.gravar()
        if confirmar(self, "Venda", f"Você já fez a venda de {lote['ticker']}?",
                     sim="Sim, registrar venda", nao="Ainda não"):
            self.registrar_venda(lote)

    def registrar_venda(self, lote=None, ticker=""):
        if self.visao or self.d["fechado"]:
            return
        if lote is None and not ticker:
            lid = self.t_lotes.selecionado()
            lote = next((l for l in self.d["lotes"] if l["id"] == lid), None) if lid else None
            if lote and restante(lote) == 0:
                lote = None
        if not any(restante(l) > 0 for l in self.d["lotes"]):
            avisar(self, "Registrar venda", "Não há compras em aberto neste mês.")
            return
        sugestoes, _ = self.sugestoes(so_custodia=True)
        f = FormVenda(self, self.d, sugestoes, lote_inicial=lote, ticker_inicial=ticker)
        if not f.resultado:
            return
        r = dict(f.resultado)
        lote_id = r.pop("lote_id")
        alvo = next(l for l in self.d["lotes"] if l["id"] == lote_id)
        alvo["vendas"].append({"id": uuid.uuid4().hex, **r})
        self.gravar()

    def editar_lote(self):
        if self.visao or self.d["fechado"]:
            return
        lid = self.t_lotes.selecionado()
        lote = next((l for l in self.d["lotes"] if l["id"] == lid), None) if lid else None
        if not lote:
            avisar(self, "Editar", "Selecione uma compra na tabela de ativos comprados.")
            return
        sugestoes, tipos = self.sugestoes()
        f = FormCompra(self, sugestoes, tipos, editar=lote)
        if not f.resultado:
            return
        lote.update(f.resultado)
        self.gravar()

    def editar_venda(self):
        if self.visao or self.d["fechado"]:
            return
        vid = self.t_vendas.selecionado()
        par = next(((l, v) for l in self.d["lotes"] for v in l["vendas"] if v["id"] == vid), None) if vid else None
        if not par:
            avisar(self, "Editar", "Selecione uma venda na tabela de vendas.")
            return
        f = FormVenda(self, self.d, [], editar=par)
        if not f.resultado:
            return
        r = dict(f.resultado)
        r.pop("lote_id")
        par[1].update(r)
        self.gravar()

    def excluir_lote(self):
        lid = self.t_lotes.selecionado()
        if not lid:
            avisar(self, "Excluir", "Selecione um ativo na tabela de ativos comprados.")
            return
        lote = next(l for l in self.d["lotes"] if l["id"] == lid)
        txt = f"Excluir {lote['ticker']}"
        txt += " e todas as vendas dele?" if lote["vendas"] else "?"
        if not confirmar(self, "Excluir ativo", txt, sim="Excluir", perigo=True):
            return
        self.d["lotes"] = [l for l in self.d["lotes"] if l["id"] != lid]
        self.gravar()

    def excluir_venda(self):
        vid = self.t_vendas.selecionado()
        if not vid:
            avisar(self, "Excluir", "Selecione uma venda na tabela de vendas.")
            return
        if not confirmar(self, "Excluir venda", "Excluir esta venda?", sim="Excluir", perigo=True):
            return
        for l in self.d["lotes"]:
            l["vendas"] = [v for v in l["vendas"] if v["id"] != vid]
        self.gravar()

    def fechar_mes(self):
        r = apurar(self.d)
        if not confirmar(self, f"Fechar {fmt_mes(self.mes)}",
                         f"Depois de fechado, o mês não pode ser alterado.\n\nTotal da DARF: {brl(r['darf'])}",
                         sim="Fechar mês"):
            return
        r, prox = nc.fechar_mes(self.d)
        avisar(self, "Mês fechado", nc.mensagem_fechamento(r, prox))
        self.atualizar()
        self.agendar_sync()

    # --- navegação
    def trocar_pagina(self, rotulo):
        if rotulo.startswith(PAGINA_NOTICIAS):  # o rótulo pode trazer a contagem: "Notícias (3)"
            rotulo = PAGINA_NOTICIAS
        paginas = {PAGINA_APURACAO: ("apuracao", self.pg_apuracao), PAGINA_RADAR: ("radar", self.pg_radar),
                   PAGINA_CAIXA: ("caixa", self.pg_caixa), PAGINA_NOTICIAS: ("noticias", self.pg_noticias)}
        for r, (_, pg) in paginas.items():
            if r != rotulo:
                pg.grid_remove()
        self.pagina, pg = paginas.get(rotulo, paginas[PAGINA_APURACAO])
        pg.grid(row=1, column=0, sticky="nsew")
        if self.pagina == "radar":
            self.radar_redesenhar()
            self.atualizar_radar()
        elif self.pagina == "caixa":
            self.atualizar_caixa()
        elif self.pagina == "noticias":
            self.desenhar_noticias()
            nt.marcar_lidas()
            if nt.precisa_atualizar(nt.ler_estado()):
                self.atualizar_noticias()
        self.rotular_noticias()
        self.nav.set(next(v for v in self.nav.cget("values") if v.startswith(rotulo)))

    # --- caixa (tesouraria)
    def montar_caixa(self):
        pg = self.pg_caixa = ctk.CTkFrame(self, fg_color="transparent")
        pg.grid_columnconfigure(0, weight=1)
        pg.grid_rowconfigure(3, weight=1)
        barra = ctk.CTkFrame(pg, fg_color="transparent")
        barra.grid(row=0, column=0, sticky="ew", padx=24, pady=(0, 12))
        ctk.CTkLabel(barra, text="Visualizando", font=F(12, "bold"), text_color=C["muted"]).pack(side="left",
                                                                                               padx=(0, 8))
        self.seletor_visao(barra).pack(side="left")
        self.lb_caixa_dono = ctk.CTkLabel(barra, text="", font=F(12, "bold"), text_color=C["aviso"])
        self.lb_caixa_dono.pack(side="left", padx=12)
        k = ctk.CTkFrame(pg, fg_color="transparent")
        k.grid(row=1, column=0, sticky="ew", padx=24, pady=(0, 8))
        for i in range(3):
            k.grid_columnconfigure(i, weight=1, uniform="caixa")
        self.k_disp = CardKPI(k, "Saldo disponível (D+0)")
        self.k_trans = CardKPI(k, "Em trânsito (D+1 / D+2)")
        self.k_proj = CardKPI(k, "Saldo projetado", destaque=True)
        for i, c in enumerate((self.k_disp, self.k_trans, self.k_proj)):
            c.grid(row=0, column=i, sticky="nsew", padx=(0 if i == 0 else 8, 0 if i == 2 else 8))
        self.bt_editar_saldo = botao(self.k_disp, "✎  Editar", self.editar_saldo, "neutro", altura=30, fonte=12,
                                     width=96)
        self.bt_editar_saldo.place(relx=1.0, x=-14, y=12, anchor="ne")
        self.lb_caixa_info = ctk.CTkLabel(pg, text="", font=F(12), text_color=C["muted"], anchor="w", justify="left")
        self.lb_caixa_info.grid(row=2, column=0, sticky="ew", padx=28, pady=(0, 12))

        card = self.card(pg)
        card.grid(row=3, column=0, sticky="nsew", padx=24, pady=(0, 24))
        self.lb_qtd_agenda = self.topo_card(card, "Agenda financeira")[1]
        self.fr_grupos = ctk.CTkFrame(card, fg_color="transparent")
        self.fr_grupos.pack(fill="x", padx=18, pady=(0, 10))
        self.t_agenda = Tabela(card, [
            ("liquidacao", "LIQUIDAÇÃO (D+2)", 190, "w"), ("data", "OPERAÇÃO", 100, "center"),
            ("ticker", "TICKER", 90, "w"), ("tipo", "TIPO", 140, "w"), ("valor", "VALOR LÍQUIDO", 150, "e"),
            ("status", "STATUS", 110, "center")],
            "Nenhum lançamento. Compras e vendas aparecem aqui com a data de liquidação (D+2 úteis).",
            ordenaveis=("liquidacao", "data", "ticker", "valor"))
        self.t_agenda.pack(fill="both", expand=True, padx=16, pady=(0, 16))
        self.dia_caixa = date.today()

    def atualizar_caixa(self):
        """Recalcula o caixa; chamado ao gravar, ao sincronizar e na virada do dia."""
        hoje = date.today()
        self.dia_caixa = hoje
        r = nc.resumo_caixa(self.cfg, hoje)
        self.bt_saldo.configure(text=f"Saldo: {brl(r['disponivel'])}" if r["definido"] else "Definir saldo")
        if not hasattr(self, "k_disp"):
            return
        amigo = self.visao
        if amigo:  # caixa do amigo, calculado com as operações e o saldo da planilha dele
            r = nc.resumo_caixa({"caixa": self.amigo_caixa or {}}, hoje, meses=self.dados_amigo)
        self.lb_caixa_dono.configure(text=f"Caixa de {amigo} · somente leitura" if amigo else "")
        if amigo:
            self.bt_editar_saldo.place_forget()
        else:
            self.bt_editar_saldo.place(relx=1.0, x=-14, y=12, anchor="ne")
        if r["definido"]:
            self.k_disp.set(brl(r["disponivel"]), "livre para novas operações",
                            C["danger"] if r["disponivel"] < 0 else None)
            self.lb_caixa_info.configure(
                text=f"Saldo informado em {r['base']:%d/%m/%Y}. As liquidações seguintes entram sozinhas no "
                     f"saldo disponível quando a data chega.")
        else:
            self.k_disp.set("—", "não informado" if amigo else "clique em Editar para informar")
            self.lb_caixa_info.configure(text=f"{amigo} ainda não informou o saldo da conta." if amigo else
                                         "Informe o saldo livre na conta para acompanhar o caixa.")
        partes = []
        if r["a_debitar"]:
            partes.append(f"{brl(r['a_debitar'])} a debitar")
        if r["a_receber"]:
            partes.append(f"+{brl(r['a_receber'])} a receber")
        self.k_trans.set(brl(r["transito"]), " · ".join(partes) or "nada pendente",
                         C["danger"] if r["transito"] < -0.004 else (C["accent"] if r["transito"] > 0.004 else None))
        self.k_proj.set(brl(r["projetado"]) if r["definido"] else "—", "disponível + liquidações futuras",
                        C["danger"] if r["definido"] and r["projetado"] < 0 else None)

        for w in self.fr_grupos.winfo_children():
            w.destroy()
        grupos = nc.agenda_caixa(r, hoje)
        pendentes = [g for g in grupos if g[0] > hoje]
        for d, rot, total, _ in pendentes[:6]:
            cor_t = C["danger"] if total < -0.004 else (C["accent"] if total > 0.004 else C["texto"])
            sinal = "+" if total > 0.004 else ""
            pilula(self.fr_grupos, f"{rot}: {sinal}{brl(total)}", C["neutro"], cor_t, 12).pack(
                side="left", padx=(0, 8))
        if not pendentes:
            ctk.CTkLabel(self.fr_grupos, text="Nenhuma liquidação pendente.", font=F(12),
                         text_color=C["muted"]).pack(side="left")

        linhas = []
        for d, rot, _, itens in grupos:
            for it in itens:
                v = it["valor"]
                linhas.append((it["id"], (nc.fmt_liquidacao(it["liquidacao"]), fmt_data(it["data"]), it["ticker"],
                                          it["tipo"], ("+" if v > 0.004 else "") + brl(v), it["status"]),
                               ("muted",) if it["status"] == "Liquidado" else (),
                               {"liquidacao": it["liquidacao"].isoformat(), "data": it["data"], "ticker": it["ticker"],
                                "valor": v,
                                "_cores": {"valor": "accent" if v > 0.004 else "danger"} if abs(v) > 0.004 else {}}))
        self.t_agenda.preencher(linhas)
        self.lb_qtd_agenda.configure(text=str(len([1 for l in linhas if l[1][5] == "Pendente"])))

    def editar_saldo(self):
        r = nc.resumo_caixa(self.cfg)
        f = FormSaldo(self, r["disponivel"], r["definido"])
        if not f.resultado:
            return
        modo, valor = f.resultado
        if modo == "Definir saldo":
            nc.definir_saldo(self.cfg, valor)
        else:
            nc.ajustar_saldo(self.cfg, valor if modo == "Aporte" else -valor)
        self.cfg["pendente"] = True
        gravar_config(self.cfg)
        self.atualizar_caixa()
        self.agendar_sync()

    def tick_caixa(self):
        """Virada do dia: o que liquidou passa a Liquidado e entra no saldo disponível."""
        if date.today() != self.dia_caixa:
            self.atualizar_caixa()
        self.after(60000, self.tick_caixa)

    def abrir_seletor_mes(self):
        com_dados = set(self.dados_amigo) if self.visao else set(listar_meses())
        SeletorMes(self.bt_mes, self.mes, com_dados, date.today().strftime("%Y-%m"), self.trocar_mes)

    # --- radar
    def montar_radar(self):
        pg = self.pg_radar = ctk.CTkFrame(self, fg_color="transparent")
        pg.grid_columnconfigure(0, weight=1)
        pg.grid_rowconfigure(1, weight=1)

        topo = self.card(pg)
        topo.grid(row=0, column=0, sticky="ew", padx=24, pady=(0, 16))
        linha1 = ctk.CTkFrame(topo, fg_color="transparent")
        linha1.pack(fill="x", padx=20, pady=(16, 0))
        esq = ctk.CTkFrame(linha1, fg_color="transparent")
        esq.pack(side="left")
        self.lb_radar_titulo = ctk.CTkLabel(esq, text="Radar de Ações", font=F(18, "bold"), text_color=C["texto"])
        self.lb_radar_titulo.pack(anchor="w")
        self.lb_radar_status = ctk.CTkLabel(esq, text="Cotações do Yahoo Finance (atraso de até 15 min)",
                                            font=F(12), text_color=C["muted"])
        self.lb_radar_status.pack(anchor="w")
        leg = ctk.CTkFrame(topo, fg_color="transparent")
        leg.pack(fill="x", padx=20, pady=(12, 16))
        ctk.CTkLabel(leg, text="RISCO PELO ATR%", font=F(11, "bold"), text_color=C["muted"]).pack(
            side="left", padx=(0, 10))
        for (limite, rotulo, fundo, txt), faixa in zip(mk.FAIXAS_RISCO, ("< 2,2%", "2,2% a 3,0%", "3,0% a 4,5%",
                                                                         "> 4,5%")):
            pilula(leg, f"{rotulo} · {faixa}", fundo, txt).pack(side="left", padx=(0, 6))

        dir_ = ctk.CTkFrame(linha1, fg_color="transparent")
        dir_.pack(side="right")
        self.seletor_visao(dir_, 240).pack(side="left", padx=(0, 16))
        self.fr_radar_meu = ctk.CTkFrame(dir_, fg_color="transparent")
        self.fr_radar_meu.pack(side="left")
        self.bt_importar_todos = botao(dir_, "+  Importar todos para o meu radar", self.importar_todos_radar, "accent",
                                       width=250)
        self.en_radar = ctk.CTkEntry(self.fr_radar_meu, width=200, height=38, font=F(13), corner_radius=8,
                                     border_color=C["borda"], fg_color=C["card2"], text_color=C["texto"],
                                     placeholder_text="Ticker (ex.: VALE3)")
        self.en_radar.pack(side="left")
        self.en_radar.bind("<Return>", lambda e: self.adicionar_radar())
        botao(self.fr_radar_meu, "+  Adicionar", self.adicionar_radar, "accent", width=120).pack(side="left", padx=8)
        botao(dir_, "Atualizar", lambda: self.atualizar_radar(forcar=True), "neutro", width=100).pack(side="right")

        lista = self.card(pg)
        lista.grid(row=1, column=0, sticky="nsew", padx=24, pady=(0, 24))
        cabecalho_radar(lista).pack(fill="x", padx=(16, 30), pady=(16, 4))
        self.lista_radar = ctk.CTkScrollableFrame(lista, fg_color="transparent")
        self.lista_radar.pack(fill="both", expand=True, padx=(10, 10), pady=(0, 12))
        self.lista_radar.grid_columnconfigure(0, weight=1)
        self.lb_radar_vazio = ctk.CTkLabel(self.lista_radar, text="Nenhum ativo no radar. Adicione um ticker acima.",
                                           font=F(13), text_color=C["muted"])

    # --- imagens (logos e ícones das fontes)
    def imagem(self, chave, baixar, tam, ao_carregar):
        """Baixa a imagem uma vez (fora da interface) e entrega reduzida para cerca de tam px."""
        img = self.imagens.get(chave, False)
        if img is None:
            return
        if img is not False:
            if img == "carregando":
                self.esperando[chave].append(ao_carregar)
            else:
                ao_carregar(img)
            return
        self.imagens[chave] = "carregando"
        self.esperando[chave] = [ao_carregar]

        def pronto(b):
            img = None
            if b:
                try:
                    img = tk.PhotoImage(data=base64.b64encode(b).decode())
                    passo = max(1, round(img.width() / tam))
                    if passo > 1:
                        img = img.subsample(passo)
                except Exception:
                    img = None
            self.imagens[chave] = img
            for cb in self.esperando.pop(chave, []):
                if img is not None:
                    cb(img)

        def falhou(_):
            self.imagens.pop(chave, None)
            self.esperando.pop(chave, None)

        self.bg(baixar, ok=pronto, erro=falhou)

    # --- notícias
    def montar_noticias(self):
        pg = self.pg_noticias = ctk.CTkFrame(self, fg_color="transparent")
        pg.grid_columnconfigure(0, weight=1)
        pg.grid_rowconfigure(1, weight=1)
        topo = self.card(pg)
        topo.grid(row=0, column=0, sticky="ew", padx=24, pady=(0, 16))
        linha1 = ctk.CTkFrame(topo, fg_color="transparent")
        linha1.pack(fill="x", padx=20, pady=(16, 0))
        esq = ctk.CTkFrame(linha1, fg_color="transparent")
        esq.pack(side="left")
        ctk.CTkLabel(esq, text="Notícias do radar", font=F(18, "bold"), text_color=C["texto"]).pack(anchor="w")
        self.lb_noticias_status = ctk.CTkLabel(esq, text="Google Notícias · ativos do Radar de Ações", font=F(12),
                                               text_color=C["muted"])
        self.lb_noticias_status.pack(anchor="w")
        dir_ = ctk.CTkFrame(linha1, fg_color="transparent")
        dir_.pack(side="right")
        self.sb_noticias = ctk.CTkSegmentedButton(
            dir_, values=["Todas", "Relevantes"], command=lambda v: self.filtrar_noticias(tema=v), height=36,
            font=F(12, "bold"), fg_color=C["neutro"], selected_color=C["accent"], selected_hover_color=C["accent_h"],
            unselected_color=C["neutro"], unselected_hover_color=C["neutro_h"], text_color=C["texto"])
        self.sb_noticias.set("Todas")
        self.sb_noticias.pack(side="left")
        self.om_noticias = ctk.CTkOptionMenu(
            dir_, values=["Todos os ativos"], command=lambda v: self.filtrar_noticias(ticker=v), width=170, height=36,
            font=F(12, "bold"), dropdown_font=F(12), corner_radius=8, fg_color=C["neutro"],
            button_color=C["neutro_h"], button_hover_color=C["borda"], text_color=C["texto"])
        self.om_noticias.pack(side="left", padx=8)
        botao(dir_, "Atualizar", lambda: self.atualizar_noticias(forcar=True), "neutro", width=100).pack(side="left")
        linha2 = ctk.CTkFrame(topo, fg_color="transparent")
        linha2.pack(fill="x", padx=20, pady=(12, 16))
        self.sw_notificar = ctk.CTkSwitch(linha2, text="Notificar notícias relevantes", font=F(12),
                                          text_color=C["texto"], command=self.trocar_notificar,
                                          progress_color=C["accent"])
        if self.cfg.get("noticias_notificar", True):
            self.sw_notificar.select()
        self.sw_notificar.pack(side="left")
        ctk.CTkLabel(linha2, text="Relevantes: fato relevante, resultado, proventos, recomendação, fusão/aquisição, "
                                  "recompra, desdobramento, governança, jurídico e fortes oscilações. Clique na "
                                  "notícia para abrir.", font=F(11), text_color=C["muted"]).pack(side="left", padx=16)
        lista = self.card(pg)
        lista.grid(row=1, column=0, sticky="nsew", padx=24, pady=(0, 24))
        self.lista_noticias = ctk.CTkScrollableFrame(lista, fg_color="transparent")
        self.lista_noticias.pack(fill="both", expand=True, padx=10, pady=12)
        self.lista_noticias.grid_columnconfigure(0, weight=1)
        self.lista_noticias.bind("<Configure>", self.mural_redimensionado, add="+")

    def filtrar_noticias(self, tema=None, ticker=None):
        if tema:
            self.noticias_filtro["tema"] = tema
        if ticker:
            self.noticias_filtro["ticker"] = ticker
        self.desenhar_noticias()

    def trocar_notificar(self):
        self.cfg["noticias_notificar"] = bool(self.sw_notificar.get())
        gravar_config(self.cfg)

    def desenhar_noticias(self):
        if not hasattr(self, "lista_noticias"):
            return
        d = nt.ler_estado()
        radar = [r["ticker"] for r in nc.ordenar_radar(self.cfg["radar"])]
        opcoes = ["Todos os ativos"] + radar
        if self.noticias_filtro["ticker"] not in opcoes:
            self.noticias_filtro["ticker"] = "Todos os ativos"
        self.om_noticias.configure(values=opcoes)
        self.om_noticias.set(self.noticias_filtro["ticker"])
        f = self.noticias_filtro
        itens = [i for i in d["itens"] if set(i["tickers"]) & set(radar)
                 and (f["tema"] == "Todas" or i["temas"])
                 and (f["ticker"] == "Todos os ativos" or f["ticker"] in i["tickers"])]
        rolagem = self.posicao_rolagem()
        for w in self.lista_noticias.winfo_children():
            w.destroy()
        if not radar:
            vazio = "Adicione ativos no Radar de Ações para ver as notícias deles aqui."
        elif not d["hora"]:
            vazio = "Buscando notícias…" if self.noticias_rodando else "Nenhuma busca feita ainda. Clique em Atualizar."
        else:
            vazio = "Nenhuma notícia nos últimos 7 dias com esse filtro."
        if not itens:
            ctk.CTkLabel(self.lista_noticias, text=vazio, font=F(13), text_color=C["muted"]).grid(row=0, column=0,
                                                                                                pady=60)
        else:
            self.montar_mural(itens[:60], d)
        self.after_idle(lambda: self.restaurar_rolagem(rolagem))
        if any(i["id"] not in self.det_noticias for i in d["itens"][:nt.MAX_DETALHES]):
            self.detalhar_noticias(d["itens"])
        self.status_noticias(d)

    def largura_mural(self):
        try:
            px = self.lista_noticias.winfo_width()
            escala = ctk.ScalingTracker.get_widget_scaling(self.lista_noticias)
        except Exception:
            px, escala = 0, 1
        larg = px / (escala or 1) - 24
        return larg if larg > 300 else 1250

    def montar_mural(self, itens, d):
        """Destaque no topo e o resto em colunas, cada cartão no tamanho do seu conteúdo (estilo mural)."""
        largura = self.largura_mural()
        self.mural_largura = largura
        espaco = 16
        ncol = max(1, min(4, int((largura + espaco) // 340)))
        larg_col = (largura - espaco * (ncol - 1)) / ncol
        det = self.det_noticias
        linha = 0
        resto = list(itens)
        if ncol >= 2:
            com_foto = [i for i in itens[:6] if det.get(i["id"], {}).get("img")]
            destaque = next((i for i in com_foto if i["temas"]), com_foto[0] if com_foto else itens[0])
            resto.remove(destaque)
            CardNoticia(self.lista_noticias, self, destaque, det.get(destaque["id"]), nt.eh_nova(d, destaque),
                        largura, "destaque").grid(row=0, column=0, sticky="ew", padx=4, pady=(4, espaco))
            linha = 1
        grade = ctk.CTkFrame(self.lista_noticias, fg_color="transparent")
        grade.grid(row=linha, column=0, sticky="new", padx=4)
        colunas, alturas = [], [0.0] * ncol
        for c in range(ncol):
            grade.grid_columnconfigure(c, weight=1, uniform="mural")
            f = ctk.CTkFrame(grade, fg_color="transparent")
            f.grid(row=0, column=c, sticky="new", padx=(0 if c == 0 else espaco / 2, 0 if c == ncol - 1 else espaco / 2))
            colunas.append(f)
        for n, it in enumerate(resto):
            dt = det.get(it["id"])
            estilo = estilo_noticia(it, dt, n)
            c = alturas.index(min(alturas))
            CardNoticia(colunas[c], self, it, dt, nt.eh_nova(d, it), larg_col, estilo).pack(fill="x", pady=(0, espaco))
            alturas[c] += altura_noticia(it, dt, estilo, larg_col) + espaco

    def mural_redimensionado(self, _=None):
        if self.pagina != "noticias":
            return
        if self.redim_job:
            self.after_cancel(self.redim_job)

        def refazer():
            self.redim_job = None
            if abs(self.largura_mural() - self.mural_largura) > 40:
                self.desenhar_noticias()

        self.redim_job = self.after(300, refazer)

    def posicao_rolagem(self):
        try:
            return self.lista_noticias._parent_canvas.yview()[0]
        except Exception:
            return 0

    def restaurar_rolagem(self, pos):
        try:
            self.lista_noticias._parent_canvas.yview_moveto(pos)
        except Exception:
            pass

    def detalhar_noticias(self, itens):
        """Busca imagem e resumo das matérias (em segundo plano) e redesenha quando chegarem."""
        if self.detalhando:
            return
        self.detalhando = True
        itens = [dict(i) for i in itens]

        def fim(mudou):
            self.detalhando = False
            self.det_noticias = nt.ler_detalhes()
            if mudou and self.pagina == "noticias":
                self.desenhar_noticias()

        def erro(_):
            self.detalhando = False

        self.bg(lambda: nt.enriquecer(itens), ok=fim, erro=erro)

    def imagem_noticia(self, url, larg, alt, ao_carregar):
        """Imagem da matéria recortada no tamanho do cartão (Pillow)."""
        chave = (url, int(larg), int(alt))
        img = self.fotos.get(chave)
        if img is not None:
            ao_carregar(img)
            return
        destino = DADOS / "noticias_img" / (hashlib.sha1(url.encode()).hexdigest()[:20] + ".jpg")

        def pronto(caminho):
            if not caminho:
                return
            try:
                from PIL import Image, ImageOps
                with Image.open(caminho) as im:
                    recorte = ImageOps.fit(im.convert("RGB"), (int(larg * 2), int(alt * 2)), Image.LANCZOS)
                foto = ctk.CTkImage(light_image=recorte, dark_image=recorte, size=(int(larg), int(alt)))
            except Exception:
                return
            self.fotos[chave] = foto
            ao_carregar(foto)

        self.bg(lambda: nt.baixar_imagem_noticia(url, destino), ok=pronto, erro=lambda e: None)

    def status_noticias(self, d):
        if not d["hora"] or self.noticias_rodando:
            return
        erros = d.get("erros") or {}
        txt = f"Atualizado às {datetime.fromtimestamp(d['hora']):%H:%M} · Google Notícias, últimos 7 dias"
        if erros:
            txt += f" · falha em {', '.join(sorted(erros))}"
        self.lb_noticias_status.configure(text=txt, text_color=C["danger"] if erros else C["muted"])

    def rotular_noticias(self):
        n = 0 if self.pagina == "noticias" else nt.nao_lidas(nt.ler_estado())
        rotulo = f"{PAGINA_NOTICIAS} ({n})" if n else PAGINA_NOTICIAS
        valores = [PAGINA_APURACAO, PAGINA_CAIXA, PAGINA_RADAR, rotulo]
        if list(self.nav.cget("values")) != valores:
            atual = self.nav.get()
            self.nav.configure(values=valores)
            self.nav.set(rotulo if atual.startswith(PAGINA_NOTICIAS) else atual)

    def atualizar_noticias(self, forcar=False):
        if self.noticias_rodando or not self.cfg["radar"]:
            return
        if not forcar and not nt.precisa_atualizar(nt.ler_estado()) and not self._radar_sem_noticias():
            return
        self.noticias_rodando = True
        self.lb_noticias_status.configure(text="Buscando notícias…", text_color=C["muted"])
        radar = [dict(r) for r in self.cfg["radar"]]
        self.bg(lambda: nt.atualizar(radar, detalhes=True), ok=self.noticias_chegaram, erro=self.noticias_erro)

    def _radar_sem_noticias(self):
        conhecidos = set(nt.ler_estado()["conhecidos"])
        return any(r["ticker"] not in conhecidos for r in self.cfg["radar"])

    def noticias_chegaram(self, res):
        self.noticias_rodando = False
        self.det_noticias = nt.ler_detalhes()
        _, novas = res
        if self.pagina == "noticias":
            self.desenhar_noticias()
            nt.marcar_lidas()
        else:
            self.status_noticias(nt.ler_estado())
        self.rotular_noticias()
        if novas and self.cfg.get("noticias_notificar", True):
            for titulo, corpo, link in nt.textos_notificacao(novas):
                notificar_windows(titulo, corpo, link)

    def noticias_erro(self, e):
        self.noticias_rodando = False
        self.lb_noticias_status.configure(text=f"Não foi possível buscar notícias: {str(e)[:120]}",
                                          text_color=C["danger"])

    def tick_noticias(self):
        try:
            self.atualizar_noticias()
        finally:
            self.after(60000, self.tick_noticias)

    def preparar_notificacoes(self):
        """Ícone estável (fora da pasta temporária do .exe) para as notificações."""
        icone = None
        try:
            origem = recurso("assets/icone_janela.png")
            if origem.exists():
                icone = DADOS / "icone_notificacao.png"
                if not icone.exists() or icone.stat().st_size != origem.stat().st_size:
                    icone.write_bytes(origem.read_bytes())
        except OSError:
            icone = None
        registrar_notificacoes(icone)

    def custodia(self):
        return {l["ticker"] for l in carregar(mes_inicial())["lotes"] if restante(l) > 0}

    def radar_lista(self):
        """Radar exibido: o do amigo selecionado em "Visualizando" ou o meu, na ordem escolhida."""
        return self.amigo_radar if self.visao else nc.ordenar_radar(self.cfg["radar"])

    def radar_redesenhar(self):
        if not hasattr(self, "lista_radar"):
            return
        amigo = self.visao
        modo = f"amigo:{amigo}" if amigo else "meu"
        if modo != self.radar_modo:  # trocou de dono: as linhas têm botões diferentes
            for card in self.radar_cards.values():
                card.destroy()
            self.radar_cards.clear()
            self.radar_modo = modo
            self.lb_radar_titulo.configure(text=f"Radar de {amigo}" if amigo else "Radar de Ações")
            if amigo:
                self.fr_radar_meu.pack_forget()
                self.bt_importar_todos.pack(side="left")
            else:
                self.bt_importar_todos.pack_forget()
                self.fr_radar_meu.pack(side="left")
        lista = self.radar_lista()
        tickers = [r["ticker"] for r in lista]
        nomes = {r["ticker"]: r.get("nome", "") for r in lista}
        meus = {r["ticker"] for r in self.cfg["radar"]}
        for t in list(self.radar_cards):
            if t not in tickers:
                self.radar_cards.pop(t).destroy()
        custodia = set() if amigo else self.custodia()
        for t in tickers:
            if t not in self.radar_cards:
                if amigo:
                    card = LinhaRadar(self.lista_radar, t, None, None, None, ao_importar=self.importar_radar)
                else:
                    card = LinhaRadar(self.lista_radar, t, self.radar_comprar, self.radar_vender, self.remover_radar,
                                      ao_arrastar=self.arrastar_radar)
                self.radar_cards[t] = card
                self.imagem("t:" + t, lambda t=t: nt.logo_png(t), TAM_LOGO,
                            lambda img, c=card: por_logo(c.lb_logo, img))
            self.radar_cards[t].set(self.radar_dados.get(t), t in custodia, nomes.get(t, ""), ja_tenho=t in meus)
        self.posicionar_linhas(tickers)
        if tickers:
            self.lb_radar_vazio.grid_forget()
        else:
            self.lb_radar_vazio.configure(text=f"{amigo} não tem ativos no radar." if amigo else
                                          "Nenhum ativo no radar. Adicione um ticker acima.")
            self.lb_radar_vazio.grid(row=0, column=0, pady=60)

    def posicionar_linhas(self, tickers, arrastado=None):
        for i, t in enumerate(tickers):
            card = self.radar_cards[t]
            cor_ = C["selecao"] if t == arrastado else (C["card"] if i % 2 == 0 else C["zebra"])
            card.configure(fg_color=cor_)
            card.grid(row=i, column=0, sticky="ew", pady=1)

    def arrastar_radar(self, fase, t, ev):
        """Arrastar pela alça ⠿: a linha acompanha o mouse e a nova ordem é gravada ao soltar."""
        if fase == "ini":
            self.arraste = {"t": t, "ordem": [r["ticker"] for r in nc.ordenar_radar(self.cfg["radar"])]}
            self.posicionar_linhas(self.arraste["ordem"], t)
            return
        if not self.arraste:
            return
        ordem = self.arraste["ordem"]
        if fase == "mov":
            y = ev.y_root
            try:
                canvas = self.lista_radar._parent_canvas
                topo, alt = canvas.winfo_rooty(), canvas.winfo_height()
                if y < topo + 30:
                    canvas.yview_scroll(-1, "units")
                elif y > topo + alt - 30:
                    canvas.yview_scroll(1, "units")
            except Exception:
                pass
            outros = [x for x in ordem if x != t]
            idx = sum(1 for x in outros
                      if self.radar_cards[x].winfo_rooty() + self.radar_cards[x].winfo_height() / 2 < y)
            nova = outros[:idx] + [t] + outros[idx:]
            if nova != ordem:
                self.arraste["ordem"] = nova
                self.posicionar_linhas(nova, t)
            return
        self.arraste = None  # soltou
        if ordem != [r["ticker"] for r in nc.ordenar_radar(self.cfg["radar"])]:
            nc.reordenar_radar(self.cfg, ordem)
            self.agendar_sync()
        self.posicionar_linhas(ordem)

    def importar_radar(self, t):
        item = next((r for r in self.amigo_radar if r["ticker"] == t), {"nome": ""})
        if nc.adicionar_radar(self.cfg, t, item.get("nome", "")) is None:
            return
        self.agendar_sync()
        self.radar_redesenhar()
        self.atualizar_noticias()

    def importar_todos_radar(self):
        novos = [r for r in self.amigo_radar if all(m["ticker"] != r["ticker"] for m in self.cfg["radar"])]
        if not novos:
            avisar(self, "Radar", "Todos os ativos do radar do amigo já estão no seu radar.")
            return
        if not confirmar(self, "Importar radar", f"Adicionar {len(novos)} ativo(s) ao seu radar: "
                         f"{', '.join(r['ticker'] for r in novos)}?", sim="Importar"):
            return
        for r in novos:
            nc.adicionar_radar(self.cfg, r["ticker"], r.get("nome", ""))
        self.agendar_sync()
        self.radar_redesenhar()
        self.atualizar_noticias()

    def adicionar_radar(self):
        t = self.en_radar.get().strip().upper()
        if t.endswith(".SA"):
            t = t[:-3]
        if not re.fullmatch(r"[A-Z0-9]{4,7}", t):
            avisar(self, "Radar", "Ticker inválido.")
            return
        if any(r["ticker"] == t for r in self.cfg["radar"]):
            avisar(self, "Radar", f"{t} já está no radar.")
            return
        nc.adicionar_radar(self.cfg, t)
        self.en_radar.delete(0, "end")
        self.agendar_sync()
        self.radar_redesenhar()
        self.atualizar_radar(apenas=[t])
        self.atualizar_noticias()

    def remover_radar(self, t):
        if not confirmar(self, "Remover do radar", f"Remover {t} do radar?", sim="Remover", perigo=True):
            return
        self.cfg["radar"] = [r for r in self.cfg["radar"] if r["ticker"] != t]
        self.radar_dados.pop(t, None)
        self.agendar_sync()
        self.radar_redesenhar()
        self.desenhar_noticias()

    def atualizar_radar(self, forcar=False, apenas=None):
        tickers = apenas or [r["ticker"] for r in self.radar_lista()]
        if not tickers:
            return
        if self.radar_rodando:
            self.radar_espera.update(tickers)
            return
        self.radar_rodando = True
        self.lb_radar_status.configure(text="Atualizando cotações…", text_color=C["muted"])
        nomes = {r["ticker"]: r.get("nome", "") for r in self.cfg["radar"] + list(self.amigo_radar)}
        mercado = self.mercado

        def trabalho():
            if forcar:
                mercado.limpar()
            for t in tickers:
                try:
                    res = mercado.dados(t, nomes.get(t, ""))
                except Exception as e:
                    res = {"ticker": t, "erro": erro_mercado(e)}
                self.fila.put((self.radar_resultado, res, None))

        self.bg(trabalho, ok=self.radar_fim, erro=self.radar_fim)

    def radar_resultado(self, res):
        t = res["ticker"]
        self.radar_dados[t] = res
        item = next((r for r in self.cfg["radar"] if r["ticker"] == t), None)
        if item is not None and res.get("nome") and not item.get("nome"):
            item["nome"] = res["nome"]
            self.agendar_sync()
        exibido = next((r for r in self.radar_lista() if r["ticker"] == t), None)
        card = self.radar_cards.get(t)
        if card and exibido is not None:
            card.set(res, not self.visao and t in self.custodia(), exibido.get("nome", ""), ja_tenho=item is not None)

    def radar_fim(self, _=None):
        self.radar_rodando = False
        self.lb_radar_status.configure(
            text=f"Atualizado às {datetime.now():%H:%M} · Yahoo Finance (atraso de até 15 min)",
            text_color=C["muted"])
        if self.radar_espera:
            pendentes = list(self.radar_espera)
            self.radar_espera.clear()
            self.atualizar_radar(apenas=pendentes)

    def tick_radar(self):
        if self.pagina == "radar" and not self.radar_rodando:
            self.atualizar_radar()
        if self.pagina == "apuracao":
            em_carteira = {l["ticker"] for l in self.d["lotes"] if restante(l) > 0}
            self.cotacoes.atualizar(em_carteira, lambda: self.fila.put((lambda _: self.atualizar(), None, None)))
        self.after(60000, self.tick_radar)

    def preparar_operacao(self):
        """Garante a visão dos próprios dados em um mês aberto."""
        if self.visao:
            self.trocar_visao("Meus dados")
        elif self.d["fechado"]:
            self.mes = mes_inicial()
            self.d = carregar(self.mes)
            self.atualizar()

    def radar_comprar(self, t):
        self.preparar_operacao()
        ini = {"ticker": t, "tipo": inferir_tipo(t, historico_tickers()[1])}
        dados = self.radar_dados.get(t) or {}
        if dados.get("preco"):
            ini["preco"] = preco_texto(dados["preco"])
        self.novo_ativo(ini)
        self.radar_redesenhar()

    def radar_vender(self, t):
        self.preparar_operacao()
        if not any(l["ticker"] == t and restante(l) > 0 for l in self.d["lotes"]):
            avisar(self, "Vender", f"Não há {t} em custódia no mês {fmt_mes(self.mes)}.")
            return
        self.registrar_venda(ticker=t)
        self.radar_redesenhar()

    # --- atualização
    def verificar_atualizacao(self):
        self.bg(upd.verificar, ok=self.oferecer_atualizacao, erro=lambda e: None)

    def oferecer_atualizacao(self, info):
        if not info:
            return
        notas = info["notas"]
        if len(notas) > 600:
            notas = notas[:600].rstrip() + "…"
        texto = f"A versão {info['versao']} está disponível. Você está usando a {VERSAO}."
        if notas:
            texto += f"\n\nNovidades:\n{notas}"
        if confirmar(self, "Nova versão disponível", texto, sim="Atualizar", nao="Depois"):
            DialogoAtualizacao(self, info)

    # --- tarefas em segundo plano
    def bg(self, func, ok=None, erro=None):
        def rodar():
            try:
                self.fila.put((ok, func(), None))
            except Exception as e:
                self.fila.put((erro, None, e))
        threading.Thread(target=rodar, daemon=True).start()

    def processar_fila(self):
        # agenda a próxima rodada antes de executar os callbacks: um callback que abre uma janela modal
        # (ex.: aviso de atualização) bloqueia aqui, e a fila precisa continuar sendo processada
        try:
            self.after(100, self.processar_fila)
        except Exception:
            return
        try:
            while True:
                cb, res, exc = self.fila.get_nowait()
                if cb:
                    cb(exc if exc is not None else res)
        except queue.Empty:
            pass

    # --- conta Google
    def status_sync(self, estado):
        textos = {
            "off": ("○ Google não conectado", C["muted"]),
            "login": ("◌ Aguardando login no navegador…", C["aviso"]),
            "sync": ("◌ Sincronizando…", C["muted"]),
            "ok": ("● Sincronizado", C["accent"]),
            "pendente": ("● Alterações pendentes", C["aviso"]),
            "offline": ("● Sem conexão · será enviado depois", C["aviso"]),
            "erro": ("● Erro ao sincronizar", C["danger"]),
        }
        txt, c = textos[estado]
        if estado == "ok" and self.ultima_sync:
            txt += f" às {self.ultima_sync:%H:%M}"
        self.lb_sync.configure(text=txt, text_color=c)

    def atualizar_conta(self):
        if self.g.email:
            e = self.g.email
            self.bt_conta.configure(text=e if len(e) <= 26 else e[:24] + "…")
        else:
            self.bt_conta.configure(text="Conectar Google")
        self.seletores("configure", values=["Meus dados"] + [a["email"] for a in self.cfg["amigos"]])

    def conectar_token(self):
        self.carregando_token = True
        self.status_sync("sync")
        self.bg(self.g.carregar_token, ok=self.pos_login, erro=self.erro_token)

    def erro_token(self, e):
        self.carregando_token = False
        if isinstance(e, gs.Offline):
            self.status_sync("offline")
        else:
            if isinstance(e, gs.LoginNecessario):
                self.g.sair()
            self.status_sync("off")
        self.atualizar_conta()

    def clicar_conta(self):
        if self.g.email:
            self.menu_conta()
            return
        if not self.g.tem_credencial():
            avisar(self, "Credencial não encontrada",
                   "Coloque o arquivo credentials.json na mesma pasta do programa "
                   "ou gere o .exe com ele na pasta.")
            return
        self.bt_conta.configure(state="disabled")
        self.status_sync("login")
        self.bg(self.g.login, ok=self.pos_login, erro=self.erro_login)

    def erro_login(self, e):
        self.bt_conta.configure(state="normal")
        self.status_sync("off")
        avisar(self, "Login não concluído", str(e) or "Não foi possível entrar com o Google.")

    def pos_login(self, _=None):
        self.carregando_token = False
        self.bt_conta.configure(state="normal")
        self.atualizar_conta()
        self.status_sync("sync")
        email = self.g.email
        sid = self.cfg["planilhas"].get(email)

        def preparar():
            atual = sid
            if atual and not self.g.planilha_existe(atual):
                atual = None
            if not atual:
                atual = self.g.buscar_planilha("me")
            if not atual:
                atual = self.g.criar_planilha()
            return email, atual

        self.bg(preparar, ok=self.pos_preparar, erro=self.erro_sync)

    def pos_preparar(self, res):
        email, sid = res
        if email != self.g.email:
            return
        self.cfg["planilhas"][email] = sid
        gravar_config(self.cfg)
        self.sincronizar()

    def menu_conta(self):
        sid = self.cfg["planilhas"].get(self.g.email)
        info = f"Planilha \"{gs.NOME_PLANILHA}\" no seu Google Drive."
        if self.ultimo_erro:
            info += f"\n\nÚltimo erro: {self.ultimo_erro}"
        m = Mensagem(self, self.g.email, info, [
            ("Sair da conta", "sair", "perigo"), ("Abrir planilha", "abrir", "neutro"),
            ("Sincronizar agora", "sync", "accent")])
        if m.resultado == "abrir" and sid:
            webbrowser.open(f"https://docs.google.com/spreadsheets/d/{sid}")
        elif m.resultado == "sync":
            self.cfg["pendente"] = True
            gravar_config(self.cfg)
            if sid:
                self.sincronizar()
            else:
                self.pos_login()
        elif m.resultado == "sair":
            if confirmar(self, "Sair da conta", "Os dados continuam salvos neste computador e na planilha.",
                         sim="Sair", perigo=True):
                self.g.sair()
                self.visao = None
                self.dados_amigo = {}
                self.amigo_radar, self.amigo_caixa = [], None
                self.d = carregar(self.mes)
                self.atualizar()
                self.atualizar_conta()
                self.visao_mudou()
                self.status_sync("off")

    # --- sincronização
    def agendar_sync(self):
        self.cfg["pendente"] = True
        gravar_config(self.cfg)
        if not self.g.email:
            return
        self.status_sync("pendente")
        if self.sync_job:
            self.after_cancel(self.sync_job)
        self.sync_job = self.after(1500, self.disparar_sync)

    def disparar_sync(self):
        self.sync_job = None
        self.sincronizar()

    def sincronizar(self):
        if not self.g.email:
            return
        if self.sync_rodando:
            self.resync = True
            return
        sid = self.cfg["planilhas"].get(self.g.email)
        if not sid:
            return
        self.sync_rodando = True
        self.resync = False
        self.status_sync("sync")
        self.bg(lambda: (sid, self.g.ler(sid)), ok=self.mesclar_e_enviar, erro=self.erro_sync)

    def mesclar_e_enviar(self, res):
        try:
            if self.grab_current() is not None:  # há uma janela aberta: espera para não mudar dados sob ela
                self.after(2000, lambda: self.mesclar_e_enviar(res))
                return
        except Exception:
            pass
        sid, abas = res
        mudou = nc.mesclar_tudo(reconstruir(abas), self.cfg)
        if mudou:
            if not self.visao:
                self.d = carregar(self.mes)
                self.atualizar()
            self.atualizar_conta()
            self.atualizar_caixa()
            if self.pagina == "radar":
                self.radar_redesenhar()
        dados = montar_linhas(listar_meses(), self.cfg)
        self.bg(lambda: self.g.escrever(sid, dados), ok=self.sync_ok, erro=self.erro_sync)

    def sync_ok(self, _):
        self.sync_rodando = False
        self.ultimo_erro = ""
        self.ultima_puxada = datetime.now()
        if self.resync:
            self.sincronizar()
            return
        self.cfg["pendente"] = False
        gravar_config(self.cfg)
        self.ultima_sync = datetime.now()
        self.status_sync("ok")

    def erro_sync(self, e):
        self.sync_rodando = False
        self.carregando_token = False
        self.bt_conta.configure(state="normal")
        if isinstance(e, gs.LoginNecessario):
            self.g.sair()
            self.atualizar_conta()
            self.status_sync("off")
            avisar(self, "Sessão expirada", "Conecte sua conta Google novamente.")
        elif isinstance(e, gs.Offline):
            self.status_sync("offline")
        else:
            if getattr(e, "status", 0) == 404 and self.g.email:
                self.cfg["planilhas"].pop(self.g.email, None)
                gravar_config(self.cfg)
            self.ultimo_erro = str(e)
            self.status_sync("erro")

    def tick_sync(self):
        if self.g.email:
            atrasada = (datetime.now() - self.ultima_puxada).total_seconds() > 300
            if (self.cfg["pendente"] or atrasada) and not self.sync_rodando:
                if self.cfg["planilhas"].get(self.g.email):
                    self.sincronizar()
                else:
                    self.pos_login()
        elif self.g.tem_token() and not self.carregando_token:
            self.conectar_token()
        self.after(60000, self.tick_sync)

    # --- amigos
    def abrir_amigos(self):
        if not self.g.email:
            avisar(self, "Amigos", "Conecte sua conta Google para adicionar amigos.")
            return
        if not self.cfg["planilhas"].get(self.g.email):
            avisar(self, "Amigos", "Aguarde a criação da sua planilha no Google Drive e tente novamente.")
            return
        d = DialogoAmigos(self)
        if d.resultado:
            self.trocar_visao(d.resultado)

    def trocar_visao(self, rotulo):
        if rotulo == "Meus dados":
            self.visao = None
            self.dados_amigo = {}
            self.amigo_radar, self.amigo_caixa = [], None
            self.mes = mes_inicial()
            self.d = carregar(self.mes)
            self.atualizar()
            self.visao_mudou()
            return
        if not self.g.email:
            self.seletores("set", self.visao or "Meus dados")
            avisar(self, "Amigos", "Conecte sua conta Google para ver os dados dos amigos.")
            return
        email = rotulo
        self.seletores("configure", state="disabled")
        self.lb_sub.configure(text=f"Carregando dados de {email}…", text_color=C["muted"])

        def carregar_amigo():
            sid = self.g.buscar_planilha(email)
            if not sid:
                raise gs.ErroGoogle(f"{email} ainda não compartilhou a planilha com você. "
                                    f"Peça para ele adicionar {self.g.email} em Amigos.")
            meses, _, radar, _, caixa = reconstruir(self.g.ler(sid))
            return meses, nc.ordenar_radar(radar), caixa

        self.bg(carregar_amigo, ok=lambda res: self.amigo_ok(email, *res),
                erro=self.amigo_erro)

    def seletor_visao(self, pai, largura=280):
        om = ctk.CTkOptionMenu(pai, values=["Meus dados"] + [a["email"] for a in self.cfg.get("amigos", [])],
                               command=self.trocar_visao, width=largura, height=36, font=F(13, "bold"),
                               dropdown_font=F(13), corner_radius=8, fg_color=C["neutro"], button_color=C["neutro_h"],
                               button_hover_color=C["borda"], text_color=C["texto"])
        om.set(self.visao or "Meus dados")
        self.lista_seletores.append(om)
        return om

    def seletores(self, metodo, *a, **kw):
        """Aplica a mesma alteração em todos os seletores "Visualizando" (Apuração, Caixa e Radar)."""
        for om in self.lista_seletores:
            getattr(om, metodo)(*a, **kw)

    def visao_mudou(self):
        self.seletores("set", self.visao or "Meus dados")
        self.atualizar_caixa()
        self.radar_redesenhar()
        if self.pagina == "radar":
            self.atualizar_radar()

    def recarregar_amigo(self):
        if self.visao:
            self.trocar_visao(self.visao)

    def amigo_ok(self, email, meses, radar=None, caixa=None):
        self.seletores("configure", state="normal")
        trocou = self.visao != email
        self.visao = email
        self.dados_amigo = meses
        self.amigo_radar = radar or []
        self.amigo_caixa = caixa
        if trocou or self.mes not in meses:
            abertos = sorted(m for m, d in meses.items() if not d["fechado"])
            self.mes = abertos[0] if abertos else (max(meses) if meses else date.today().strftime("%Y-%m"))
        self.d = meses.get(self.mes) or mes_vazio(self.mes)
        self.atualizar()
        self.visao_mudou()

    def amigo_erro(self, e):
        self.seletores("configure", state="normal")
        self.atualizar()
        if isinstance(e, gs.Offline):
            msg = "Sem conexão com a internet."
        else:
            msg = str(e)
        avisar(self, "Não foi possível carregar", msg)


class DialogoAtualizacao(Janela):
    def __init__(self, app, info):
        super().__init__(app, "Atualizando")
        self.app = app
        self.cancelado = False
        ctk.CTkLabel(self.caixa, text=f"Atualizando para a versão {info['versao']}", font=F(17, "bold"),
                     text_color=C["texto"]).pack(anchor="w", padx=22, pady=(20, 6))
        self.lb = ctk.CTkLabel(self.caixa, text="Baixando…", font=F(13), text_color=C["muted"], width=380,
                               anchor="w")
        self.lb.pack(anchor="w", padx=22)
        self.pb = ctk.CTkProgressBar(self.caixa, height=10, corner_radius=5, fg_color=C["neutro"],
                                     progress_color=C["accent"], width=380)
        self.pb.set(0)
        self.pb.pack(fill="x", padx=22, pady=(10, 0))
        barra = ctk.CTkFrame(self.caixa, fg_color="transparent")
        barra.pack(fill="x", padx=22, pady=(18, 20))
        self.bt = botao(barra, "Cancelar", self.cancelar, "neutro", width=110)
        self.bt.pack(side="right")
        self.protocol("WM_DELETE_WINDOW", self.cancelar)

        def progresso(b, t):
            if self.cancelado:
                raise upd.ErroAtualizacao("Atualização cancelada.")
            app.fila.put((self.progresso, (b, t), None))

        app.bg(lambda: upd.baixar(info, progresso), ok=self.baixado, erro=self.falha)
        self.mostrar()

    def progresso(self, bt):
        b, t = bt
        if not self.winfo_exists():
            return
        mb = 1024 * 1024
        if t:
            self.pb.set(min(b / t, 1))
            self.lb.configure(text=f"Baixando… {b / mb:.1f} de {t / mb:.1f} MB".replace(".", ","))
        else:
            self.lb.configure(text=f"Baixando… {b / mb:.1f} MB".replace(".", ","))

    def baixado(self, novo):
        if self.cancelado:
            return
        self.lb.configure(text="Instalando. O app será reaberto em alguns segundos…")
        self.pb.set(1)
        self.bt.configure(state="disabled")
        try:
            upd.instalar_e_reiniciar(novo)
        except Exception as e:
            self.falha(e)
            return
        self.app.after(500, self.app.destroy)

    def falha(self, e):
        if self.cancelado or not self.winfo_exists():
            return
        self.lb.configure(text=f"Não foi possível atualizar: {e}", text_color=C["danger"])
        self.bt.configure(text="Fechar", command=self.destroy, state="normal")
        self.protocol("WM_DELETE_WINDOW", self.destroy)

    def cancelar(self):
        self.cancelado = True
        self.destroy()


class DialogoAmigos(Janela):
    def __init__(self, app):
        super().__init__(app, "Amigos")
        self.app = app
        ctk.CTkLabel(self.caixa, text="Amigos", font=F(18, "bold"), text_color=C["texto"]).pack(
            anchor="w", padx=24, pady=(22, 0))
        ctk.CTkLabel(self.caixa, text="Ao adicionar um amigo, sua planilha é compartilhada com ele somente para "
                                      "leitura. Para ver os dados dele, ele também precisa adicionar você.",
                     font=F(12), text_color=C["muted"], wraplength=420, justify="left").pack(anchor="w", padx=24)

        linha = ctk.CTkFrame(self.caixa, fg_color="transparent")
        linha.pack(fill="x", padx=24, pady=(16, 0))
        self.en = ctk.CTkEntry(linha, height=38, font=F(13), corner_radius=8, border_color=C["borda"],
                               fg_color=C["card2"], text_color=C["texto"], placeholder_text="email@gmail.com")
        self.en.pack(side="left", fill="x", expand=True)
        self.bt_add = botao(linha, "Adicionar", self.adicionar, "accent", width=110)
        self.bt_add.pack(side="left", padx=(8, 0))

        self.lb_status = ctk.CTkLabel(self.caixa, text="", font=F(12), text_color=C["muted"],
                                      wraplength=420, justify="left")
        self.lb_status.pack(anchor="w", padx=24, pady=(8, 0))

        self.lista = ctk.CTkScrollableFrame(self.caixa, width=420, height=230, fg_color=C["card2"],
                                            corner_radius=10)
        self.lista.pack(fill="both", padx=24, pady=(8, 0))

        barra = ctk.CTkFrame(self.caixa, fg_color="transparent")
        barra.pack(fill="x", padx=24, pady=(14, 22))
        botao(barra, "Fechar", self.destroy, "neutro", width=110).pack(side="right")

        self.bind("<Return>", lambda e: self.adicionar())
        self.bind("<Escape>", lambda e: self.destroy())
        self.after(150, self.en.focus_set)
        self.desenhar()
        self.mostrar()

    def desenhar(self):
        for w in self.lista.winfo_children():
            w.destroy()
        amigos = self.app.cfg["amigos"]
        if not amigos:
            ctk.CTkLabel(self.lista, text="Nenhum amigo adicionado.", font=F(13),
                         text_color=C["muted"]).pack(pady=20)
            return
        for a in amigos:
            f = ctk.CTkFrame(self.lista, fg_color=C["card"], corner_radius=8)
            f.pack(fill="x", pady=4, padx=4)
            txt = ctk.CTkFrame(f, fg_color="transparent")
            txt.pack(side="left", padx=12, pady=8)
            ctk.CTkLabel(txt, text=a["email"], font=F(13, "bold"), text_color=C["texto"]).pack(anchor="w")
            ctk.CTkLabel(txt, text=f"Adicionado em {fmt_data(a['desde'])}", font=F(11),
                         text_color=C["muted"]).pack(anchor="w")
            botao(f, "Remover", lambda e=a["email"]: self.remover(e), "perigo", width=90).pack(
                side="right", padx=(4, 10))
            botao(f, "Ver", lambda e=a["email"]: self.ver(e), "neutro", width=60).pack(side="right")

    def ocupado(self, sim, texto="", cor_txt=None):
        self.bt_add.configure(state="disabled" if sim else "normal")
        self.lb_status.configure(text=texto, text_color=cor_txt or C["muted"])

    def sid(self):
        return self.app.cfg["planilhas"].get(self.app.g.email)

    def adicionar(self):
        email = self.en.get().strip().lower()
        if not re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", email):
            self.ocupado(False, "E-mail inválido.", C["danger"])
            return
        if email == self.app.g.email:
            self.ocupado(False, "Esse é o seu próprio e-mail.", C["danger"])
            return
        if any(a["email"] == email for a in self.app.cfg["amigos"]):
            self.ocupado(False, "Esse amigo já foi adicionado.", C["danger"])
            return
        self.ocupado(True, "Compartilhando sua planilha…")
        sid = self.sid()
        self.app.bg(lambda: self.app.g.compartilhar(sid, email),
                    ok=lambda _: self.adicionado(email), erro=self.falha)

    def adicionado(self, email):
        self.app.cfg["amigos"].append({"email": email, "desde": date.today().isoformat()})
        self.app.atualizar_conta()
        self.app.agendar_sync()
        if self.winfo_exists():
            self.en.delete(0, "end")
            self.ocupado(False, f"Planilha compartilhada com {email}.", C["accent"])
            self.desenhar()

    def remover(self, email):
        if not confirmar(self, "Remover amigo",
                         f"{email} deixará de ter acesso à sua planilha.", sim="Remover", perigo=True):
            return
        self.ocupado(True, "Removendo acesso…")
        sid = self.sid()
        self.app.bg(lambda: self.app.g.descompartilhar(sid, email),
                    ok=lambda _: self.removido(email), erro=self.falha)

    def removido(self, email):
        self.app.cfg["amigos"] = [a for a in self.app.cfg["amigos"] if a["email"] != email]
        self.app.atualizar_conta()
        self.app.agendar_sync()
        if self.app.visao == email:
            self.app.trocar_visao("Meus dados")
        if self.winfo_exists():
            self.ocupado(False, f"Acesso de {email} removido.", C["accent"])
            self.desenhar()

    def falha(self, e):
        msg = "Sem conexão com a internet." if isinstance(e, gs.Offline) else str(e)
        if self.winfo_exists():
            self.ocupado(False, msg, C["danger"])

    def ver(self, email):
        self.resultado = email
        self.destroy()


if __name__ == "__main__":
    App().mainloop()
