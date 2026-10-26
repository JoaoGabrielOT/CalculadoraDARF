from datetime import date, timedelta

import customtkinter as ctk

from tema import C, F, botao

MESES = ["Janeiro", "Fevereiro", "Março", "Abril", "Maio", "Junho", "Julho", "Agosto",
         "Setembro", "Outubro", "Novembro", "Dezembro"]
MESES_CURTOS = ["Jan", "Fev", "Mar", "Abr", "Mai", "Jun", "Jul", "Ago", "Set", "Out", "Nov", "Dez"]
DIAS = ["D", "S", "T", "Q", "Q", "S", "S"]


class Popup(ctk.CTkToplevel):
    """Janela flutuante sem bordas, posicionada sob um widget e fechada ao clicar fora ou com Esc."""

    def __init__(self, ancora):
        super().__init__(ancora.winfo_toplevel())
        self.withdraw()
        self.overrideredirect(True)
        self.configure(fg_color=C["borda"])
        self.ancora = ancora
        self.grab_anterior = None
        self.corpo = ctk.CTkFrame(self, fg_color=C["card"], corner_radius=0)
        self.corpo.pack(padx=1, pady=1, fill="both", expand=True)

    def abrir(self):
        self.update_idletasks()
        w, h = self.winfo_reqwidth(), self.winfo_reqheight()
        x = self.ancora.winfo_rootx()
        y = self.ancora.winfo_rooty() + self.ancora.winfo_height() + 4
        if y + h > self.winfo_screenheight() - 40:
            y = self.ancora.winfo_rooty() - h - 4
        x = min(x, self.winfo_screenwidth() - w - 8)
        self.geometry(f"+{max(x, 0)}+{max(y, 0)}")
        self.deiconify()
        self.lift()
        try:
            self.grab_anterior = self.grab_current()
        except Exception:
            self.grab_anterior = None
        self.bind("<Escape>", lambda e: self.fechar())
        self.bind("<ButtonPress-1>", self._clique, add="+")
        self.after(20, self._prender)

    def _prender(self):
        try:
            self.grab_set()
            self.focus_force()
        except Exception:
            pass

    def _clique(self, e):
        x0, y0 = self.winfo_rootx(), self.winfo_rooty()
        if not (x0 <= e.x_root < x0 + self.winfo_width() and y0 <= e.y_root < y0 + self.winfo_height()):
            self.fechar()

    def fechar(self):
        anterior = self.grab_anterior
        try:
            self.grab_release()
        except Exception:
            pass
        self.destroy()
        if anterior is not None and anterior is not self:
            try:
                anterior.grab_set()
            except Exception:
                pass


