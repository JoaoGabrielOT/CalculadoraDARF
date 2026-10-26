import calendar
import json
import queue
import re
import sys
import threading
import uuid
import webbrowser
from collections import Counter, defaultdict
from datetime import date, datetime, timedelta
from pathlib import Path
from tkinter import ttk

import customtkinter as ctk

import atualizador as upd
import google_sync as gs
import nucleo as nc
import mercado as mk
from componentes import CampoData, SeletorMes
from tema import C, F, FONTE, botao, cor, estilo_botao
from nucleo import (DARF_MINIMO, LIMITE_ISENCAO, apurar, brl, carregar, fmt_data, fmt_mes, gravar_config,
                    historico_tickers, inferir_tipo, ler_config, limites_mes, listar_meses, mes_inicial, mes_vazio,
                    montar_linhas, parse_num, parse_qtd, preco_texto, proximo_mes, reconstruir, restante, salvar,
                    status_lote, vendido)
from versao import VERSAO

PAGINA_APURACAO = "Apuração / DARF"
PAGINA_RADAR = "Radar de Ações"

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


class FormCompra(FormBase):
    def __init__(self, master, sugestoes, tipos, iniciais=None):
        ini = iniciais or {}
        super().__init__(master, "Novo ativo", "Dados da compra")
        self.tipos = tipos
        self.rotulo("TICKER")
        self.en_ticker = self.entrada("Ex.: PETR4", ini.get("ticker", ""))
        self.en_ticker.bind("<KeyRelease>", lambda e: self.ticker_digitado())
        self.chips(sugestoes, self.escolher)
        self.rotulo("TIPO")
        self.seg_tipo = ctk.CTkSegmentedButton(self.caixa, values=["Ação", "BDR"], height=36, font=F(13),
                                               selected_color=C["accent"], selected_hover_color=C["accent_h"])
        self.seg_tipo.set(ini.get("tipo") or "Ação")
        self.seg_tipo.pack(fill="x", padx=24)
        self.rotulo("DATA DA COMPRA")
        self.data = CampoData(self.caixa, valor=date.today(), maximo=date.today())
        self.data.pack(fill="x", padx=24)
        self.rotulo("QUANTIDADE")
        self.en_qtd = self.entrada("Ex.: 100", ini.get("qtd", ""))
        self.rotulo("PREÇO UNITÁRIO (R$)")
        self.en_preco = self.entrada("Ex.: 32,50", ini.get("preco", ""))
        self.rodape()
        if ini.get("ticker"):
            self.marcar_chip(ini["ticker"])
        foco = self.en_qtd if ini.get("ticker") else self.en_ticker
        self.after(150, foco.focus_set)
        self.mostrar()

    def escolher(self, t):
        self.en_ticker.delete(0, "end")
        self.en_ticker.insert(0, t)
        self.seg_tipo.set(inferir_tipo(t, self.tipos))
        self.marcar_chip(t)
        self.en_qtd.focus_set()

    def ticker_digitado(self):
        t = self.en_ticker.get().strip().upper()
        self.marcar_chip(t)
        if len(t) >= 5:
            self.seg_tipo.set(inferir_tipo(t, self.tipos))

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
        self.resultado = {"ticker": ticker, "tipo": self.seg_tipo.get(), "data_compra": dc.isoformat(),
                          "qtd": q, "preco": p}
        self.destroy()