class Calendario(Popup):
    def __init__(self, ancora, valor, minimo, maximo, ao_escolher):
        super().__init__(ancora)
        self.minimo, self.maximo, self.cb = minimo, maximo, ao_escolher
        self.sel = valor
        hoje = date.today()
        base = valor or (min(hoje, maximo) if maximo else hoje)
        if minimo and base < minimo:
            base = minimo
        self.ano, self.mes = base.year, base.month

        topo = ctk.CTkFrame(self.corpo, fg_color="transparent")
        topo.pack(fill="x", padx=10, pady=(10, 6))
        self.bt_ant = botao(topo, "‹", lambda: self.mover(-1), "neutro", altura=30, fonte=15, width=34)
        self.bt_ant.pack(side="left")
        self.bt_prox = botao(topo, "›", lambda: self.mover(1), "neutro", altura=30, fonte=15, width=34)
        self.bt_prox.pack(side="right")
        self.lb = ctk.CTkLabel(topo, text="", font=F(14, "bold"), text_color=C["texto"])
        self.lb.pack(side="left", expand=True)

        grade = ctk.CTkFrame(self.corpo, fg_color="transparent")
        grade.pack(padx=10)
        for i, d in enumerate(DIAS):
            ctk.CTkLabel(grade, text=d, font=F(11, "bold"), text_color=C["muted"], width=38).grid(
                row=0, column=i, pady=(0, 2))
        self.botoes = []
        for i in range(42):
            b = ctk.CTkButton(grade, text="", width=38, height=32, corner_radius=8, font=F(12),
                              border_width=1, text_color_disabled=C["borda"])
            b.grid(row=1 + i // 7, column=i % 7, padx=1, pady=1)
            self.botoes.append(b)

        rod = ctk.CTkFrame(self.corpo, fg_color="transparent")
        rod.pack(fill="x", padx=10, pady=(6, 10))
        self.bt_hoje = botao(rod, "Hoje", lambda: self.escolher(hoje), "chip", altura=30, fonte=12, width=80)
        self.bt_hoje.pack(side="left")
        ontem = hoje - timedelta(days=1)
        self.bt_ontem = botao(rod, "Ontem", lambda: self.escolher(ontem), "chip", altura=30, fonte=12, width=80)
        self.bt_ontem.pack(side="left", padx=6)
        for b, d in ((self.bt_hoje, hoje), (self.bt_ontem, ontem)):
            if not self.permitido(d):
                b.configure(state="disabled")
        self.desenhar()
        self.abrir()

    def permitido(self, d):
        return not ((self.minimo and d < self.minimo) or (self.maximo and d > self.maximo))

    def mover(self, passo):
        m = self.mes + passo
        self.ano += (m - 1) // 12
        self.mes = (m - 1) % 12 + 1
        self.desenhar()

    def desenhar(self):
        self.lb.configure(text=f"{MESES[self.mes - 1]} {self.ano}")
        primeiro = date(self.ano, self.mes, 1)
        inicio = primeiro - timedelta(days=(primeiro.weekday() + 1) % 7)
        hoje = date.today()
        for i, b in enumerate(self.botoes):
            d = inicio + timedelta(days=i)
            fora = d.month != self.mes
            ok = self.permitido(d)
            if d == self.sel:
                estilo = dict(fg_color=C["accent"], hover_color=C["accent_h"], text_color="#ffffff",
                              border_color=C["accent"])
            else:
                estilo = dict(fg_color="transparent", hover_color=C["neutro"],
                              text_color=C["muted"] if fora else C["texto"],
                              border_color=C["accent"] if d == hoje else C["card"])
            b.configure(text=str(d.day), state="normal" if ok else "disabled",
                        command=lambda d=d: self.escolher(d), **estilo)
        ultimo_ant = primeiro - timedelta(days=1)
        prox = date(self.ano + (self.mes == 12), self.mes % 12 + 1, 1)
        self.bt_ant.configure(state="disabled" if self.minimo and ultimo_ant < self.minimo else "normal")
        self.bt_prox.configure(state="disabled" if self.maximo and prox > self.maximo else "normal")

    def escolher(self, d):
        if not self.permitido(d):
            return
        cb = self.cb
        self.fechar()
        cb(d)


class CampoData(ctk.CTkFrame):
    """Campo de data que abre um calendário. Não aceita digitação; get() devolve dd/mm/aaaa."""

    def __init__(self, pai, valor=None, minimo=None, maximo=None, ao_mudar=None):
        super().__init__(pai, fg_color="transparent")
        self.valor, self.minimo, self.maximo, self.ao_mudar = valor, minimo, maximo, ao_mudar
        self.en = ctk.CTkEntry(self, height=38, font=F(13), corner_radius=8, border_color=C["borda"],
                               fg_color=C["card2"], text_color=C["texto"], placeholder_text="Selecione a data")
        self.en.pack(side="left", fill="x", expand=True)
        self.bt = botao(self, "▦", self.abrir, "neutro", altura=38, fonte=15, width=44)
        self.bt.pack(side="left", padx=(6, 0))
        self.en.bind("<Button-1>", lambda e: self.after(1, self.abrir))
        self.en.bind("<Key>", self._tecla)
        self._mostrar()

    def _tecla(self, e):
        if e.keysym in ("Tab", "ISO_Left_Tab", "Return", "Escape"):
            return None
        if e.keysym in ("space", "Down"):
            self.abrir()
        return "break"

    def _mostrar(self):
        self.en.delete(0, "end")
        if self.valor:
            self.en.insert(0, self.valor.strftime("%d/%m/%Y"))

    def abrir(self):
        Calendario(self.en, self.valor, self.minimo, self.maximo, self.set)

    def set(self, d):
        self.valor = d
        self._mostrar()
        if self.ao_mudar:
            self.ao_mudar(d)

    def set_limites(self, minimo=None, maximo=None):
        self.minimo, self.maximo = minimo, maximo
        if self.valor and ((minimo and self.valor < minimo) or (maximo and self.valor > maximo)):
            self.valor = None
            self._mostrar()

    def get(self):
        return self.valor.strftime("%d/%m/%Y") if self.valor else ""


class SeletorMes(Popup):
    def __init__(self, ancora, atual, com_dados, maximo, ao_escolher):
        """atual e maximo no formato AAAA-MM; com_dados é um conjunto de meses AAAA-MM."""
        super().__init__(ancora)
        self.atual, self.com_dados, self.maximo, self.cb = atual, com_dados, maximo, ao_escolher
        self.ano = int(atual[:4])

        topo = ctk.CTkFrame(self.corpo, fg_color="transparent")
        topo.pack(fill="x", padx=10, pady=(10, 6))
        botao(topo, "‹", lambda: self.mover(-1), "neutro", altura=30, fonte=15, width=34).pack(side="left")
        self.bt_prox = botao(topo, "›", lambda: self.mover(1), "neutro", altura=30, fonte=15, width=34)
        self.bt_prox.pack(side="right")
        self.lb = ctk.CTkLabel(topo, text="", font=F(14, "bold"), text_color=C["texto"])
        self.lb.pack(side="left", expand=True)

        grade = ctk.CTkFrame(self.corpo, fg_color="transparent")
        grade.pack(padx=10)
        self.botoes = []
        for i in range(12):
            b = ctk.CTkButton(grade, text=MESES_CURTOS[i], width=70, height=36, corner_radius=8,
                              border_width=1, text_color_disabled=C["borda"])
            b.grid(row=i // 4, column=i % 4, padx=2, pady=2)
            self.botoes.append(b)

        rod = ctk.CTkFrame(self.corpo, fg_color="transparent")
        rod.pack(fill="x", padx=10, pady=(6, 10))
        botao(rod, "Mês atual", lambda: self.escolher(date.today().strftime("%Y-%m")), "chip",
              altura=30, fonte=12, width=100).pack(side="left")
        ctk.CTkLabel(rod, text="● com operações", font=F(11), text_color=C["accent"]).pack(side="right")
        self.desenhar()
        self.abrir()

    def mover(self, passo):
        self.ano += passo
        self.desenhar()

    def desenhar(self):
        self.lb.configure(text=str(self.ano))
        for i, b in enumerate(self.botoes):
            m = f"{self.ano:04d}-{i + 1:02d}"
            futuro = m > self.maximo
            if m == self.atual:
                estilo = dict(fg_color=C["accent"], hover_color=C["accent_h"], text_color="#ffffff",
                              border_color=C["accent"], font=F(12, "bold"))
            elif m in self.com_dados:
                estilo = dict(fg_color=C["accent_bg"], hover_color=C["neutro"], text_color=C["accent"],
                              border_color=C["accent_bg"], font=F(12, "bold"))
            else:
                estilo = dict(fg_color="transparent", hover_color=C["neutro"], text_color=C["texto"],
                              border_color=C["borda"], font=F(12))
            b.configure(state="disabled" if futuro else "normal", command=lambda m=m: self.escolher(m), **estilo)
        self.bt_prox.configure(state="disabled" if f"{self.ano + 1:04d}-01" > self.maximo else "normal")

    def escolher(self, m):
        cb = self.cb
        self.fechar()
        cb(m)