class FormVenda(FormBase):
    def __init__(self, master, d, sugestoes, lote_inicial=None, ticker_inicial=""):
        super().__init__(master, "Registrar venda", f"Mês {fmt_mes(d['mes'])}")
        self.abertos = [l for l in d["lotes"] if restante(l) > 0]
        self.inicio_mes, self.fim_mes = limites_mes(d["mes"])
        self.opcoes = {}
        self.lote = None
        self.ticker_atual = None

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
        self.data = CampoData(self.caixa, minimo=self.inicio_mes, maximo=min(self.fim_mes, date.today()))
        self.data.pack(fill="x", padx=24)
        self.lb_qtd = self.rotulo("QUANTIDADE")
        self.en_qtd = self.entrada()
        self.rotulo("PREÇO UNITÁRIO (R$)")
        self.en_preco = self.entrada("Ex.: 35,10")
        self.rodape()

        t = lote_inicial["ticker"] if lote_inicial else ticker_inicial
        self.selecionar_ticker(t or "", lote_inicial=lote_inicial)
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
        self.tv = ttk.Treeview(self, columns=[c[0] for c in colunas], show="headings",
                               selectmode="browse", style="D.Treeview")
        for chave, titulo, larg, ancora in colunas:
            kw = {"command": lambda c=chave: self.ordenar(c)} if chave in self.ordenaveis else {}
            self.tv.heading(chave, text=titulo, anchor=ancora, **kw)
            self.tv.column(chave, width=larg, minwidth=60, anchor=ancora)
        sb = ctk.CTkScrollbar(self, command=self.tv.yview)
        self.tv.configure(yscrollcommand=sb.set)
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
        for i, (iid, valores, tags, _) in enumerate(linhas):
            self.tv.insert("", "end", iid=iid, values=valores, tags=("impar" if i % 2 else "par", *tags))
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

    def aplicar_cores(self):
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
    def __init__(self, pai, ticker, ao_comprar, ao_vender, ao_remover):
        super().__init__(pai, fg_color=C["card"], corner_radius=8)
        self.ticker = ticker
        colunas_radar(self)
        ativo = ctk.CTkFrame(self, fg_color="transparent")
        ativo.grid(row=0, column=0, sticky="w", padx=12, pady=8)
        ctk.CTkLabel(ativo, text=ticker, font=F(14, "bold"), text_color=C["texto"], anchor="w").pack(anchor="w")
        self.lb_nome = ctk.CTkLabel(ativo, text="", font=F(11), text_color=C["muted"], anchor="w", justify="left",
                                    wraplength=220)
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
        botao(acoes, "Comprar", lambda: ao_comprar(ticker), "accent", altura=30, fonte=12, width=74).pack(side="left")
        self.bt_vender = botao(acoes, "Vender", lambda: ao_vender(ticker), "neutro", altura=30, fonte=12, width=74)
        self.bt_vender.pack(side="left", padx=6)
        botao(acoes, "Remover", lambda: ao_remover(ticker), "perigo", altura=30, fonte=12, width=74).pack(side="left")

    def limpar(self):
        for v in self.vals.values():
            v.configure(text="—")
        self.badge.configure(text="", fg_color="transparent")

    def set(self, dados, pode_vender, nome=""):
        self.bt_vender.configure(state="normal" if pode_vender else "disabled")
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
        self.sync_rodando = False
        self.resync = False
        self.sync_job = None
        self.carregando_token = False
        self.ultima_sync = None
        self.ultima_puxada = datetime.now()
        self.ultimo_erro = ""
        self.mercado = mk.Mercado()
        self.radar_dados = {}
        self.radar_cards = {}
        self.radar_rodando = False
        self.radar_espera = set()
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
        self.estilizar_tabelas()
        self.atualizar()
        self.atualizar_conta()
        self.status_sync("off")

        self.after(100, self.processar_fila)
        self.after(60000, self.tick_sync)
        self.after(60000, self.tick_radar)
        if upd.pode_atualizar():
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

        self.nav = ctk.CTkSegmentedButton(h, values=[PAGINA_APURACAO, PAGINA_RADAR], command=self.trocar_pagina,
                                          height=38, font=F(13, "bold"), corner_radius=10,
                                          fg_color=C["neutro"], selected_color=C["accent"],
                                          selected_hover_color=C["accent_h"], unselected_color=C["neutro"],
                                          unselected_hover_color=C["neutro_h"], text_color=C["texto"])
        self.nav.set(PAGINA_APURACAO)
        self.nav.grid(row=0, column=1)

        conta = ctk.CTkFrame(h, fg_color="transparent")
        conta.grid(row=0, column=2, sticky="e")
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
        self.om_visao = ctk.CTkOptionMenu(barra, values=["Meus dados"], command=self.trocar_visao, width=280,
                                          height=36, font=F(13, "bold"), dropdown_font=F(13), corner_radius=8,
                                          fg_color=C["neutro"], button_color=C["neutro_h"],
                                          button_hover_color=C["borda"], text_color=C["texto"])
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
        self.bt_venda = botao(top[0], "Registrar venda", lambda: self.registrar_venda(), "neutro", width=140)
        self.bt_venda.pack(side="right", padx=8)
        self.bt_novo = botao(top[0], "+  Novo ativo", lambda: self.novo_ativo(), "accent", width=140)
        self.bt_novo.pack(side="right")
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
            ("qtd", "QTD", 70, "e"), ("preco", "PREÇO", 110, "e"), ("total", "TOTAL", 130, "e"),
            ("vendida", "VENDIDA", 80, "e"), ("restante", "RESTANTE", 85, "e"), ("status", "SITUAÇÃO", 130, "center")],
            "Nenhum ativo neste mês. Clique em  +  Novo ativo  para começar.",
            ordenaveis=("ticker", "data", "qtd", "preco", "total", "restante"))
        self.t_lotes.pack(fill="both", expand=True, padx=16, pady=(0, 16))
        self.t_lotes.tv.bind("<Double-1>", lambda e: self.registrar_venda())

        # vendas
        c2 = self.card(corpo)
        c2.grid(row=1, column=0, sticky="nsew", pady=(8, 0))
        top = self.topo_card(c2, "Vendas do mês")
        self.lb_qtd_vendas = top[1]
        self.bt_excluir_venda = botao(top[0], "Excluir venda", self.excluir_venda, "perigo", width=120)
        self.bt_excluir_venda.pack(side="right")
        self.t_vendas = Tabela(c2, [
            ("ticker", "TICKER", 80, "w"), ("tipo", "TIPO", 60, "w"), ("data", "VENDA", 95, "center"),
            ("qtd", "QTD", 60, "e"), ("preco", "PREÇO", 100, "e"), ("regime", "OPERAÇÃO", 120, "center"),
            ("taxas", "TAXAS B3", 90, "e"), ("bruto", "LUCRO BRUTO", 115, "e"),
            ("liquido", "APÓS TAXAS", 115, "e"), ("imposto", "IMPOSTO", 100, "e")],
            "Nenhuma venda registrada neste mês.",
            ordenaveis=("ticker", "data", "qtd", "preco", "taxas", "bruto", "liquido", "imposto"))
        self.t_vendas.pack(fill="both", expand=True, padx=16, pady=(0, 16))

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
        for t in (self.t_lotes, self.t_vendas):
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
        self.agendar_sync()

    def atualizar(self):
        if self.visao:
            self.lb_sub.configure(text=f"Dados de {self.visao} · somente leitura", text_color=C["aviso"])
        else:
            self.lb_sub.configure(text="Ações e BDRs · apuração mensal de IR", text_color=C["muted"])
        self.bt_mes.configure(text=f"{fmt_mes(self.mes)}  ▾")
        self.om_visao.set(self.visao or "Meus dados")
        self.bt_recarregar.configure(state="normal" if self.visao else "disabled")

        fechado = self.d["fechado"]
        if self.visao:
            self.badge.configure(text="Somente leitura", fg_color=C["neutro"], text_color=C["aviso"])
        elif fechado:
            self.badge.configure(text="Fechado", fg_color=C["neutro"], text_color=C["muted"])
        else:
            self.badge.configure(text="● Aberto", fg_color=C["accent_bg"], text_color=C["accent"])
        estado = "disabled" if (fechado or self.visao) else "normal"
        for b in (self.bt_novo, self.bt_venda, self.bt_excluir_lote, self.bt_excluir_venda, self.bt_fechar):
            b.configure(state=estado)

        linhas = []
        for l in self.d["lotes"]:
            st = status_lote(l)
            tags = ("muted",) if st == "Vendido" else ()
            linhas.append((l["id"], (l["ticker"], l["tipo"], fmt_data(l["data_compra"]), l["qtd"],
                                     brl(l["preco"]), brl(l["qtd"] * l["preco"]), vendido(l),
                                     restante(l), st), tags,
                           {"ticker": l["ticker"], "data": l["data_compra"], "qtd": l["qtd"], "preco": l["preco"],
                            "total": l["qtd"] * l["preco"], "restante": restante(l)}))
        self.t_lotes.preencher(linhas)
        self.contar_lotes()

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
        self.nav.set(rotulo)
        if rotulo == PAGINA_RADAR:
            self.pg_apuracao.grid_remove()
            self.pg_radar.grid(row=1, column=0, sticky="nsew")
            self.pagina = "radar"
            self.radar_redesenhar()
            self.atualizar_radar()
        else:
            self.pg_radar.grid_remove()
            self.pg_apuracao.grid(row=1, column=0, sticky="nsew")
            self.pagina = "apuracao"

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
        ctk.CTkLabel(esq, text="Radar de Ações", font=F(18, "bold"), text_color=C["texto"]).pack(anchor="w")
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
        self.en_radar = ctk.CTkEntry(dir_, width=200, height=38, font=F(13), corner_radius=8,
                                     border_color=C["borda"], fg_color=C["card2"], text_color=C["texto"],
                                     placeholder_text="Ticker (ex.: VALE3)")
        self.en_radar.pack(side="left")
        self.en_radar.bind("<Return>", lambda e: self.adicionar_radar())
        botao(dir_, "+  Adicionar", self.adicionar_radar, "accent", width=120).pack(side="left", padx=8)
        botao(dir_, "Atualizar", lambda: self.atualizar_radar(forcar=True), "neutro", width=100).pack(side="left")

        lista = self.card(pg)
        lista.grid(row=1, column=0, sticky="nsew", padx=24, pady=(0, 24))
        cabecalho_radar(lista).pack(fill="x", padx=(16, 30), pady=(16, 4))
        self.lista_radar = ctk.CTkScrollableFrame(lista, fg_color="transparent")
        self.lista_radar.pack(fill="both", expand=True, padx=(10, 10), pady=(0, 12))
        self.lista_radar.grid_columnconfigure(0, weight=1)
        self.lb_radar_vazio = ctk.CTkLabel(self.lista_radar, text="Nenhum ativo no radar. Adicione um ticker acima.",
                                           font=F(13), text_color=C["muted"])

    def custodia(self):
        return {l["ticker"] for l in carregar(mes_inicial())["lotes"] if restante(l) > 0}

    def radar_redesenhar(self):
        tickers = [r["ticker"] for r in self.cfg["radar"]]
        nomes = {r["ticker"]: r.get("nome", "") for r in self.cfg["radar"]}
        for t in list(self.radar_cards):
            if t not in tickers:
                self.radar_cards.pop(t).destroy()
        custodia = self.custodia()
        for i, t in enumerate(tickers):
            card = self.radar_cards.get(t)
            if card is None:
                card = self.radar_cards[t] = LinhaRadar(self.lista_radar, t, self.radar_comprar, self.radar_vender,
                                                        self.remover_radar)
            card.configure(fg_color=C["card"] if i % 2 == 0 else C["zebra"])
            card.grid(row=i, column=0, sticky="ew", pady=1)
            card.set(self.radar_dados.get(t), t in custodia, nomes.get(t, ""))
        if tickers:
            self.lb_radar_vazio.grid_forget()
        else:
            self.lb_radar_vazio.grid(row=0, column=0, pady=60)

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
        self.cfg["radar"].append({"ticker": t, "nome": "", "desde": date.today().isoformat()})
        self.en_radar.delete(0, "end")
        self.agendar_sync()
        self.radar_redesenhar()
        self.atualizar_radar(apenas=[t])

    def remover_radar(self, t):
        if not confirmar(self, "Remover do radar", f"Remover {t} do radar?", sim="Remover", perigo=True):
            return
        self.cfg["radar"] = [r for r in self.cfg["radar"] if r["ticker"] != t]
        self.radar_dados.pop(t, None)
        self.agendar_sync()
        self.radar_redesenhar()

    def atualizar_radar(self, forcar=False, apenas=None):
        tickers = apenas or [r["ticker"] for r in self.cfg["radar"]]
        if not tickers:
            return
        if self.radar_rodando:
            self.radar_espera.update(tickers)
            return
        self.radar_rodando = True
        self.lb_radar_status.configure(text="Atualizando cotações…", text_color=C["muted"])
        nomes = {r["ticker"]: r.get("nome", "") for r in self.cfg["radar"]}
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
        if not any(r["ticker"] == t for r in self.cfg["radar"]):
            return
        self.radar_dados[t] = res
        item = next(r for r in self.cfg["radar"] if r["ticker"] == t)
        if res.get("nome") and not item.get("nome"):
            item["nome"] = res["nome"]
            self.agendar_sync()
        card = self.radar_cards.get(t)
        if card:
            card.set(res, t in self.custodia(), item.get("nome", ""))

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
        try:
            while True:
                cb, res, exc = self.fila.get_nowait()
                if cb:
                    cb(exc if exc is not None else res)
        except queue.Empty:
            pass
        self.after(100, self.processar_fila)

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
        self.om_visao.configure(values=["Meus dados"] + [a["email"] for a in self.cfg["amigos"]])

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
                self.d = carregar(self.mes)
                self.atualizar()
                self.atualizar_conta()
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
            self.mes = mes_inicial()
            self.d = carregar(self.mes)
            self.atualizar()
            return
        if not self.g.email:
            self.om_visao.set(self.visao or "Meus dados")
            avisar(self, "Amigos", "Conecte sua conta Google para ver os dados dos amigos.")
            return
        email = rotulo
        self.om_visao.configure(state="disabled")
        self.lb_sub.configure(text=f"Carregando dados de {email}…", text_color=C["muted"])

        def carregar_amigo():
            sid = self.g.buscar_planilha(email)
            if not sid:
                raise gs.ErroGoogle(f"{email} ainda não compartilhou a planilha com você. "
                                    f"Peça para ele adicionar {self.g.email} em Amigos.")
            return reconstruir(self.g.ler(sid))[0]

        self.bg(carregar_amigo, ok=lambda meses: self.amigo_ok(email, meses),
                erro=self.amigo_erro)

    def recarregar_amigo(self):
        if self.visao:
            self.trocar_visao(self.visao)

    def amigo_ok(self, email, meses):
        self.om_visao.configure(state="normal")
        trocou = self.visao != email
        self.visao = email
        self.dados_amigo = meses
        if trocou or self.mes not in meses:
            abertos = sorted(m for m, d in meses.items() if not d["fechado"])
            self.mes = abertos[0] if abertos else (max(meses) if meses else date.today().strftime("%Y-%m"))
        self.d = meses.get(self.mes) or mes_vazio(self.mes)
        self.atualizar()

    def amigo_erro(self, e):
        self.om_visao.configure(state="normal")
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
