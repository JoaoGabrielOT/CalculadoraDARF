"""Calculadora DARF — versão Android (Flet).

Os módulos compartilhados (nucleo, google_sync, mercado, atualizador, versao) são copiados para esta
pasta pelo workflow de build; em desenvolvimento, a pasta-pai é usada.
"""
import os
import sys
import tempfile
import threading
import time
import traceback
from datetime import date, datetime, timedelta
from pathlib import Path

import flet as ft
import flet.canvas as cv

AQUI = Path(__file__).resolve().parent
for _p in (AQUI, AQUI.parent):
    if (_p / "nucleo.py").exists() and str(_p) not in sys.path:
        sys.path.insert(0, str(_p))

import atualizador as upd  # noqa: E402
import google_sync as gs  # noqa: E402
import mercado as mk  # noqa: E402
import metas as ms  # noqa: E402
import noticias as nt  # noqa: E402
import nucleo as nc  # noqa: E402
from nucleo import brl, fmt_data, fmt_mes  # noqa: E402
from versao import VERSAO  # noqa: E402

nc.configurar(os.environ.get("FLET_APP_STORAGE_DATA") or (AQUI / "dados"))

VERDE = "#10b981"
VERMELHO = "#ef4444"
AMARELO = "#f59e0b"
MUTED = ft.Colors.ON_SURFACE_VARIANT
PRIMARIO = ft.Colors.ON_SURFACE        # ação primária neutra: inverte com o tema (clara no escuro, escura no claro)
PRIMARIO_TXT = ft.Colors.SURFACE
NOME_APK = "CalculadoraDARF.apk"
ABA_APURACAO, ABA_CAIXA, ABA_RADAR, ABA_NOTICIAS, ABA_CONTA = range(5)
CANAL_NOTICIAS = "noticias_radar"
URL_RELEASES = f"https://github.com/{upd.REPOSITORIO}/releases/latest"
ORD_LOTES = [("cadastro", "Cadastro"), ("data", "Data da compra"), ("ticker", "Ticker"), ("qtd", "Quantidade"),
             ("preco", "Preço de compra"), ("atual", "Preço atual"), ("total", "Total"),
             ("resultado", "Ganho/perda"), ("restante", "Restante")]
ORD_VENDAS = [("data", "Data da venda"), ("ticker", "Ticker"), ("qtd", "Quantidade"), ("preco", "Preço de venda"),
              ("bruto", "Lucro bruto"), ("liquido", "Após taxas"), ("imposto", "Imposto"), ("taxas", "Taxas B3")]
SITUACOES = ["Todos", "Em aberto", "Vendidos"]
TIPOS = ["Todos", "Ação", "BDR"]
OPERACOES = ["Todas", "Swing", "Day trade"]
FILTRO_LOTES = {"situacao": "Todos", "tipo": "Todos", "busca": "", "ordem": "cadastro", "desc": False,
                "buscando": False}
FILTRO_VENDAS = {"operacao": "Todas", "tipo": "Todos", "busca": "", "ordem": "data", "desc": True,
                 "buscando": False}
MESES_CURTOS = ["Jan", "Fev", "Mar", "Abr", "Mai", "Jun", "Jul", "Ago", "Set", "Out", "Nov", "Dez"]


# ---------------------------------------------------------------- Android nativo

def no_android():
    return "MAIN_ACTIVITY_HOST_CLASS_NAME" in os.environ


def atividade():
    from jnius import autoclass
    return autoclass(os.environ["MAIN_ACTIVITY_HOST_CLASS_NAME"]).mActivity


def pasta_cache():
    if no_android():
        try:
            return atividade().getCacheDir().getAbsolutePath()
        except Exception:
            pass
    return os.environ.get("FLET_APP_STORAGE_CACHE") or tempfile.gettempdir()


def instalar_apk(caminho):
    """Abre o instalador do Android para o APK baixado (usa o FileProvider declarado pelo Flet)."""
    from jnius import autoclass
    Intent = autoclass("android.content.Intent")
    File = autoclass("java.io.File")
    FileProvider = autoclass("androidx.core.content.FileProvider")
    ctx = atividade()
    uri = FileProvider.getUriForFile(ctx, ctx.getPackageName() + ".provider", File(str(caminho)))
    intent = Intent(Intent.ACTION_VIEW)
    intent.setDataAndType(uri, "application/vnd.android.package-archive")
    intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_ACTIVITY_NEW_TASK)
    ctx.startActivity(intent)


def permitir_notificacoes():
    """Android 13+: pede a permissão de notificações (o sistema só mostra o pedido enquanto ela não foi negada)."""
    from jnius import autoclass
    if autoclass("android.os.Build$VERSION").SDK_INT < 33:
        return True
    ctx = atividade()
    perm = "android.permission.POST_NOTIFICATIONS"
    if ctx.checkSelfPermission(perm) == autoclass("android.content.pm.PackageManager").PERMISSION_GRANTED:
        return True
    ctx.requestPermissions([perm], 7101)
    return False


def notificar_android(numero, titulo, corpo, link=""):
    """Notificação do sistema; tocar nela abre o link da notícia (ou o app, no resumo)."""
    from jnius import autoclass
    ctx = atividade()
    Context = autoclass("android.content.Context")
    Builder = autoclass("android.app.Notification$Builder")
    Intent = autoclass("android.content.Intent")
    PendingIntent = autoclass("android.app.PendingIntent")
    gerente = ctx.getSystemService(Context.NOTIFICATION_SERVICE)
    if autoclass("android.os.Build$VERSION").SDK_INT >= 26:
        Canal = autoclass("android.app.NotificationChannel")
        importancia = autoclass("android.app.NotificationManager").IMPORTANCE_DEFAULT
        gerente.createNotificationChannel(Canal(CANAL_NOTICIAS, "Notícias do radar", importancia))
        b = Builder(ctx, CANAL_NOTICIAS)
    else:
        b = Builder(ctx)
    if link:
        intent = Intent(Intent.ACTION_VIEW, autoclass("android.net.Uri").parse(link))
    else:
        intent = ctx.getPackageManager().getLaunchIntentForPackage(ctx.getPackageName())
    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    pi = PendingIntent.getActivity(ctx, numero, intent, PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT)
    b.setSmallIcon(autoclass("android.R$drawable").ic_dialog_info)
    b.setContentTitle(titulo)
    b.setContentText(corpo)
    b.setStyle(autoclass("android.app.Notification$BigTextStyle")().bigText(corpo))
    b.setAutoCancel(True)
    b.setContentIntent(pi)
    gerente.notify(numero, b.build())


# ---------------------------------------------------------------- componentes visuais

def logo_ativo(ticker, tam=40):
    """Logo da empresa (PNG; se faltar, SVG); sem nenhuma, as iniciais do ticker."""
    pngs, svg = nt.urls_logo(ticker)
    reserva = ft.Container(width=tam, height=tam, alignment=ft.Alignment.CENTER, bgcolor=ft.Colors.SURFACE_CONTAINER_HIGHEST,
                           content=texto(nt.iniciais(ticker), 10, ft.FontWeight.BOLD, MUTED))
    img = ft.Image(src=svg, width=tam, height=tam, fit=ft.BoxFit.CONTAIN, error_content=reserva)
    for url in reversed(pngs):
        img = ft.Image(src=url, width=tam, height=tam, fit=ft.BoxFit.CONTAIN, error_content=img)
    return ft.Container(width=tam, height=tam, border_radius=ft.BorderRadius.all(tam * 0.22),
                        clip_behavior=ft.ClipBehavior.ANTI_ALIAS, content=img)


def texto(valor, tam=14, peso=None, cor=None, **kw):
    return ft.Text(valor, size=tam, weight=peso, color=cor, **kw)


def rotulo(valor):
    return texto(valor.upper(), 12, ft.FontWeight.BOLD, MUTED)


def valor_total(qtd, preco):
    """Total ao vivo do formulário (quantidade × preço); vazio enquanto algum campo estiver incompleto."""
    try:
        return f"Total: {brl(nc.parse_qtd(qtd or '') * nc.parse_num(preco or ''))}"
    except ValueError:
        return ""


def botao_primario(valor, icone, acao):
    return ft.FilledButton(valor, icon=icone, on_click=acao,
                           style=ft.ButtonStyle(bgcolor=PRIMARIO, color=PRIMARIO_TXT))


def linha_valor(titulo, valor, cor=None, sub=None, tam=16):
    esq = [texto(titulo, 14)]
    if sub:
        esq.append(texto(sub, 12, cor=MUTED))
    return ft.Row(alignment=ft.MainAxisAlignment.SPACE_BETWEEN, vertical_alignment=ft.CrossAxisAlignment.START,
                  controls=[ft.Column(spacing=0, expand=True, controls=esq),
                            texto(valor, tam, ft.FontWeight.BOLD, cor)])


def bloco(conteudo, padding=16, cor=None, borda=None, **kw):
    return ft.Container(content=conteudo, padding=ft.Padding.all(padding), border_radius=ft.BorderRadius.all(16),
                        bgcolor=cor or ft.Colors.SURFACE_CONTAINER, border=borda, **kw)


def pilula(valor, fundo, cor="#ffffff", tam=11):
    return ft.Container(content=texto(valor, tam, ft.FontWeight.BOLD, cor), bgcolor=fundo,
                        padding=ft.Padding.symmetric(horizontal=10, vertical=3), border_radius=ft.BorderRadius.all(12))


def menu_cabecalho(titulo, subtitulo):
    """Primeira linha do menu de contexto: identifica o item e não pode ser clicada."""
    return ft.PopupMenuItem(disabled=True, content=ft.Column(spacing=0, tight=True, controls=[
        texto(titulo, 14, ft.FontWeight.BOLD), texto(subtitulo, 12, cor=MUTED)]))


def menu_contexto(conteudo, itens):
    """Item que abre um menu flutuante sobre ele ao ser tocado, como o menu do botão direito do Windows."""
    return ft.PopupMenuButton(content=conteudo, items=itens, expand=True, padding=0, tooltip="",
                              menu_position=ft.PopupMenuPosition.UNDER, elevation=8,
                              shape=ft.RoundedRectangleBorder(radius=12))


def chip(conteudo, ativo=False, icone=None):
    """Aparência de chip para o conteúdo de um PopupMenuButton ou botão."""
    controles = [ft.Icon(icone, size=16, color=VERDE if ativo else MUTED)] if icone else []
    if conteudo:
        controles.append(texto(conteudo, 13, ft.FontWeight.BOLD if ativo else None, VERDE if ativo else None))
    return ft.Container(
        padding=ft.Padding.symmetric(horizontal=10, vertical=7), border_radius=ft.BorderRadius.all(10),
        bgcolor=ft.Colors.with_opacity(0.15, VERDE) if ativo else None,
        border=ft.Border.all(1, VERDE if ativo else ft.Colors.OUTLINE_VARIANT),
        content=ft.Row(spacing=4, tight=True, vertical_alignment=ft.CrossAxisAlignment.CENTER, controls=controles))


def chip_menu(titulo, valor, opcoes, ao_escolher, padrao, sempre_valor=False):
    """Chip que abre um menu com as opções; opcoes é uma lista de (chave, texto)."""
    rotulo_txt = dict(opcoes).get(valor, valor)
    ativo = valor != padrao
    conteudo = chip(f"{titulo}: {rotulo_txt}" if ativo or sempre_valor else titulo, ativo)
    conteudo.content.controls.append(ft.Icon(ft.Icons.ARROW_DROP_DOWN, size=18, color=VERDE if ativo else MUTED))
    return ft.PopupMenuButton(content=conteudo, tooltip=titulo, items=[
        ft.PopupMenuItem(content=ft.Text(t), checked=k == valor, on_click=lambda e, k=k: ao_escolher(k))
        for k, t in opcoes])


def cor_resultado(v):
    return VERMELHO if v < 0 else (VERDE if v > 0 else None)


def para_data(v):
    if isinstance(v, datetime):
        return v.date()
    if isinstance(v, date):
        return v
    return datetime.fromisoformat(str(v)).date()


def erro_mercado(e):
    if isinstance(e, mk.SemDados):
        return str(e)
    nome = type(e).__name__
    if "RateLimit" in nome or "Too Many" in str(e):
        return "Limite de consultas do Yahoo atingido. Tente em alguns minutos."
    if "Connection" in nome or "Timeout" in nome:
        return "Sem conexão com a internet."
    return f"Erro ao consultar: {str(e)[:120]}"


class ResumoOrdem:
    """Resumo financeiro da ordem: valor bruto, taxas, IRRF, débito/crédito na conta e data de liquidação."""

    def __init__(self):
        self.bruto, self.taxas, self.irrf = (texto("—", 13, ft.FontWeight.BOLD) for _ in range(3))
        self.impacto = texto("", 14, ft.FontWeight.BOLD)
        self.liq = texto("", 12, ft.FontWeight.BOLD)
        self.nota = texto("", 11, cor=MUTED)

        def linha(t, v):
            return ft.Row(alignment=ft.MainAxisAlignment.SPACE_BETWEEN, controls=[texto(t, 12, cor=MUTED), v])

        self.controle = ft.Container(
            padding=ft.Padding.all(12), border_radius=ft.BorderRadius.all(12),
            bgcolor=ft.Colors.SURFACE_CONTAINER_HIGHEST, content=ft.Column(spacing=4, controls=[
                rotulo("Resumo financeiro da ordem"), linha("Valor bruto", self.bruto),
                linha("Taxas B3 (estimadas)", self.taxas), linha("IRRF retido", self.irrf),
                self.impacto, self.liq, self.nota]))

    def mostrar(self, res, nota=""):
        self.nota.value = nota
        if res is None:
            self.bruto.value = self.taxas.value = self.irrf.value = "—"
            self.impacto.value, self.impacto.color = "Preencha quantidade, preço e data.", MUTED
            self.liq.value = ""
            return
        self.bruto.value, self.taxas.value, self.irrf.value = brl(res["bruto"]), brl(res["taxas"]), brl(res["irrf"])
        if res["liquido"] < 0:
            self.impacto.value, self.impacto.color = f"Será debitado da conta: {brl(-res['liquido'])}", VERMELHO
        else:
            self.impacto.value, self.impacto.color = f"Será creditado na conta: {brl(res['liquido'])}", VERDE
        self.liq.value = f"📅 Liquidação financeira: {nc.fmt_liquidacao(res['liquidacao'])}"


def numeros_ordem(qtd, preco):
    try:
        return nc.parse_qtd(qtd or ""), nc.parse_num(preco or "")
    except ValueError:
        return None


class CampoData:
    """Campo de data que abre o calendário do Material; não aceita digitação."""

    def __init__(self, app, rotulo_txt, valor=None, minimo=None, maximo=None, ao_mudar=None):
        self.app, self.valor, self.minimo, self.maximo = app, valor, minimo, maximo
        self.ao_mudar = ao_mudar
        # campo "falso" (toque abre o calendário); um TextField somente leitura reabriria ao recuperar o foco
        self.valor_txt = texto(self._txt() or "Selecione a data", 15)
        self.campo = ft.Container(
            on_click=self.abrir, padding=ft.Padding.symmetric(horizontal=14, vertical=14),
            border=ft.Border.all(1, ft.Colors.OUTLINE), border_radius=ft.BorderRadius.all(6),
            content=ft.Row(controls=[ft.Column(spacing=0, expand=True, controls=[texto(rotulo_txt, 11, cor=MUTED),
                                                                               self.valor_txt]),
                                     ft.Icon(ft.Icons.CALENDAR_MONTH, color=MUTED)]))
        hoje = date.today()
        self.atalhos = ft.Row(spacing=6, controls=[
            ft.Chip(label=ft.Text("Hoje"), on_click=lambda e: self.definir(hoje)),
            ft.Chip(label=ft.Text("Ontem"), on_click=lambda e: self.definir(hoje - timedelta(days=1)))])
        self.controle = ft.Column(spacing=6, tight=True, controls=[self.campo, self.atalhos])

    def _txt(self):
        return self.valor.strftime("%d/%m/%Y") if self.valor else ""

    def permitido(self, d):
        return not ((self.minimo and d < self.minimo) or (self.maximo and d > self.maximo))

    def definir(self, d):
        if not self.permitido(d):
            self.app.aviso("Data fora do período permitido.")
            return
        self.valor = d
        self.valor_txt.value = self._txt()
        self.valor_txt.update()
        if self.ao_mudar:
            self.ao_mudar(d)

    def set_limites(self, minimo, maximo):
        self.minimo, self.maximo = minimo, maximo
        if self.valor and not self.permitido(self.valor):
            self.valor = None
            self.valor_txt.value = "Selecione a data"

    def abrir(self, e=None):
        inicio = self.minimo or date(2000, 1, 1)
        fim = self.maximo or date.today()
        if inicio > fim:
            self.app.aviso("Não há data válida neste período.")
            return
        inicial = self.valor or min(max(date.today(), inicio), fim)

        def escolheu(ev):
            if ev.control.value:
                self.definir(para_data(ev.control.value))

        self.app.page.show_dialog(ft.DatePicker(first_date=inicio, last_date=fim, value=inicial,
                                                current_date=date.today(), on_change=escolheu,
                                                help_text="Selecione a data", cancel_text="Cancelar",
                                                confirm_text="OK"))


class GraficoAtivo:
    """Diálogo com o gráfico de preço do ativo: períodos de 1D a Máx; tocar/arrastar no gráfico mostra o ponto."""

    ALTURA = 220
    MARGEM = (4, 10, 58, 22)  # esquerda, topo, direita (preços), base (datas)

    def __init__(self, app, ticker, nome, dados):
        self.app, self.ticker, self.dados = app, ticker, dados
        self.periodo = "1D"
        self.g = None
        self.largura = max(260, min(560, (app.page.width or 380) - 96))
        self.pontos = []
        d = dados
        vp, v = d.get("var_pct"), d.get("var")
        self.lb_periodo = texto("", 13, ft.FontWeight.BOLD)
        self.lb_ponto = texto("Toque no gráfico para ver o preço de cada ponto", 12, cor=MUTED)
        self.canvas = cv.Canvas(width=self.largura, height=self.ALTURA, on_resize=self.redimensionou,
                                resize_interval=100,
                                shapes=[cv.Text(self.largura / 2, self.ALTURA / 2, "Carregando…",
                                                style=ft.TextStyle(size=12, color=MUTED),
                                                alignment=ft.Alignment.CENTER)])
        self.chips = ft.Row(spacing=6, wrap=True, run_spacing=6)
        self.desenhar_chips()

        def stat(titulo, valor):
            return ft.Container(width=(self.largura - 8) / 2, padding=ft.Padding.symmetric(horizontal=10, vertical=6),
                                border_radius=ft.BorderRadius.all(10), bgcolor=ft.Colors.SURFACE_CONTAINER_HIGHEST,
                                content=ft.Column(spacing=0, controls=[texto(titulo, 10, cor=MUTED),
                                                                       texto(valor, 13, ft.FontWeight.BOLD)]))

        faixa = lambda a, b: f"{brl(a)} – {brl(b)}" if a and b else "—"  # noqa: E731
        stats = ft.Row(spacing=8, run_spacing=8, wrap=True, controls=[
            stat("Fech. anterior", brl(d["anterior"]) if d.get("anterior") else "—"),
            stat("Mín./máx. do dia", faixa(d.get("min_dia"), d.get("max_dia"))),
            stat("Mín./máx. 52 sem.", faixa(d.get("min52"), d.get("max52"))),
            stat("Média 6 meses", (brl(d["media6m"]) + (f" ({mk.fmt_pct(d['vs_media_pct'])})"
                                                       if d.get("vs_media_pct") is not None else ""))
                 if d.get("media6m") else "—"),
            stat("ATR (14)", brl(d["atr"]) + (f" · {mk.fmt_pct(d['atr_pct'], False)}" if d.get("atr_pct") else "")
                 if d.get("atr") else "—"),
            stat("Volume", mk.fmt_volume(d.get("volume")))])
        acoes = []
        if app.visao:
            if all(r["ticker"] != ticker for r in app.cfg["radar"]):
                acoes.append(botao_primario("Meu radar", ft.Icons.PLAYLIST_ADD, lambda e: self.depois(app.importar_radar)))
        else:
            acoes.append(botao_primario("Comprar", ft.Icons.ADD_SHOPPING_CART, lambda e: self.depois(app.radar_comprar)))
            if ticker in nc.custodia_atual():
                acoes.append(ft.OutlinedButton("Vender", icon=ft.Icons.SELL,
                                               on_click=lambda e: self.depois(app.radar_vender)))
        acoes.append(ft.TextButton("Notícias", icon=ft.Icons.NEWSPAPER, on_click=lambda e: self.depois(self.noticias)))
        cor_v = cor_resultado(round(vp, 2)) if vp is not None else MUTED
        conteudo = ft.Column(tight=True, spacing=10, scroll=ft.ScrollMode.AUTO, controls=[
            ft.Row(spacing=10, vertical_alignment=ft.CrossAxisAlignment.CENTER, controls=[
                logo_ativo(ticker, 40), ft.Column(spacing=0, expand=True, controls=[
                    texto(ticker, 18, ft.FontWeight.BOLD),
                    texto(nome or d.get("nome", ""), 12, cor=MUTED, max_lines=1, overflow=ft.TextOverflow.ELLIPSIS)])]),
            ft.Row(vertical_alignment=ft.CrossAxisAlignment.END, controls=[
                texto(brl(d["preco"]) if d.get("preco") else "—", 26, ft.FontWeight.BOLD),
                texto(f"{mk.fmt_pct(vp)} ({'+' if (v or 0) > 0 else ''}{brl(v)}) hoje" if vp is not None else "", 13,
                      ft.FontWeight.BOLD, cor_v)]),
            self.chips, self.lb_periodo,
            ft.GestureDetector(content=self.canvas, on_tap_down=self.tocou, on_pan_update=self.arrastou,
                               on_horizontal_drag_update=self.arrastou),
            self.lb_ponto, stats, ft.Row(spacing=8, wrap=True, controls=acoes)])
        self.dlg = ft.AlertDialog(content=ft.Container(width=self.largura, content=conteudo),
                                  content_padding=ft.Padding.all(18),
                                  actions=[ft.TextButton("Fechar", on_click=lambda e: app.page.pop_dialog())])
        app.page.show_dialog(self.dlg)
        self.carregar()

    def depois(self, acao):
        self.app.page.pop_dialog()
        acao(self.ticker)

    def noticias(self, t):
        self.app.f_noticias["ticker"] = t
        self.app.ir_para(ABA_NOTICIAS)

    def desenhar_chips(self):
        self.chips.controls = [
            ft.Container(content=chip(p, p == self.periodo), on_click=lambda e, p=p: self.trocar(p))
            for p in mk.PERIODOS_GRAFICO]

    def trocar(self, p):
        self.periodo = p
        self.desenhar_chips()
        self.carregar()

    def atualizar(self):
        try:
            self.dlg.update()
        except Exception:
            pass

    def carregar(self):
        periodo = self.periodo
        self.lb_periodo.value = "Carregando…"
        self.lb_periodo.color = MUTED
        self.atualizar()

        def trabalho():
            try:
                g = self.app.mercado.grafico(self.ticker, periodo)
            except Exception as ex:
                if periodo == self.periodo:
                    self.lb_periodo.value = erro_mercado(ex)
                    self.lb_periodo.color = VERMELHO
                    self.atualizar()
                return
            if periodo != self.periodo:
                return
            self.g = g
            ult, ref = g["pontos"][-1][1], g["referencia"]
            var = (ult / ref - 1) * 100 if ref else None
            nome = {"1D": "hoje", "Máx": "desde o início"}.get(periodo, f"em {periodo}")
            self.lb_periodo.value = f"{mk.fmt_pct(var)} {nome}"
            self.lb_periodo.color = cor_resultado(round(var, 2)) if var is not None else MUTED
            self.desenhar()

        self.app.page.run_thread(trabalho)

    def redimensionou(self, e):
        if e.width and abs(e.width - self.largura) > 4:
            self.largura = e.width
            self.desenhar()

    def rotulo_tempo(self, ts, curto=False):
        d = datetime(1970, 1, 1) + timedelta(seconds=ts + self.g["desvio"])
        if self.periodo == "1D":
            return d.strftime("%H:%M")
        if self.periodo == "5D":
            return d.strftime("%d/%m") if curto else d.strftime("%d/%m %H:%M")
        if self.periodo in ("5A", "Máx"):
            return d.strftime("%m/%Y")
        return d.strftime("%d/%m/%y") if curto else d.strftime("%d/%m/%Y")

    def desenhar(self, cursor=None):
        g = self.g
        if not g:
            return
        pts = g["pontos"]
        ml, mt, mr, mb = self.MARGEM
        x0, x1, y0, y1 = ml, self.largura - mr, mt, self.ALTURA - mb
        valores = [v for _, v in pts] + ([g["referencia"]] if self.periodo == "1D" else [])
        vmin, vmax = min(valores), max(valores)
        folga = (vmax - vmin) * 0.08 or vmax * 0.01 or 1
        vmin, vmax = vmin - folga, vmax + folga
        n = len(pts)
        px = lambda i: x0 + (x1 - x0) * (i / (n - 1))  # noqa: E731
        py = lambda v: y1 - (y1 - y0) * ((v - vmin) / (vmax - vmin))  # noqa: E731
        linha = VERDE if pts[-1][1] >= g["referencia"] else VERMELHO
        estilo = ft.TextStyle(size=10, color=MUTED)
        grade = ft.Paint(color=ft.Colors.with_opacity(0.25, ft.Colors.OUTLINE), stroke_width=1,
                         style=ft.PaintingStyle.STROKE)
        formas = []
        for k in range(5):
            v = vmin + (vmax - vmin) * k / 4
            y = py(v)
            formas.append(cv.Line(x0, y, x1, y, paint=grade))
            formas.append(cv.Text(x1 + 6, y, brl(v).replace("R$ ", ""), style=estilo,
                                  alignment=ft.Alignment.CENTER_LEFT))
        marcas = min(4, n)
        for k in range(marcas):
            i = round(k * (n - 1) / max(1, marcas - 1))
            alin = ft.Alignment.TOP_CENTER if 0 < k < marcas - 1 else (
                ft.Alignment.TOP_LEFT if k == 0 else ft.Alignment.TOP_RIGHT)
            formas.append(cv.Text(px(i), y1 + 6, self.rotulo_tempo(pts[i][0], True), style=estilo, alignment=alin))
        coords = [(px(i), py(v)) for i, (_, v) in enumerate(pts)]
        area = [cv.Path.MoveTo(x0, y1)] + [cv.Path.LineTo(x, y) for x, y in coords] + [cv.Path.LineTo(x1, y1),
                                                                                       cv.Path.Close()]
        formas.append(cv.Path(area, paint=ft.Paint(style=ft.PaintingStyle.FILL, gradient=ft.PaintLinearGradient(
            begin=(0, y0), end=(0, y1), colors=[ft.Colors.with_opacity(0.35, linha),
                                                ft.Colors.with_opacity(0.0, linha)]))))
        if self.periodo == "1D":
            yr = py(g["referencia"])
            formas.append(cv.Line(x0, yr, x1, yr, paint=ft.Paint(color=MUTED, stroke_width=1,
                                                                 style=ft.PaintingStyle.STROKE,
                                                                 stroke_dash_pattern=[4, 4])))
        formas.append(cv.Path([cv.Path.MoveTo(*coords[0])] + [cv.Path.LineTo(x, y) for x, y in coords[1:]],
                              paint=ft.Paint(color=linha, stroke_width=2, style=ft.PaintingStyle.STROKE,
                                             stroke_join=ft.StrokeJoin.ROUND)))
        formas.append(cv.Circle(coords[-1][0], coords[-1][1], 4, paint=ft.Paint(color=linha)))
        if cursor is not None:
            x, y = coords[cursor]
            formas.append(cv.Line(x, y0, x, y1, paint=ft.Paint(color=MUTED, stroke_width=1,
                                                                style=ft.PaintingStyle.STROKE,
                                                                stroke_dash_pattern=[3, 3])))
            formas.append(cv.Circle(x, y, 5, paint=ft.Paint(color=linha)))
        self.pontos = coords
        self.canvas.width = self.largura
        self.canvas.shapes = formas
        self.atualizar()

    def mostrar_ponto(self, x):
        if not self.pontos or not self.g:
            return
        i = min(range(len(self.pontos)), key=lambda k: abs(self.pontos[k][0] - x))
        ts, v = self.g["pontos"][i]
        ref = self.g["referencia"]
        var = (v / ref - 1) * 100 if ref else None
        self.lb_ponto.value = f"{self.rotulo_tempo(ts)} · {brl(v)} · {mk.fmt_pct(var)}"
        self.lb_ponto.color = cor_resultado(round(var, 2)) if var is not None else None
        self.desenhar(cursor=i)

    def tocou(self, e):
        if e.local_position is not None:
            self.mostrar_ponto(e.local_position.x)

    def arrastou(self, e):
        if e.local_position is not None:
            self.mostrar_ponto(e.local_position.x)


# ---------------------------------------------------------------- aplicativo

class App:
    def __init__(self, page: ft.Page):
        self.page = page
        self.cfg = nc.ler_config()
        if nc.corrigir_tipos():  # registros antigos com Ação/BDR errado
            self.cfg["pendente"] = True
            nc.gravar_config(self.cfg)
        self.mes = nc.mes_inicial()
        self.d = nc.carregar(self.mes)
        self.visao = None
        self.dados_amigo = {}
        self.amigo_radar, self.amigo_caixa = [], None
        self.f_lotes = dict(FILTRO_LOTES)
        self.f_vendas = dict(FILTRO_VENDAS)
        self.col_lotes = self.col_vendas = self.cont_lotes = self.cont_vendas = None
        self.aba = 0
        self.navegando = None  # (aba de destino, hora) durante a animação disparada pela barra inferior
        self.g = gs.Google(nc.DADOS, AQUI)
        self.mercado = mk.Mercado()
        self.cotacoes = mk.Cotacoes(self.mercado)
        self.radar_dados = {}
        self.radar_rodando = False
        self.radar_hora = 0
        self.radar_msg = "Cotações do Yahoo Finance (atraso de até 15 min)"
        self.sync_rodando = False
        self.resync = False
        self.sync_timer = None
        self.status = "off"
        self.ultima_sync = None
        self.ultima_puxada = 0
        self.ultimo_erro = ""
        self.trava_sync = threading.Lock()
        self.launcher = ft.UrlLauncher()
        self.noticias_rodando = False
        self.noticias_msg = ""
        self.radar_filtro = "Todos"
        self.radar_ordem = self.cfg.get("radar_ordem_lista", "manual")
        self.f_noticias = {"tema": "Todas", "ticker": "Todos"}
        self.cfg.setdefault("noticias_notificar", True)
        self.cfg.setdefault("metas", [])
        self.metas_ui = None  # atualiza o diálogo de metas quando ele está aberto

        page.title = "Calculadora DARF"
        page.theme = ft.Theme(color_scheme_seed=VERDE)
        page.dark_theme = ft.Theme(color_scheme_seed=VERDE)
        page.theme_mode = ft.ThemeMode.LIGHT if self.cfg.get("tema") == "Light" else ft.ThemeMode.DARK
        page.padding = 0
        self.bt_sync = ft.IconButton(icon=ft.Icons.CLOUD_OFF, tooltip="Sincronização",
                                     on_click=lambda e: self.ir_para(ABA_CONTA))
        page.appbar = ft.AppBar(title=texto("Calculadora DARF", 20, ft.FontWeight.BOLD), actions=[self.bt_sync])
        page.navigation_bar = ft.NavigationBar(selected_index=0, on_change=self.trocar_aba, destinations=[
            ft.NavigationBarDestination(icon=ft.Icons.RECEIPT_LONG, label="Apuração"),
            ft.NavigationBarDestination(icon=ft.Icons.ACCOUNT_BALANCE_WALLET, label="Caixa"),
            ft.NavigationBarDestination(icon=ft.Icons.INSIGHTS, label="Radar"),
            ft.NavigationBarDestination(icon=ft.Icons.NEWSPAPER, label="Notícias"),
            ft.NavigationBarDestination(icon=ft.Icons.ACCOUNT_CIRCLE, label="Conta")])
        # as telas ficam lado a lado: dá para trocar arrastando para os lados
        self.paginas = [ft.Container(expand=True) for _ in range(5)]
        self.pv = ft.PageView(controls=self.paginas, selected_index=0, expand=True, on_change=self.pagina_arrastada)
        page.add(self.pv)
        self.render(todas=True)
        self.marcar_badge()

        if self.g.tem_token():
            page.run_thread(self.conectar_token)
        page.run_thread(self.verificar_atualizacao)
        page.run_thread(self.verificar_metas)  # ao abrir: cobre o período em que o app ficou fechado
        try:  # ao voltar para o primeiro plano
            page.on_app_lifecycle_state_change = self.mudou_ciclo
        except Exception:
            pass
        if self.cfg.get("noticias_notificar", True) and no_android():
            page.run_thread(self.pedir_permissao_notificacao)
        threading.Thread(target=self.laco, daemon=True).start()

    # ------------------------------------------------------------ utilidades
    def mudou_ciclo(self, e):
        if "resume" in str(getattr(e, "state", "")).lower():
            self.page.run_thread(self.verificar_metas)

    def aviso(self, msg):
        try:
            self.page.show_dialog(ft.SnackBar(content=ft.Text(msg)))
        except Exception:
            pass

    def perguntar(self, titulo, msg, sim, ao_sim, nao="Cancelar", perigo=False):
        def responder(ok):
            self.page.pop_dialog()
            if ok:
                ao_sim()

        estilo = ft.ButtonStyle(bgcolor=VERMELHO, color="#ffffff") if perigo else None
        self.page.show_dialog(ft.AlertDialog(title=ft.Text(titulo), content=ft.Text(msg), actions=[
            ft.TextButton(nao, on_click=lambda e: responder(False)),
            ft.FilledButton(sim, style=estilo, on_click=lambda e: responder(True))]))

    def abrir_url(self, url):
        self.page.run_task(self.launcher.launch_url, url, mode=ft.LaunchMode.EXTERNAL_APPLICATION)

    def ir_para(self, aba, animar=True):
        anterior = self.aba
        self.aba = aba
        self.page.navigation_bar.selected_index = aba
        self.render()
        if animar and aba != anterior:
            self.navegando = (aba, time.time())
            self.page.run_task(self.pv.go_to_page, aba, ft.Duration(milliseconds=280))
        if aba == ABA_RADAR:
            self.atualizar_radar()
        if aba == ABA_NOTICIAS:
            nt.marcar_lidas()
            self.marcar_badge()
            self.atualizar_noticias()
        elif anterior == ABA_NOTICIAS:
            self.render(todas=False, indice=ABA_NOTICIAS)  # some o selo "Nova" das já vistas

    def trocar_aba(self, e):
        self.ir_para(e.control.selected_index)

    def pagina_arrastada(self, e):
        try:
            idx = int(e.data)
        except (TypeError, ValueError):
            idx = e.control.selected_index
        if self.navegando:
            destino, hora = self.navegando
            if time.time() - hora < 2:
                if idx == destino:  # páginas intermediárias da animação são ignoradas
                    self.navegando = None
                return
            self.navegando = None
        if idx != self.aba:
            self.ir_para(idx, animar=False)

    def render(self, todas=False, indice=None):
        telas = (self.tela_apuracao, self.tela_caixa, self.tela_radar, self.tela_noticias, self.tela_conta)
        alvo = self.aba if indice is None else indice
        try:
            for i, tela in enumerate(telas):
                if todas or i == alvo:
                    self.paginas[i].content = tela()
            editavel = self.aba == ABA_APURACAO and not self.visao and not self.d["fechado"]
            self.page.floating_action_button = ft.FloatingActionButton(
                icon=ft.Icons.ADD, tooltip="Nova compra", bgcolor=PRIMARIO, foreground_color=PRIMARIO_TXT,
                on_click=lambda e: self.form_compra()) if editavel else None
            self.atualizar_icone_sync()
            self.page.update()
        except Exception:
            traceback.print_exc()

    def recarregar(self):
        if not self.visao:
            self.d = nc.carregar(self.mes)
        self.render()

    # ------------------------------------------------------------ apuração
    def tela_apuracao(self):
        d = self.d
        r = nc.apurar(d)
        proprio = not self.visao
        editavel = proprio and not d["fechado"]

        if self.visao:
            estado = pilula("Somente leitura", ft.Colors.with_opacity(0.2, AMARELO), AMARELO)
        elif d["fechado"]:
            estado = pilula("Fechado", ft.Colors.SURFACE_CONTAINER_HIGHEST, MUTED)
        else:
            estado = pilula("● Aberto", ft.Colors.with_opacity(0.18, VERDE), VERDE)
        if self.visao:
            estado = pilula("Somente leitura", ft.Colors.with_opacity(0.2, AMARELO), AMARELO)
        elif d["fechado"]:
            estado = pilula("Fechado", ft.Colors.SURFACE_CONTAINER_HIGHEST, MUTED)
        else:
            estado = pilula("Aberto", ft.Colors.SURFACE_CONTAINER_HIGHEST, ft.Colors.ON_SURFACE)
        mais = [ft.PopupMenuItem(content=ft.Text("Fechar mês"), icon=ft.Icons.LOCK, on_click=self.fechar_mes)] \
            if editavel else []
        topo = ft.Row(vertical_alignment=ft.CrossAxisAlignment.CENTER, controls=[
            ft.OutlinedButton(fmt_mes(self.mes), icon=ft.Icons.CALENDAR_MONTH, on_click=self.abrir_meses),
            estado,
            ft.Container(expand=True),
            ft.PopupMenuButton(icon=ft.Icons.MORE_VERT, items=mais) if mais else ft.Container()])
        itens = [topo]
        if not self.visao:
            cx = nc.resumo_caixa(self.cfg)
            if cx["definido"]:
                txt = f"Saldo disponível {brl(cx['disponivel'])} · projetado {brl(cx['projetado'])}"
            else:
                txt = "Definir saldo em conta"
            itens.append(ft.Container(
                on_click=lambda e: self.ir_para(ABA_CAIXA), padding=ft.Padding.symmetric(horizontal=14, vertical=10),
                border_radius=ft.BorderRadius.all(12), bgcolor=ft.Colors.SURFACE_CONTAINER,
                content=ft.Row(spacing=8, controls=[ft.Icon(ft.Icons.ACCOUNT_BALANCE_WALLET, size=18, color=MUTED),
                                                    texto(txt, 13, ft.FontWeight.BOLD, expand=True),
                                                    ft.Icon(ft.Icons.CHEVRON_RIGHT, size=18, color=MUTED)])))

            ativas = len(ms.metas_ativas(self.cfg))
            itens.append(ft.Container(
                on_click=lambda e: self.dialogo_metas(), padding=ft.Padding.symmetric(horizontal=14, vertical=10),
                border_radius=ft.BorderRadius.all(12), bgcolor=ft.Colors.SURFACE_CONTAINER,
                content=ft.Row(spacing=8, controls=[
                    ft.Icon(ft.Icons.TRACK_CHANGES, size=18, color=MUTED),
                    texto("Meta de lucro / Preço-alvo" + (f" · {ativas} ativa{'s' if ativas != 1 else ''}"
                                                           if ativas else ""), 13, ft.FontWeight.BOLD, expand=True),
                    ft.Icon(ft.Icons.CHEVRON_RIGHT, size=18, color=MUTED)])))

        itens += self.seletor_visao("Dados")

        n = len(r["ops"])
        v = r["vendas_acoes_st"]
        isento = r["isento"]
        ops_dt = [o for o in r["ops"] if o["dt"]]
        ops_st = [o for o in r["ops"] if not o["dt"]]

        # imposto a pagar (destaque)
        complemento = [texto(nc.info_darf(r, self.mes), 12, cor=MUTED)]
        if r["darf_anterior"]:
            complemento.append(texto(f"Inclui {brl(r['darf_anterior'])} de meses anteriores", 12, cor=MUTED))
        itens.append(bloco(ft.Column(spacing=6, controls=[rotulo("Imposto a pagar"),
                                                          texto(brl(r["darf"]), 32, ft.FontWeight.BOLD)] + complemento),
                           padding=20))

        # resultado do mês
        itens.append(bloco(ft.Column(spacing=12, controls=[
            rotulo("Resultado do mês"),
            linha_valor("Lucro bruto", brl(r["bruto"]), cor_resultado(r["bruto"]), f"{n} venda{'s' if n != 1 else ''}"),
            linha_valor("Lucro líquido", brl(r["lucro_liquido"]), cor_resultado(r["lucro_liquido"]),
                        "após taxas e impostos")])))

        # day trade x swing trade
        def regime(titulo, aliquota, imposto, ops_, extra):
            return ft.Container(expand=True, padding=ft.Padding.all(14), border_radius=ft.BorderRadius.all(16),
                                bgcolor=ft.Colors.SURFACE_CONTAINER, content=ft.Column(spacing=4, controls=[
                                    rotulo(titulo), texto(brl(imposto), 17, ft.FontWeight.BOLD),
                                    texto(f"Alíquota {aliquota} · {len(ops_)} venda{'s' if len(ops_) != 1 else ''}", 11,
                                          cor=MUTED),
                                    texto(extra, 11, cor=MUTED)]))
        extra_st = "Isento até R$ 20 mil em ações" if isento else "Acima do limite de isenção"
        itens.append(ft.Row(spacing=10, vertical_alignment=ft.CrossAxisAlignment.START, controls=[
            regime("Swing trade", "15%", r["imp_st"], ops_st, extra_st),
            regime("Day trade", "20%", r["imp_dt"], ops_dt, "Sem isenção")]))

        # detalhamento (recolhido por padrão)
        def linha(t, val, forte=False):
            return ft.Row(alignment=ft.MainAxisAlignment.SPACE_BETWEEN, controls=[
                texto(t, 14 if forte else 13, ft.FontWeight.BOLD if forte else None, None if forte else MUTED),
                texto(val, 15 if forte else 13, ft.FontWeight.BOLD)])
        detalhe = ft.ExpansionTile(title=texto("Detalhamento", 15, ft.FontWeight.BOLD), expanded=False,
                                   tile_padding=ft.Padding.symmetric(horizontal=16), bgcolor=ft.Colors.TRANSPARENT,
                                   controls_padding=ft.Padding.only(left=16, right=16, bottom=16), controls=[
            ft.Column(spacing=8, controls=[
                rotulo("Limite de isenção (ações · swing)"),
                texto(f"{brl(v)}  de  {brl(nc.LIMITE_ISENCAO)}", 14, ft.FontWeight.BOLD),
                ft.ProgressBar(value=min(v / nc.LIMITE_ISENCAO, 1), color=VERDE if isento else VERMELHO, bar_height=8,
                               border_radius=ft.BorderRadius.all(4)),
                texto("Isento de IR em swing trade de ações" if isento else "Acima do limite · lucro tributado em 15%",
                      12, ft.FontWeight.BOLD, VERDE if isento else VERMELHO),
                ft.Divider(),
                linha("Taxas B3 + corretagem", brl(r["custos"])),
                linha("Imposto swing trade (15%)", brl(r["imp_st"])),
                linha("Imposto day trade (20%)", brl(r["imp_dt"])),
                linha("Imposto devido", brl(r["imposto_total"]), forte=True),
                linha("IRRF retido (dedo-duro)", ("- " + brl(r["irrf"])) if r["irrf"] else brl(0)),
                linha("DARF de meses anteriores", brl(r["darf_anterior"])),
            ])])
        itens.append(ft.Container(content=detalhe, bgcolor=ft.Colors.SURFACE_CONTAINER,
                                  border_radius=ft.BorderRadius.all(16), clip_behavior=ft.ClipBehavior.HARD_EDGE))

        # ativos comprados
        total = len(d["lotes"])
        self.cont_lotes = pilula("", ft.Colors.SURFACE_CONTAINER_HIGHEST, MUTED)
        itens.append(ft.Row(controls=[texto("Ativos comprados", 17, ft.FontWeight.BOLD), self.cont_lotes,
                                      ft.Container(expand=True),
                                      ft.OutlinedButton("Registrar venda", icon=ft.Icons.SELL,
                                                        on_click=lambda e: self.form_venda())
                                      if editavel else ft.Container()]))
        if total:
            itens += self.barra_filtros(self.f_lotes, ORD_LOTES, "cadastro", [
                ("situacao", "Situação", [(x, x) for x in SITUACOES], "Todos"),
                ("tipo", "Tipo", [(x, x) for x in TIPOS], "Todos")])
        self.col_lotes = ft.Column(spacing=12)
        itens.append(self.col_lotes)

        # vendas
        self.cont_vendas = pilula("", ft.Colors.SURFACE_CONTAINER_HIGHEST, MUTED)
        itens.append(ft.Row(controls=[texto("Vendas do mês", 17, ft.FontWeight.BOLD), self.cont_vendas]))
        if r["ops"]:
            itens += self.barra_filtros(self.f_vendas, ORD_VENDAS, "data", [
                ("operacao", "Operação", [(x, x) for x in OPERACOES], "Todas"),
                ("tipo", "Tipo", [(x, x) for x in TIPOS], "Todos")])
        self.col_vendas = ft.Column(spacing=12)
        itens.append(self.col_vendas)
        self.preencher_listas(r)
        itens.append(ft.Container(height=80))
        em_carteira = {l["ticker"] for l in d["lotes"] if nc.restante(l) > 0}
        self.cotacoes.atualizar(em_carteira, self.cotacoes_chegaram)
        return ft.ListView(controls=itens, padding=ft.Padding.all(16), spacing=12, expand=True)

    # ------------------------------------------------------------ filtros e ordenação das listas
    def barra_filtros(self, f, ordens, ordem_padrao, menus):
        """Linha de chips (busca, filtros, ordenação e sentido) e o campo de busca quando aberto."""
        padrao = FILTRO_LOTES if f is self.f_lotes else FILTRO_VENDAS

        def definir(chave, valor):
            f[chave] = valor
            if chave == "ordem":
                f["desc"] = valor in ("data", "total", "resultado", "atual", "bruto", "liquido", "imposto", "taxas")
            self.render()

        def alternar_busca(e):
            f["buscando"] = not f["buscando"]
            if not f["buscando"]:
                f["busca"] = ""
            self.render()

        def inverter(e):
            f["desc"] = not f["desc"]
            self.render()

        def limpar(e):
            f.clear()
            f.update(padrao)
            self.render()

        def digitou(e):
            f["busca"] = (e.control.value or "").strip().upper()
            self.preencher_listas(atualizar=True)

        chips = [ft.Container(content=chip("", bool(f["busca"]) or f["buscando"], ft.Icons.SEARCH),
                              on_click=alternar_busca, tooltip="Buscar ticker")]
        for chave, titulo, opcoes, pad in menus:
            chips.append(chip_menu(titulo, f[chave], opcoes, lambda v, c=chave: definir(c, v), pad))
        chips.append(chip_menu("Ordenar", f["ordem"], ordens, lambda v: definir("ordem", v), ordem_padrao,
                               sempre_valor=True))
        chips.append(ft.Container(
            content=chip("", False, ft.Icons.ARROW_DOWNWARD if f["desc"] else ft.Icons.ARROW_UPWARD),
            on_click=inverter, tooltip="Decrescente" if f["desc"] else "Crescente"))
        filtrado = any(f[k] != padrao[k] for k in ("busca",) + tuple(m[0] for m in menus))
        if filtrado:
            chips.append(ft.Container(content=chip("Limpar", False, ft.Icons.FILTER_ALT_OFF), on_click=limpar))
        controles = [ft.Row(scroll=ft.ScrollMode.HIDDEN, spacing=8, controls=chips)]
        if f["buscando"] or f["busca"]:
            controles.append(ft.TextField(
                value=f["busca"], hint_text="Buscar ticker", dense=True, autofocus=not f["busca"],
                prefix_icon=ft.Icons.SEARCH, capitalization=ft.TextCapitalization.CHARACTERS, on_change=digitou))
        return controles

    def lotes_filtrados(self):
        f = self.f_lotes
        lotes = list(self.d["lotes"])
        if f["situacao"] == "Em aberto":
            lotes = [l for l in lotes if nc.restante(l) > 0]
        elif f["situacao"] == "Vendidos":
            lotes = [l for l in lotes if nc.restante(l) == 0]
        if f["tipo"] != "Todos":
            lotes = [l for l in lotes if l["tipo"] == f["tipo"]]
        if f["busca"]:
            lotes = [l for l in lotes if f["busca"] in l["ticker"]]

        def resultado(l):
            res = nc.resultado_aberto(l, self.cotacoes.preco(l["ticker"]))
            return res[0] if res else float("-inf")

        chaves = {"data": lambda l: l["data_compra"], "ticker": lambda l: l["ticker"], "qtd": lambda l: l["qtd"],
                  "preco": lambda l: l["preco"], "total": lambda l: l["qtd"] * l["preco"],
                  "atual": lambda l: (self.cotacoes.preco(l["ticker"]) if nc.restante(l) > 0 else None)
                  or float("-inf"),
                  "resultado": resultado, "restante": nc.restante}
        if f["ordem"] in chaves:
            lotes.sort(key=chaves[f["ordem"]], reverse=f["desc"])
        elif f["desc"]:
            lotes.reverse()
        return lotes

    def vendas_filtradas(self, ops):
        f = self.f_vendas
        ops = list(ops)
        if f["operacao"] != "Todas":
            ops = [o for o in ops if o["regime"].startswith(f["operacao"])]
        if f["tipo"] != "Todos":
            ops = [o for o in ops if o["tipo"] == f["tipo"]]
        if f["busca"]:
            ops = [o for o in ops if f["busca"] in o["ticker"]]
        chaves = {"data": lambda o: o["data"], "ticker": lambda o: o["ticker"], "qtd": lambda o: o["qtd"],
                  "preco": lambda o: o["preco"], "bruto": lambda o: o["bruto"], "liquido": lambda o: o["liquido"],
                  "imposto": lambda o: o["imposto"], "taxas": lambda o: o["taxas"] + o["corretagem"]}
        ops.sort(key=chaves.get(f["ordem"], chaves["data"]), reverse=f["desc"])
        return ops

    def preencher_listas(self, r=None, atualizar=False):
        """Recria só os itens das listas (sem refazer a tela, para não perder o foco da busca)."""
        if self.col_lotes is None:
            return
        r = r or nc.apurar(self.d)
        editavel = not self.visao and not self.d["fechado"]
        total = len(self.d["lotes"])
        lotes = self.lotes_filtrados()
        if lotes:
            vazio_lotes = []
        elif not total:
            vazio_lotes = [ft.Column(horizontal_alignment=ft.CrossAxisAlignment.CENTER, spacing=10, controls=[
                ft.Icon(ft.Icons.INVENTORY_2_OUTLINED, size=40, color=MUTED),
                texto("Nenhuma compra neste mês", 14, ft.FontWeight.BOLD),
                texto("Cadastre a primeira compra para começar.", 12, cor=MUTED),
                botao_primario("Nova compra", ft.Icons.ADD, lambda e: self.form_compra()) if editavel else ft.Container()])]
        else:
            vazio_lotes = [texto("Nenhum ativo para esse filtro.", 13, cor=MUTED)]
        self.col_lotes.controls = [self.item_lote(l, editavel) for l in lotes] or vazio_lotes
        self.cont_lotes.content.value = str(total) if len(lotes) == total else f"{len(lotes)}/{total}"
        ops = self.vendas_filtradas(r["ops"])
        self.col_vendas.controls = [self.item_venda(o, editavel) for o in ops] or [
            texto("Nenhuma venda registrada neste mês." if not r["ops"] else "Nenhuma venda para esse filtro.",
                  13, cor=MUTED)]
        n = len(r["ops"])
        self.cont_vendas.content.value = str(n) if len(ops) == n else f"{len(ops)}/{n}"
        if atualizar:
            try:
                for c in (self.col_lotes, self.col_vendas, self.cont_lotes, self.cont_vendas):
                    c.update()
            except Exception:
                traceback.print_exc()

    def cotacoes_chegaram(self):
        if self.aba == 0:
            self.preencher_listas(atualizar=True)

    def item_lote(self, l, editavel):
        st = nc.status_lote(l)
        cor_st = MUTED if st == "Vendido" else (AMARELO if st == "Vendido parcial" else VERDE)
        linha_atual = ft.Container()
        if nc.restante(l) > 0:
            atual = self.cotacoes.preco(l["ticker"])
            res = nc.resultado_aberto(l, atual)
            if atual:
                linha_atual = ft.Row(spacing=6, wrap=True, controls=[
                    texto(f"Atual: {brl(atual)}", 12, ft.FontWeight.BOLD),
                    texto(nc.fmt_resultado(res), 12, ft.FontWeight.BOLD, cor_resultado(res[0]) if res else None)])
            else:
                linha_atual = texto("Atual: carregando…" if l["ticker"] not in self.cotacoes.precos
                                    else "Atual: sem cotação", 12, cor=MUTED)
        tile = ft.Container(
            padding=ft.Padding.all(14), border_radius=ft.BorderRadius.all(14), bgcolor=ft.Colors.SURFACE_CONTAINER,
            content=ft.Row(vertical_alignment=ft.CrossAxisAlignment.CENTER, controls=[
                ft.Column(expand=True, spacing=2, controls=[
                    ft.Row(spacing=8, controls=[texto(l["ticker"], 16, ft.FontWeight.BOLD),
                                                pilula(l["tipo"], ft.Colors.SURFACE_CONTAINER_HIGHEST, MUTED, 10)]),
                    texto(f"{fmt_data(l['data_compra'])} · {l['qtd']} × {brl(l['preco'])}", 12, cor=MUTED),
                    linha_atual,
                    texto(st, 12, ft.FontWeight.BOLD, cor_st)]),
                ft.Column(spacing=2, horizontal_alignment=ft.CrossAxisAlignment.END, controls=[
                    texto(brl(l["qtd"] * l["preco"]), 15, ft.FontWeight.BOLD),
                    texto(f"Restante: {nc.restante(l)}", 12, cor=MUTED)])]))
        if not editavel:
            return tile
        return menu_contexto(tile, self.menu_lote(l))

    def menu_lote(self, l):
        opcoes = [menu_cabecalho(l["ticker"], f"{fmt_data(l['data_compra'])} · {l['qtd']} × {brl(l['preco'])}")]
        if nc.restante(l) > 0:
            opcoes.append(ft.PopupMenuItem(content=ft.Text("Registrar venda"), icon=ft.Icon(ft.Icons.SELL),
                                           on_click=lambda e: self.form_venda(lote_id=l["id"])))
        opcoes.append(ft.PopupMenuItem(content=ft.Text("Editar compra"), icon=ft.Icon(ft.Icons.EDIT_OUTLINED),
                                       on_click=lambda e: self.form_compra(editar=l)))
        opcoes.append(ft.PopupMenuItem())  # separador
        opcoes.append(ft.PopupMenuItem(content=ft.Text("Excluir compra", color=VERMELHO),
                                       icon=ft.Icon(ft.Icons.DELETE_OUTLINE, color=VERMELHO),
                                       on_click=lambda e: self.excluir_lote(l)))
        return opcoes

    def item_venda(self, o, editavel):
        tile = ft.Container(
            padding=ft.Padding.all(14), border_radius=ft.BorderRadius.all(14), bgcolor=ft.Colors.SURFACE_CONTAINER,
            content=ft.Row(vertical_alignment=ft.CrossAxisAlignment.CENTER, controls=[
                ft.Column(expand=True, spacing=2, controls=[
                    ft.Row(spacing=8, controls=[texto(o["ticker"], 16, ft.FontWeight.BOLD),
                                                pilula(o["regime"], ft.Colors.SURFACE_CONTAINER_HIGHEST, MUTED, 10)]),
                    texto(f"{fmt_data(o['data'])} · {o['qtd']} × {brl(o['preco'])}", 12, cor=MUTED),
                    texto(f"Taxas B3: {brl(o['taxas'] + o['corretagem'])}", 12, cor=MUTED)]),
                ft.Column(spacing=2, horizontal_alignment=ft.CrossAxisAlignment.END, controls=[
                    texto(brl(o["liquido"]), 15, ft.FontWeight.BOLD, cor_resultado(o["liquido"])),
                    texto(f"Imposto: {brl(o['imposto'])}", 12, cor=MUTED)])]))
        if not editavel:
            return tile
        return menu_contexto(tile, self.menu_venda(o))

    def menu_venda(self, o):
        def excluir(e):
            self.perguntar("Excluir venda", "Excluir esta venda?", "Excluir", perigo=True,
                           ao_sim=lambda: self.mutar(lambda d: [l.update(vendas=[v for v in l["vendas"]
                                                                                if v["id"] != o["venda_id"]])
                                                                for l in d["lotes"]]))

        def editar(e):
            par = next(((l, v) for l in self.d["lotes"] for v in l["vendas"] if v["id"] == o["venda_id"]), None)
            if par:
                self.form_venda(editar=par)

        return [menu_cabecalho(f"Venda de {o['ticker']}", f"{fmt_data(o['data'])} · {o['qtd']} × {brl(o['preco'])}"),
                ft.PopupMenuItem(content=ft.Text("Editar venda"), icon=ft.Icon(ft.Icons.EDIT_OUTLINED), on_click=editar),
                ft.PopupMenuItem(),  # separador
                ft.PopupMenuItem(content=ft.Text("Excluir venda", color=VERMELHO),
                                 icon=ft.Icon(ft.Icons.DELETE_OUTLINE, color=VERMELHO), on_click=excluir)]

    def excluir_lote(self, l):
        msg = f"Excluir {l['ticker']}" + (" e todas as vendas dele?" if l["vendas"] else "?")
        self.perguntar("Excluir compra", msg, "Excluir", perigo=True,
                       ao_sim=lambda: self.mutar(lambda d: d.update(lotes=[x for x in d["lotes"] if x["id"] != l["id"]])))

    def mutar(self, funcao):
        """Altera o mês atual a partir do arquivo (nunca de uma cópia antiga) e agenda a sincronização."""
        with nc.TRAVA:
            d = nc.carregar(self.mes)
            funcao(d)
            nc.salvar(d)
            self.d = d
        self.agendar_sync()
        self.render()

    def abrir_meses(self, e=None):
        com_dados = set(self.dados_amigo) if self.visao else set(nc.listar_meses())
        maximo = date.today().strftime("%Y-%m")
        estado = {"ano": int(self.mes[:4])}
        grade = ft.Row(wrap=True, spacing=8, run_spacing=8, width=300)
        titulo = texto("", 16, ft.FontWeight.BOLD)

        def escolher(m):
            self.page.pop_dialog()
            self.trocar_mes(m)

        def desenhar():
            titulo.value = str(estado["ano"])
            grade.controls = []
            for i, nome in enumerate(MESES_CURTOS):
                m = f"{estado['ano']:04d}-{i + 1:02d}"
                atual = m == self.mes
                grade.controls.append(ft.Container(
                    width=90, height=44, alignment=ft.Alignment.CENTER, border_radius=ft.BorderRadius.all(10),
                    bgcolor=VERDE if atual else (ft.Colors.with_opacity(0.18, VERDE) if m in com_dados else
                                                 ft.Colors.SURFACE_CONTAINER_HIGHEST),
                    disabled=m > maximo, opacity=0.35 if m > maximo else 1,
                    on_click=lambda e, m=m: escolher(m),
                    content=texto(nome, 14, ft.FontWeight.BOLD,
                                  "#ffffff" if atual else (VERDE if m in com_dados else None))))

        def mover(passo):
            estado["ano"] += passo
            desenhar()
            dlg.update()

        desenhar()
        dlg = ft.AlertDialog(
            title=ft.Row(alignment=ft.MainAxisAlignment.SPACE_BETWEEN, controls=[
                ft.IconButton(ft.Icons.CHEVRON_LEFT, on_click=lambda e: mover(-1)), titulo,
                ft.IconButton(ft.Icons.CHEVRON_RIGHT, on_click=lambda e: mover(1))]),
            content=ft.Column(tight=True, controls=[grade, texto("Verde: meses com operações", 11, cor=MUTED)]),
            actions=[ft.TextButton("Mês atual", on_click=lambda e: escolher(maximo)),
                     ft.TextButton("Fechar", on_click=lambda e: self.page.pop_dialog())])
        self.page.show_dialog(dlg)

    def trocar_mes(self, mes):
        self.mes = mes
        self.d = (self.dados_amigo.get(mes) or nc.mes_vazio(mes)) if self.visao else nc.carregar(mes)
        self.render()

    def fechar_mes(self, e=None):
        """Antes de fechar, verifica as metas do mês: um alvo já atingido é registrado e uma consulta que falhou
        bloqueia o fechamento (fechar poderia invalidar a meta)."""
        if not ms.metas_ativas(self.cfg):
            return self.confirmar_fechamento()
        mes = self.mes
        self.aviso("Verificando as metas antes de fechar…")

        def trabalho():
            try:
                res = ms.preparar_fechamento(self.cfg, mes, mk.historico_desde)
            except Exception as ex:
                traceback.print_exc()
                res = {"bloqueio": f"Falha ao verificar as metas antes de fechar: {str(ex)[:120]}",
                       "executadas": [], "invalidas": []}
            if self.mes != mes:
                return
            if res["bloqueio"]:
                self.page.show_dialog(ft.AlertDialog(
                    title=ft.Text("Não foi possível fechar o mês"), content=ft.Text(res["bloqueio"]),
                    actions=[ft.FilledButton("OK", on_click=lambda e: self.page.pop_dialog())]))
                return
            if res["executadas"] or res["invalidas"]:
                with nc.TRAVA:
                    if not self.visao:
                        self.d = nc.carregar(self.mes)
                self.agendar_sync()
                self.render(todas=True)
                for m in res["executadas"]:
                    self.aviso(f"Meta atingida: {m['ticker']} vendida a {brl(m['execucao']['preco_usado'])}.")
                for m in res["invalidas"]:
                    self.aviso(f"Meta inválida ({m['ticker']}): {m.get('ultimo_erro', '')}")
            self.confirmar_fechamento()
        self.page.run_thread(trabalho)

    def confirmar_fechamento(self):
        r = nc.apurar(self.d)

        def confirmar():
            with nc.TRAVA:
                r2, prox = nc.fechar_mes(nc.carregar(self.mes))
                self.d = nc.carregar(self.mes)
            self.agendar_sync()
            self.render()
            self.page.show_dialog(ft.AlertDialog(title=ft.Text("Mês fechado"),
                                                 content=ft.Text(nc.mensagem_fechamento(r2, prox)),
                                                 actions=[ft.FilledButton("OK", on_click=lambda e: self.page.pop_dialog())]))

        self.perguntar(f"Fechar {fmt_mes(self.mes)}",
                       f"Depois de fechado, o mês não pode ser alterado.\n\nTotal da DARF: {brl(r['darf'])}",
                       "Fechar mês", confirmar)

    # ------------------------------------------------------------ formulários
    def _chips(self, tickers, ao_escolher):
        linha = ft.Row(wrap=True, spacing=6, run_spacing=6, controls=[
            ft.Chip(label=ft.Text(t), on_click=lambda e, t=t: ao_escolher(t)) for t in tickers])
        return linha

    def _marcar(self, linha, ticker):
        for c in linha.controls:
            c.bgcolor = ft.Colors.with_opacity(0.25, VERDE) if c.label.value == ticker else None

    def form_compra(self, ini=None, editar=None):
        if self.visao or self.d["fechado"]:
            return
        ini = ini or {}
        maximo = date.today()
        if editar:
            ini = {"ticker": editar["ticker"], "tipo": editar["tipo"], "qtd": str(editar["qtd"]),
                   "preco": nc.fmt_num(editar["preco"])}
            if editar["vendas"]:
                maximo = min(maximo, date.fromisoformat(min(v["data"] for v in editar["vendas"])))
        sugestoes, tipos = nc.sugestoes(self.d)
        tk = ft.TextField(label="Ticker *", value=ini.get("ticker", ""), hint_text="Ex.: PETR4",
                          capitalization=ft.TextCapitalization.CHARACTERS)
        tipo = texto("", 12, ft.FontWeight.BOLD, MUTED)

        def mostrar_tipo(t):
            tipo.value = f"Tipo: {nc.tipo_por_ticker(t)} (identificado pelo ticker)" if len(t) >= 5 else ""

        mostrar_tipo((ini.get("ticker") or "").upper())
        data = CampoData(self, "Data da compra *", valor=date.fromisoformat(editar["data_compra"]) if editar
                         else date.today(), maximo=maximo, ao_mudar=lambda d: calcular_total())
        qtd = ft.TextField(label="Quantidade *", keyboard_type=ft.KeyboardType.NUMBER, value=ini.get("qtd", ""))
        preco = ft.TextField(label="Preço unitário (R$) *", keyboard_type=ft.KeyboardType.NUMBER,
                             value=ini.get("preco", ""), hint_text="Ex.: 32,50")
        erro = texto("", 12, cor=VERMELHO)
        resumo = ResumoOrdem()

        def calcular_resumo():
            v = numeros_ordem(qtd.value, preco.value)
            if not v or not data.valor:
                return resumo.mostrar(None)
            resumo.mostrar(nc.resumo_ordem("compra", v[0], v[1], data.valor),
                           "Se vender no mesmo dia (day trade), a B3 liquida só o resultado do dia.")

        calcular_resumo()

        def calcular_total(e=None):
            calcular_resumo()
            try:
                dlg.update()
            except Exception:
                pass

        qtd.on_change = calcular_total
        preco.on_change = calcular_total

        def escolher(t):
            tk.value = t
            mostrar_tipo(t)
            self._marcar(chips, t)
            dlg.update()

        chips = self._chips(sugestoes, escolher)
        if ini.get("ticker"):
            self._marcar(chips, ini["ticker"])

        def digitou(e):
            t = (tk.value or "").strip().upper()
            self._marcar(chips, t)
            mostrar_tipo(t)
            dlg.update()

        tk.on_change = digitou

        def salvar(e):
            t = (tk.value or "").strip().upper()
            try:
                if not t:
                    raise ValueError("Informe o ticker.")
                if not data.valor:
                    raise ValueError("Selecione a data da compra.")
                try:
                    q = nc.parse_qtd(qtd.value or "")
                except ValueError:
                    raise ValueError("Quantidade inválida.")
                try:
                    p = nc.parse_num(preco.value or "")
                except ValueError:
                    raise ValueError("Preço inválido.")
            except ValueError as ex:
                erro.value = str(ex)
                dlg.update()
                return
            novo = {"ticker": t, "tipo": nc.tipo_por_ticker(t), "data_compra": data.valor.isoformat(), "qtd": q, "preco": p}
            if editar:
                lid = editar["id"]

                def aplicar(d):
                    alvo = next((x for x in d["lotes"] if x["id"] == lid), None)
                    if alvo is None:
                        raise ValueError("A compra foi excluída em outro aparelho.")
                    msg = nc.erro_edicao_lote(alvo, novo)
                    if msg:
                        raise ValueError(msg)
                    alvo.update(novo)

                msg = nc.erro_edicao_lote(editar, novo)
                if msg:
                    erro.value = msg
                    dlg.update()
                    return
                self.page.pop_dialog()
                try:
                    self.mutar(aplicar)
                except ValueError as ex:
                    self.aviso(str(ex))
                return
            lote = {"id": nc.novo_id(), **novo, "vendas": []}
            self.page.pop_dialog()
            self.mutar(lambda d: d["lotes"].append(lote))
            self.perguntar("Venda", f"Você já fez a venda de {t}?", "Sim, registrar venda",
                           lambda: self.form_venda(lote_id=lote["id"]), nao="Ainda não")

        conteudo = [tk]
        if sugestoes:
            conteudo += [texto("Frequentes", 11, cor=MUTED), chips]
        conteudo += [tipo, data.controle, qtd, preco, resumo.controle, erro]
        if editar and editar["vendas"]:
            conteudo.insert(0, texto(f"Já vendidas: {nc.vendido(editar)}", 12, cor=MUTED))
        dlg = ft.AlertDialog(title=ft.Text("Editar compra" if editar else "Novo ativo"), scrollable=True,
                             content=ft.Container(width=380, content=ft.Column(tight=True, spacing=12,
                                                                               controls=conteudo)),
                             actions=[ft.TextButton("Cancelar", on_click=lambda e: self.page.pop_dialog()),
                                      ft.FilledButton("Salvar", on_click=salvar)])
        self.page.show_dialog(dlg)

    def form_venda(self, lote_id=None, ticker="", editar=None):
        """editar=(compra, venda): edita a venda; a compra fica fixa."""
        if self.visao or self.d["fechado"]:
            return
        if editar:
            base = nc.sem_venda(editar[0], editar[1]["id"])
            abertos = [base]
            lote_id = base["id"]
            sugestoes = []
        else:
            abertos = [l for l in self.d["lotes"] if nc.restante(l) > 0]
            if not abertos:
                self.aviso("Não há compras em aberto neste mês.")
                return
            sugestoes, _ = nc.sugestoes(self.d, so_custodia=True)
        inicio_mes, fim_mes = nc.limites_mes(self.mes)
        estado = {"ticker": None, "lote": None}
        tk = ft.TextField(label="Ticker *", hint_text="Ex.: PETR4", capitalization=ft.TextCapitalization.CHARACTERS)
        compra = ft.Dropdown(label="Compra *", options=[], expand=True)
        info = texto("", 12, cor=MUTED)
        qtd = ft.TextField(label="Quantidade *", keyboard_type=ft.KeyboardType.NUMBER)
        preco = ft.TextField(label="Preço unitário (R$) *", keyboard_type=ft.KeyboardType.NUMBER, hint_text="Ex.: 35,10")
        preco_info = texto("", 11, cor=MUTED)
        erro = texto("", 12, cor=VERMELHO)
        resumo = ResumoOrdem()
        auto = {"preco": "", "pedido": None}  # último preço sugerido e a busca em andamento

        def atualizar_dlg():
            try:
                dlg.update()
            except Exception:  # diálogo ainda não exibido ou já fechado
                pass

        def calcular_resumo():
            l = estado["lote"]
            v = numeros_ordem(qtd.value, preco.value)
            if not v or not l or not data.valor:
                return resumo.mostrar(None)
            dt = data.valor.isoformat() == l["data_compra"]
            resumo.mostrar(nc.resumo_ordem("venda", v[0], v[1], data.valor, preco_compra=l["preco"], day_trade=dt),
                           "Day trade (compra e venda no mesmo dia): a B3 liquida só o resultado, já com o IRRF "
                           "de 1% sobre o lucro." if dt else "Swing trade: crédito do valor da venda menos as taxas.")

        def calcular_total(e=None):
            calcular_resumo()
            atualizar_dlg()

        qtd.on_change = calcular_total
        preco.on_change = calcular_total

        def preco_digitado():
            return (preco.value or "").strip() not in ("", auto["preco"])

        def sugerir_preco():
            """Cotação atual (venda hoje) ou fechamento da data escolhida; não sobrescreve o que foi digitado."""
            l = estado["lote"]
            if editar or not l or not data.valor or preco_digitado():
                return
            pedido = (l["ticker"], data.valor)
            if pedido == auto["pedido"]:
                return
            auto["pedido"] = pedido
            preco_info.value = "Buscando cotação…"

            def trabalho():
                try:
                    valor, origem = self.mercado.preco_venda(*pedido)
                except Exception:
                    if auto["pedido"] == pedido:
                        auto["pedido"] = None
                        preco_info.value = "Não foi possível buscar a cotação. Informe o preço."
                else:
                    if auto["pedido"] != pedido or preco_digitado():
                        return
                    auto["preco"] = nc.preco_texto(valor)
                    preco.value = auto["preco"]
                    preco_info.value = f"{origem} · pode alterar"
                    calcular_resumo()
                atualizar_dlg()

            self.page.run_thread(trabalho)

        def mudou_data(d):
            sugerir_preco()
            calcular_resumo()
            atualizar_dlg()

        data = CampoData(self, "Data da venda *", minimo=inicio_mes, maximo=min(fim_mes, date.today()),
                         ao_mudar=mudou_data)

        def selecionar_lote(lid):
            l = next((x for x in abertos if x["id"] == lid), None)
            estado["lote"] = l
            if not l:
                info.value = ""
                return
            disp = nc.restante(l)
            minimo = max(date.fromisoformat(l["data_compra"]), inicio_mes)
            maximo = min(fim_mes, date.today())
            info.value = f"{l['tipo']} · Custo {brl(l['preco'])} · Disponível: {disp}"
            if minimo > maximo:
                info.value += "\nNão há data válida para vender essa compra neste mês."
            qtd.label = f"Quantidade * (máx. {disp})"
            qtd.value = str(disp)
            data.set_limites(minimo, maximo)
            hoje = date.today()
            if not data.valor and minimo <= hoje <= maximo:
                data.valor = hoje
                data.valor_txt.value = hoje.strftime("%d/%m/%Y")
            sugerir_preco()
            calcular_resumo()

        def selecionar_ticker(t, lote_inicial=None):
            t = (t or "").strip().upper()
            if t == estado["ticker"] and not lote_inicial:
                return
            estado["ticker"] = t
            self._marcar(chips, t)
            lotes = [l for l in abertos if l["ticker"] == t]
            compra.options = [ft.DropdownOption(
                key=l["id"], text=f"{fmt_data(l['data_compra'])} · {brl(l['preco'])} · {nc.restante(l)} disp.")
                for l in lotes]
            if lotes:
                alvo = lote_inicial if lote_inicial in [l["id"] for l in lotes] else lotes[0]["id"]
                compra.value = alvo
                compra.disabled = False
                selecionar_lote(alvo)
            else:
                compra.value = None
                compra.disabled = True
                estado["lote"] = None
                info.value = "Nenhuma compra em aberto desse ticker" if t else "Escolha um ticker"
                qtd.label = "Quantidade *"
                calcular_resumo()

        def escolher(t):
            tk.value = t
            selecionar_ticker(t)
            dlg.update()

        chips = self._chips(sugestoes, escolher)

        def digitou(e):
            selecionar_ticker(tk.value)
            dlg.update()

        def mudou_lote(e):
            selecionar_lote(e.control.value)
            dlg.update()

        tk.on_change = digitou
        compra.on_select = mudou_lote

        inicial = next((l for l in abertos if l["id"] == lote_id), None)
        t0 = inicial["ticker"] if inicial else ticker
        if t0:
            tk.value = t0
            selecionar_ticker(t0, lote_inicial=lote_id)
        else:
            selecionar_ticker("")
        if editar:
            v0 = editar[1]
            tk.disabled = compra.disabled = True
            data.valor = date.fromisoformat(v0["data"])
            data.valor_txt.value = data.valor.strftime("%d/%m/%Y")
            qtd.value = str(v0["qtd"])
            preco.value = nc.fmt_num(v0["preco"])
            calcular_resumo()

        def salvar(e):
            l = estado["lote"]
            try:
                if not l:
                    raise ValueError("Escolha o ticker e a compra que foi vendida.")
                if not data.valor:
                    raise ValueError("Selecione a data da venda.")
                try:
                    q = nc.parse_qtd(qtd.value or "")
                except ValueError:
                    raise ValueError("Quantidade inválida.")
                if q > nc.restante(l):
                    raise ValueError(f"Quantidade maior que a disponível ({nc.restante(l)}).")
                try:
                    p = nc.parse_num(preco.value or "")
                except ValueError:
                    raise ValueError("Preço inválido.")
            except ValueError as ex:
                erro.value = str(ex)
                dlg.update()
                return
            venda = {"id": editar[1]["id"] if editar else nc.novo_id(), "data": data.valor.isoformat(),
                     "qtd": q, "preco": p}
            lid = l["id"]

            def aplicar(d):
                alvo = next((x for x in d["lotes"] if x["id"] == lid), None)
                mudou = "A compra foi alterada em outro aparelho. Abra a venda novamente."
                if alvo is None:
                    raise ValueError(mudou)
                if editar:
                    existente = next((x for x in alvo["vendas"] if x["id"] == venda["id"]), None)
                    if existente is None:
                        raise ValueError("A venda foi excluída em outro aparelho.")
                    if nc.restante(nc.sem_venda(alvo, venda["id"])) < q:
                        raise ValueError(mudou)
                    existente.update(data=venda["data"], qtd=q, preco=p)
                else:
                    if nc.restante(alvo) < q:
                        raise ValueError(mudou)
                    alvo["vendas"].append(venda)

            self.page.pop_dialog()
            try:
                self.mutar(aplicar)
            except ValueError as ex:
                self.aviso(str(ex))

        conteudo = [tk]
        if sugestoes:
            conteudo += [texto("Em carteira", 11, cor=MUTED), chips]
        conteudo += [compra, info, data.controle, qtd, preco, preco_info, resumo.controle, erro]
        dlg = ft.AlertDialog(title=ft.Text("Editar venda" if editar else "Registrar venda"), scrollable=True,
                             content=ft.Container(width=380, content=ft.Column(tight=True, spacing=12,
                                                                               controls=conteudo)),
                             actions=[ft.TextButton("Cancelar", on_click=lambda e: self.page.pop_dialog()),
                                      ft.FilledButton("Salvar", on_click=salvar)])
        self.page.show_dialog(dlg)

    # ------------------------------------------------------------ caixa (tesouraria)
    def tela_caixa(self):
        hoje = date.today()
        self.dia_caixa = hoje
        amigo = self.visao
        if amigo:
            r = nc.resumo_caixa({"caixa": self.amigo_caixa or {}}, hoje, meses=self.dados_amigo)
        else:
            r = nc.resumo_caixa(self.cfg, hoje)
        itens = self.seletor_visao("Caixa")

        if r["definido"]:
            disp = texto(brl(r["disponivel"]), 32, ft.FontWeight.BOLD, VERMELHO if r["disponivel"] < 0 else None)
            info = texto(f"Saldo informado em {r['base']:%d/%m/%Y}. As liquidações seguintes entram sozinhas "
                         "quando a data chega.", 12, cor=MUTED)
        else:
            disp = texto("—", 32, ft.FontWeight.BOLD)
            info = texto(f"{amigo} ainda não informou o saldo da conta." if amigo else
                         "Informe o saldo livre na conta da corretora para acompanhar o caixa.", 12, cor=MUTED)
        editar = [] if amigo else [
            ft.FilledButton("Editar", icon=ft.Icons.EDIT_OUTLINED, on_click=lambda e: self.editar_saldo(),
                            style=ft.ButtonStyle(bgcolor=PRIMARIO, color=PRIMARIO_TXT))]
        itens.append(bloco(ft.Column(spacing=6, controls=[
            ft.Row(vertical_alignment=ft.CrossAxisAlignment.CENTER, controls=[
                rotulo("Saldo disponível (D+0)"), ft.Container(expand=True), *editar]),
            disp, info]), padding=20))

        def card(titulo, valor, sub, cor=None):
            return ft.Container(expand=True, padding=ft.Padding.all(14), border_radius=ft.BorderRadius.all(16),
                                bgcolor=ft.Colors.SURFACE_CONTAINER, content=ft.Column(spacing=4, controls=[
                                    rotulo(titulo), texto(valor, 17, ft.FontWeight.BOLD, cor), texto(sub, 11, cor=MUTED)]))

        partes = []
        if r["a_debitar"]:
            partes.append(f"{brl(r['a_debitar'])} a debitar")
        if r["a_receber"]:
            partes.append(f"+{brl(r['a_receber'])} a receber")
        t = r["transito"]
        itens.append(ft.Row(spacing=10, vertical_alignment=ft.CrossAxisAlignment.START, controls=[
            card("Em trânsito (D+1/D+2)", brl(t), "\n".join(partes) or "Nada pendente", cor_resultado(round(t, 2))),
            card("Saldo projetado", brl(r["projetado"]) if r["definido"] else "—", "Disponível + liquidações futuras",
                 VERMELHO if r["definido"] and r["projetado"] < 0 else None)]))

        itens.append(texto("Agenda financeira", 17, ft.FontWeight.BOLD))
        grupos = nc.agenda_caixa(r, hoje)
        pendentes = [g for g in grupos if g[0] > hoje]
        liquidados = [g for g in grupos if g[0] <= hoje][::-1]
        if not grupos:
            itens.append(ft.Column(horizontal_alignment=ft.CrossAxisAlignment.CENTER, spacing=8, controls=[
                ft.Icon(ft.Icons.EVENT_AVAILABLE, size=40, color=MUTED),
                texto("Nenhum lançamento", 14, ft.FontWeight.BOLD),
                texto("Compras e vendas aparecem aqui com a data de liquidação (D+2 úteis).", 12, cor=MUTED)]))
        elif not pendentes:
            itens.append(texto("Nenhuma liquidação pendente.", 13, cor=MUTED))

        def grupo(rot, total, lancs):
            sinal = "+" if total > 0.004 else ""
            linhas = []
            for it in lancs:
                v = it["valor"]
                linhas.append(ft.Row(vertical_alignment=ft.CrossAxisAlignment.CENTER, controls=[
                    ft.Column(spacing=0, expand=True, controls=[
                        texto(f"{it['ticker']} · {it['tipo']}", 14, ft.FontWeight.BOLD),
                        texto(f"Operação {fmt_data(it['data'])} · {it['status']}", 12, cor=MUTED)]),
                    texto(("+" if v > 0.004 else "") + brl(v), 14, ft.FontWeight.BOLD, cor_resultado(round(v, 2)))]))
            return bloco(ft.Column(spacing=10, controls=[
                ft.Row(controls=[texto(rot, 14, ft.FontWeight.BOLD), ft.Container(expand=True),
                                 texto(f"{sinal}{brl(total)}", 14, ft.FontWeight.BOLD, cor_resultado(round(total, 2)))]),
                ft.Divider(height=1), *linhas]), padding=14)

        for d, rot, total, lancs in pendentes:
            itens.append(grupo(rot, total, lancs))
        if liquidados:
            itens.append(rotulo("Liquidados recentemente"))
            for d, rot, total, lancs in liquidados:
                itens.append(grupo(rot, total, lancs))
        itens.append(ft.Container(height=24))
        return ft.ListView(controls=itens, padding=ft.Padding.all(16), spacing=12, expand=True)

    def editar_saldo(self):
        r = nc.resumo_caixa(self.cfg)
        modos = ["Definir saldo", "Aporte", "Retirada"] if r["definido"] else ["Definir saldo"]
        modo = ft.SegmentedButton(selected=[modos[0]], show_selected_icon=False,
                                  segments=[ft.Segment(value=m, label=ft.Text(m)) for m in modos])
        campo = ft.TextField(label="Saldo disponível hoje (R$) *", keyboard_type=ft.KeyboardType.NUMBER,
                             value=nc.preco_texto(r["disponivel"]) if r["definido"] else "", hint_text="Ex.: 10.000,00")
        ajuda = texto("Use o saldo livre que a corretora mostra hoje, já com as liquidações de hoje.", 12, cor=MUTED)
        erro = texto("", 12, cor=VERMELHO)

        def trocou(e):
            m = modo.selected[0] if modo.selected else modos[0]
            if m == "Definir saldo":
                campo.label = "Saldo disponível hoje (R$) *"
                ajuda.value = "Use o saldo livre que a corretora mostra hoje, já com as liquidações de hoje."
            else:
                campo.label = f"Valor do {m.lower()} (R$) *"
                campo.value = ""
                ajuda.value = "Soma ao saldo disponível." if m == "Aporte" else "Desconta do saldo disponível."
            dlg.update()

        modo.on_change = trocou

        def salvar(e):
            m = modo.selected[0] if modo.selected else modos[0]
            try:
                valor = nc.parse_valor(campo.value)
            except ValueError:
                erro.value = "Valor inválido."
                dlg.update()
                return
            if m != "Definir saldo" and valor <= 0:
                erro.value = "Informe um valor maior que zero."
                dlg.update()
                return
            self.page.pop_dialog()
            with nc.TRAVA:
                if m == "Definir saldo":
                    nc.definir_saldo(self.cfg, valor)
                else:
                    nc.ajustar_saldo(self.cfg, valor if m == "Aporte" else -valor)
                self.cfg["pendente"] = True
                nc.gravar_config(self.cfg)
            self.agendar_sync()
            self.render()

        sub = [texto(f"Saldo disponível hoje: {brl(r['disponivel'])}", 13, cor=MUTED)] if r["definido"] else []
        dlg = ft.AlertDialog(title=ft.Text("Saldo em conta"), scrollable=True,
                             content=ft.Container(width=380, content=ft.Column(tight=True, spacing=12, controls=[
                                 *sub, modo, campo, ajuda, erro])),
                             actions=[ft.TextButton("Cancelar", on_click=lambda e: self.page.pop_dialog()),
                                      ft.FilledButton("Salvar", on_click=salvar)])
        self.page.show_dialog(dlg)

    # ------------------------------------------------------------ radar
    def tela_radar(self):
        amigo = self.visao
        legenda = ft.Row(wrap=True, spacing=6, run_spacing=6, controls=[
            pilula(f"{rot} · {faixa}", fundo, txt, 10) for (lim, rot, fundo, txt), faixa in
            zip(mk.FAIXAS_RISCO, ("< 2,2%", "2,2% a 3,0%", "3,0% a 4,5%", "> 4,5%"))])
        topo = [ft.Row(controls=[texto(f"Radar de {amigo}" if amigo else "Radar de Ações", 18, ft.FontWeight.BOLD,
                                       expand=True, max_lines=1, overflow=ft.TextOverflow.ELLIPSIS),
                                 ft.IconButton(ft.Icons.REFRESH, tooltip="Atualizar",
                                               on_click=lambda e: self.atualizar_radar(forcar=True))]),
                texto(self.radar_msg, 12, cor=MUTED)]
        if amigo:
            faltam = [r for r in self.amigo_radar if all(m["ticker"] != r["ticker"] for m in self.cfg["radar"])]
            topo.append(ft.FilledButton(f"Importar {len(faltam)} para o meu radar" if faltam else
                                        "Todos já estão no seu radar", icon=ft.Icons.PLAYLIST_ADD,
                                        disabled=not faltam, on_click=lambda e: self.importar_todos_radar()))
        else:
            campo = ft.TextField(label="Adicionar ticker", hint_text="Ex.: VALE3", expand=True, dense=True,
                                 capitalization=ft.TextCapitalization.CHARACTERS)

            def adicionar(e=None):
                t = (campo.value or "").strip().upper()
                if t.endswith(".SA"):
                    t = t[:-3]
                import re
                if not re.fullmatch(r"[A-Z0-9]{4,7}", t):
                    self.aviso("Ticker inválido.")
                    return
                with nc.TRAVA:
                    if nc.adicionar_radar(self.cfg, t) is None:
                        self.aviso(f"{t} já está no radar.")
                        return
                    nc.gravar_config(self.cfg)
                self.agendar_sync()
                self.render()
                self.atualizar_radar(apenas=[t])
                self.atualizar_noticias()

            campo.on_submit = adicionar
            topo.append(ft.Row(controls=[campo, ft.IconButton(ft.Icons.ADD_CIRCLE, icon_color=VERDE, icon_size=32,
                                                              on_click=adicionar)]))
        topo += [rotulo("Risco pelo ATR%"), legenda]
        todos = self.radar_lista()
        custodia = set() if amigo else nc.custodia_atual()
        lista = mk.filtrar_ordenar(todos, self.radar_dados, self.radar_filtro, self.radar_ordem, custodia)
        manual = self.radar_ordem == "manual" and self.radar_filtro == "Todos"

        def filtrar(k):
            self.radar_filtro = k
            self.render()

        def ordenar(k):
            self.radar_ordem = k
            self.cfg["radar_ordem_lista"] = k
            nc.gravar_config(self.cfg)
            self.render()

        altas, quedas, media = mk.resumo_dia([r["ticker"] for r in todos], self.radar_dados)
        filtros = [ft.Row(spacing=8, wrap=True, run_spacing=8, controls=[
            chip_menu("Mostrar", self.radar_filtro, [(f, f) for f in mk.FILTROS_RADAR], filtrar, "Todos"),
            chip_menu("Ordenar", self.radar_ordem, mk.ORDENS_RADAR, ordenar, "manual")])]
        if media is not None:
            filtros.append(texto(f"Hoje: {altas} em alta · {quedas} em queda · média {mk.fmt_pct(media)}", 12,
                                 ft.FontWeight.BOLD, cor_resultado(round(media, 2))))
        cabecalho = self.seletor_visao("Radar") + [bloco(ft.Column(spacing=10, controls=topo)), *filtros]
        if not todos:
            cabecalho.append(texto(f"{amigo} não tem ativos no radar." if amigo else
                                   "Nenhum ativo no radar. Adicione um ticker acima.", 13, cor=MUTED))
        elif not lista:
            cabecalho.append(texto("Nenhum ativo com esse filtro.", 13, cor=MUTED))
        elif not amigo and len(lista) > 1:
            cabecalho.append(texto("Toque para ver o gráfico. Toque e segure e arraste para mudar a ordem." if manual
                                   else "Toque para ver o gráfico. Para arrastar, use Ordenar: Minha ordem.", 12,
                                   cor=MUTED))
        meus = {r["ticker"] for r in self.cfg["radar"]}
        cards = [self.card_radar(item, item["ticker"] in custodia, amigo=bool(amigo), ja_tenho=item["ticker"] in meus)
                 for item in lista]
        if amigo or not manual:
            return ft.ListView(controls=cabecalho + cards + [ft.Container(height=24)], padding=ft.Padding.all(16),
                               spacing=12, expand=True)
        return ft.ReorderableListView(
            header=ft.Container(padding=ft.Padding.only(bottom=12),
                                content=ft.Column(spacing=12, controls=cabecalho)),
            footer=ft.Container(height=24), padding=ft.Padding.all(16), expand=True, on_reorder=self.reordenar_radar,
            controls=[ft.Container(key=item["ticker"], padding=ft.Padding.only(bottom=12), content=c)
                      for item, c in zip(lista, cards)])

    def reordenar_radar(self, e):
        """Soltou o card em outra posição: grava a nova ordem (sincronizada pela planilha)."""
        ordem = [r["ticker"] for r in nc.ordenar_radar(self.cfg["radar"])]
        if e.old_index is None or e.new_index is None or not 0 <= e.old_index < len(ordem):
            return
        t = ordem.pop(e.old_index)
        ordem.insert(max(0, min(e.new_index, len(ordem))), t)
        with nc.TRAVA:
            nc.reordenar_radar(self.cfg, ordem)
            nc.gravar_config(self.cfg)
        self.agendar_sync()
        self.render()

    def importar_radar(self, t):
        item = next((r for r in self.amigo_radar if r["ticker"] == t), {"nome": ""})
        with nc.TRAVA:
            if nc.adicionar_radar(self.cfg, t, item.get("nome", "")) is None:
                return
            nc.gravar_config(self.cfg)
        self.agendar_sync()
        self.aviso(f"{t} adicionado ao seu radar.")
        self.render(todas=True)
        self.atualizar_noticias()

    def importar_todos_radar(self):
        novos = [r for r in self.amigo_radar if all(m["ticker"] != r["ticker"] for m in self.cfg["radar"])]
        if not novos:
            return

        def importar():
            with nc.TRAVA:
                for r in novos:
                    nc.adicionar_radar(self.cfg, r["ticker"], r.get("nome", ""))
                nc.gravar_config(self.cfg)
            self.agendar_sync()
            self.aviso(f"{len(novos)} ativo(s) adicionados ao seu radar.")
            self.render(todas=True)
            self.atualizar_noticias()

        self.perguntar("Importar radar", f"Adicionar ao seu radar: {', '.join(r['ticker'] for r in novos)}?",
                       "Importar", importar)

    def card_radar(self, item, pode_vender, amigo=False, ja_tenho=False):
        t = item["ticker"]
        dados = self.radar_dados.get(t)
        nome = (dados or {}).get("nome") or item.get("nome") or ("Carregando…" if dados is None else "")
        erro = (dados or {}).get("erro")
        badge = ft.Container()
        if dados and dados.get("risco"):
            rot, fundo, txt = dados["risco"]
            badge = pilula(rot, fundo, txt, 10)

        def mini(titulo, valor):
            return ft.Column(spacing=0, controls=[texto(titulo, 11, cor=MUTED), texto(valor, 13, ft.FontWeight.BOLD)])

        if dados and not erro:
            pct = dados.get("atr_pct")
            vp, v = dados.get("var_pct"), dados.get("var")
            cor_v = cor_resultado(round(vp, 2)) if vp is not None else MUTED
            seta = ft.Icons.ARROW_DROP_UP if (vp or 0) > 0.0049 else (
                ft.Icons.ARROW_DROP_DOWN if (vp or 0) < -0.0049 else ft.Icons.REMOVE)
            dia = ft.Row(spacing=0, tight=True, vertical_alignment=ft.CrossAxisAlignment.CENTER, controls=[
                ft.Icon(seta, color=cor_v, size=22),
                texto(f"{mk.fmt_pct(vp)} ({'+' if (v or 0) > 0 else ''}{brl(v)})" if vp is not None else "—", 13,
                      ft.FontWeight.BOLD, cor_v)])
            corpo = [
                ft.Row(vertical_alignment=ft.CrossAxisAlignment.CENTER, controls=[
                    texto(brl(dados["preco"]), 20, ft.FontWeight.BOLD), dia, ft.Container(expand=True), badge]),
                ft.Row(spacing=20, controls=[
                    mini("Média 6 meses", brl(dados["media6m"])),
                    mini("ATR (14)", brl(dados["atr"]) if dados.get("atr") else "—"),
                    mini("ATR%", f"{pct:.2f}%".replace(".", ",") if pct is not None else "—")])]
        else:
            corpo = [texto(erro or "Carregando cotação…", 13, cor=VERMELHO if erro else MUTED)]
        if amigo:
            acoes = [ft.OutlinedButton("Já está no seu radar", icon=ft.Icons.CHECK, disabled=True) if ja_tenho else
                     botao_primario("Adicionar ao meu radar", ft.Icons.PLAYLIST_ADD, lambda e: self.importar_radar(t))]
        else:
            acoes = [
                botao_primario("Comprar", ft.Icons.ADD_SHOPPING_CART, lambda e: self.radar_comprar(t)),
                ft.OutlinedButton("Vender", icon=ft.Icons.SELL, disabled=not pode_vender,
                                  on_click=lambda e: self.radar_vender(t)),
                ft.Container(expand=True),
                ft.IconButton(ft.Icons.DELETE_OUTLINE, icon_color=VERMELHO, tooltip="Remover do radar",
                              on_click=lambda e: self.remover_radar(t))]
        cab = [logo_ativo(t), ft.Column(spacing=0, expand=True, controls=[
            texto(t, 16, ft.FontWeight.BOLD), texto(nome, 12, cor=MUTED, max_lines=1,
                                                    overflow=ft.TextOverflow.ELLIPSIS)])]
        if not amigo:
            cab.append(ft.Icon(ft.Icons.DRAG_INDICATOR, color=MUTED, size=20))
        return bloco(ft.Column(spacing=10, controls=[
            ft.Row(spacing=12, controls=cab), *corpo, ft.Row(spacing=8, controls=acoes)]), padding=14,
            ink=True, on_click=lambda e: self.abrir_grafico(t))

    # ------------------------------------------------------------ gráfico do ativo
    def abrir_grafico(self, t):
        item = next((r for r in self.radar_lista() if r["ticker"] == t), {"ticker": t, "nome": ""})
        GraficoAtivo(self, t, item.get("nome", ""), self.radar_dados.get(t) or {})

    # ------------------------------------------------------------ notícias
    def tela_noticias(self):
        d = nt.ler_estado()
        radar = [r["ticker"] for r in nc.ordenar_radar(self.cfg["radar"])]
        f = self.f_noticias
        if f["ticker"] not in radar:
            f["ticker"] = "Todos"

        def definir(chave, valor):
            f[chave] = valor
            self.render()

        def notificar(e):
            self.cfg["noticias_notificar"] = bool(e.control.value)
            nc.gravar_config(self.cfg)
            if e.control.value and no_android():
                self.page.run_thread(self.pedir_permissao_notificacao)

        if self.noticias_rodando:
            status = "Buscando notícias…"
        elif self.noticias_msg:
            status = self.noticias_msg
        elif d["hora"]:
            status = f"Atualizado às {datetime.fromtimestamp(d['hora']):%H:%M} · Google Notícias, últimos 7 dias"
            if d.get("erros"):
                status += f" · falha em {', '.join(sorted(d['erros']))}"
        else:
            status = "Google Notícias · ativos do Radar de Ações"
        cabecalho = bloco(ft.Column(spacing=8, controls=[
            ft.Row(controls=[texto("Notícias do radar", 18, ft.FontWeight.BOLD), ft.Container(expand=True),
                             ft.IconButton(ft.Icons.REFRESH, tooltip="Atualizar",
                                           on_click=lambda e: self.atualizar_noticias(forcar=True))]),
            texto(status, 12, cor=VERMELHO if d.get("erros") and not self.noticias_rodando else MUTED),
            ft.Row(spacing=8, wrap=True, run_spacing=8, controls=[
                chip_menu("Mostrar", f["tema"], [("Todas", "Todas"), ("Relevantes", "Relevantes")],
                          lambda k: definir("tema", k), "Todas", sempre_valor=True),
                chip_menu("Ativo", f["ticker"], [("Todos", "Todos")] + [(t, t) for t in radar],
                          lambda k: definir("ticker", k), "Todos")]),
            ft.Row(controls=[ft.Column(spacing=0, expand=True, controls=[
                texto("Notificar notícias relevantes", 14),
                texto("Com o app aberto ou em segundo plano", 11, cor=MUTED)]),
                ft.Switch(value=self.cfg.get("noticias_notificar", True), on_change=notificar)])]))
        itens = [cabecalho]
        lista = [i for i in d["itens"] if set(i["tickers"]) & set(radar)
                 and (f["tema"] == "Todas" or i["temas"]) and (f["ticker"] == "Todos" or f["ticker"] in i["tickers"])]
        if not radar:
            vazio = "Adicione ativos no Radar para ver as notícias deles aqui."
        elif not d["hora"]:
            vazio = "Buscando notícias…" if self.noticias_rodando else "Nenhuma busca feita ainda."
        else:
            vazio = "Nenhuma notícia nos últimos 7 dias com esse filtro."
        if not lista:
            itens.append(texto(vazio, 13, cor=MUTED))
        for it in lista[:60]:
            itens.append(self.card_noticia(it, nt.eh_nova(d, it)))
        itens.append(ft.Container(height=24))
        return ft.ListView(controls=itens, padding=ft.Padding.all(16), spacing=10, expand=True)

    def card_noticia(self, it, nova):
        tags = [pilula("Nova", VERDE, "#ffffff", 10)] if nova else []
        tags += [pilula(t, ft.Colors.with_opacity(0.15, VERDE), VERDE, 10) for t in it["temas"][:2]]
        fav = nt.url_favicon(it)
        meta = [ft.Image(src=fav, width=14, height=14, error_content=ft.Container(width=0))] if fav else []
        meta.append(texto(" · ".join(x for x in (it["fonte"], nt.tempo_relativo(it["data"]),
                                                 ", ".join(it["tickers"])) if x), 11, cor=MUTED,
                          max_lines=1, overflow=ft.TextOverflow.ELLIPSIS, expand=True))
        corpo = [texto(it["titulo"], 14, ft.FontWeight.BOLD, max_lines=4, overflow=ft.TextOverflow.ELLIPSIS),
                 ft.Row(spacing=6, vertical_alignment=ft.CrossAxisAlignment.CENTER, controls=meta)]
        if tags:
            corpo.append(ft.Row(spacing=6, wrap=True, run_spacing=6, controls=tags))
        return ft.Container(
            padding=ft.Padding.all(12), border_radius=ft.BorderRadius.all(16), bgcolor=ft.Colors.SURFACE_CONTAINER,
            ink=True, on_click=lambda e, u=it["link"]: self.abrir_url(u),
            content=ft.Row(spacing=12, vertical_alignment=ft.CrossAxisAlignment.START, controls=[
                logo_ativo(it["tickers"][0], 40), ft.Column(spacing=6, expand=True, controls=corpo)]))

    def marcar_badge(self):
        n = 0 if self.aba == ABA_NOTICIAS else nt.nao_lidas(nt.ler_estado())
        destino = self.page.navigation_bar.destinations[ABA_NOTICIAS]
        destino.icon = ft.Icon(ft.Icons.NEWSPAPER, badge=str(n) if n else None)
        try:
            self.page.update()
        except Exception:
            pass

    def atualizar_noticias(self, forcar=False):
        if self.noticias_rodando or not self.cfg["radar"]:
            return
        d = nt.ler_estado()
        estreia = any(r["ticker"] not in d["conhecidos"] for r in self.cfg["radar"])
        if not forcar and not estreia and not nt.precisa_atualizar(d):
            return
        self.noticias_rodando = True
        radar = [dict(r) for r in self.cfg["radar"]]

        def trabalho():
            novas = []
            try:
                if self.aba == ABA_NOTICIAS:
                    self.render()
                _, novas = nt.atualizar(radar)
                self.noticias_msg = ""
            except Exception as e:
                self.noticias_msg = f"Não foi possível buscar notícias: {str(e)[:120]}"
            finally:
                self.noticias_rodando = False
            if self.aba == ABA_NOTICIAS:
                nt.marcar_lidas()
            self.marcar_badge()
            self.render(indice=ABA_NOTICIAS)
            if novas and self.cfg.get("noticias_notificar", True):
                self.notificar(novas)

        self.page.run_thread(trabalho)

    def notificar(self, novas):
        for titulo, corpo, link in nt.textos_notificacao(novas):
            if no_android():
                try:
                    notificar_android(abs(hash(link or titulo)) % 2_000_000_000, titulo, corpo, link)
                    continue
                except Exception:
                    traceback.print_exc()
            self.aviso(f"{titulo}: {corpo}")

    def pedir_permissao_notificacao(self):
        try:
            permitir_notificacoes()
        except Exception:
            traceback.print_exc()

    def remover_radar(self, t):
        def remover():
            with nc.TRAVA:
                self.cfg["radar"] = [r for r in self.cfg["radar"] if r["ticker"] != t]
                nc.gravar_config(self.cfg)
            self.radar_dados.pop(t, None)
            self.agendar_sync()
            self.render(todas=True)

        self.perguntar("Remover do radar", f"Remover {t} do radar?", "Remover", remover, perigo=True)

    def atualizar_radar(self, forcar=False, apenas=None):
        tickers = apenas or [r["ticker"] for r in self.radar_lista()]
        if not tickers or self.radar_rodando:
            return
        self.radar_rodando = True

        def trabalho():
            try:
                if forcar:
                    self.mercado.limpar()
                self.radar_msg = "Atualizando cotações…"
                if self.aba == ABA_RADAR:
                    self.render()
                nomes = {r["ticker"]: r.get("nome", "") for r in self.cfg["radar"] + list(self.amigo_radar)}
                for t in tickers:
                    try:
                        res = self.mercado.dados(t, nomes.get(t, ""))
                    except Exception as e:
                        res = {"ticker": t, "erro": erro_mercado(e)}
                    self.radar_dados[t] = res
                    if res.get("nome"):
                        with nc.TRAVA:
                            item = next((r for r in self.cfg["radar"] if r["ticker"] == t), None)
                            if item is not None and not item.get("nome"):
                                item["nome"] = res["nome"]
                                nc.gravar_config(self.cfg)
                                self.cfg["pendente"] = True
                    if self.aba == ABA_RADAR:
                        self.render()
                self.radar_hora = time.time()
                self.radar_msg = f"Atualizado às {datetime.now():%H:%M} · Yahoo Finance (atraso de até 15 min)"
            finally:
                self.radar_rodando = False
                if self.aba == ABA_RADAR:
                    self.render()

        self.page.run_thread(trabalho)

    def preparar_operacao(self):
        if self.visao:
            self.visao = None
            self.dados_amigo = {}
        self.mes = nc.mes_inicial()
        self.d = nc.carregar(self.mes)

    def radar_comprar(self, t):
        self.preparar_operacao()
        ini = {"ticker": t, "tipo": nc.inferir_tipo(t, nc.historico_tickers()[1])}
        dados = self.radar_dados.get(t) or {}
        if dados.get("preco"):
            ini["preco"] = nc.preco_texto(dados["preco"])
        self.form_compra(ini)

    def radar_vender(self, t):
        self.preparar_operacao()
        if not any(l["ticker"] == t and nc.restante(l) > 0 for l in self.d["lotes"]):
            self.aviso(f"Não há {t} em custódia no mês {fmt_mes(self.mes)}.")
            return
        self.form_venda(ticker=t)

    # ------------------------------------------------------------ conta, amigos e sincronização
    def tela_conta(self):
        itens = []
        status_txt = {"off": "Google não conectado", "login": "Aguardando login no navegador…",
                      "sync": "Sincronizando…", "ok": "Sincronizado", "pendente": "Alterações pendentes",
                      "offline": "Sem conexão · será enviado depois", "erro": "Erro ao sincronizar"}[self.status]
        if self.status == "ok" and self.ultima_sync:
            status_txt += f" às {self.ultima_sync:%H:%M}"
        itens.append(rotulo("Google"))
        if self.g.email:
            sid = self.cfg["planilhas"].get(self.g.email)
            conteudo = [texto(self.g.email, 15, ft.FontWeight.BOLD), texto(status_txt, 12, cor=MUTED)]
            if self.ultimo_erro and self.status == "erro":
                conteudo.append(texto(f"Último erro: {self.ultimo_erro}", 12, cor=VERMELHO))
            conteudo.append(ft.Row(wrap=True, spacing=8, controls=[
                ft.FilledButton("Sincronizar agora", icon=ft.Icons.SYNC, on_click=lambda e: self.sincronizar()),
                ft.OutlinedButton("Abrir planilha", icon=ft.Icons.OPEN_IN_NEW, disabled=not sid,
                                  on_click=lambda e: self.abrir_url(f"https://docs.google.com/spreadsheets/d/{sid}")),
                ft.TextButton("Sair", icon=ft.Icons.LOGOUT, on_click=self.sair)]))
            itens.append(bloco(ft.Column(spacing=8, controls=conteudo)))
            itens.append(rotulo("Amigos"))
            itens.append(self.bloco_amigos())
        else:
            itens.append(bloco(ft.Column(spacing=10, controls=[
                texto("Conecte para sincronizar com a planilha no Google Drive (a mesma usada no computador) e "
                      "para compartilhar com amigos.", 13, cor=MUTED),
                texto(status_txt, 12, cor=MUTED),
                ft.FilledButton("Conectar Google", icon=ft.Icons.LOGIN,
                                on_click=lambda e: self.page.run_thread(self.conectar),
                                disabled=self.status == "login"),
                texto("Depois de autorizar no navegador, volte para este app.", 12, cor=MUTED)])))

        escuro = self.page.theme_mode == ft.ThemeMode.DARK
        itens.append(rotulo("Preferências"))
        itens.append(bloco(ft.Row(controls=[texto("Modo escuro", 14), ft.Container(expand=True),
                                            ft.Switch(value=escuro, on_change=self.trocar_tema)])))
        itens.append(rotulo("Sobre"))
        itens.append(bloco(ft.Column(spacing=8, controls=[
            texto(f"Versão {VERSAO}", 13, cor=MUTED),
            ft.OutlinedButton("Verificar atualização", icon=ft.Icons.SYSTEM_UPDATE,
                              on_click=lambda e: self.page.run_thread(self.verificar_atualizacao, True))])))
        return ft.ListView(controls=itens, padding=ft.Padding.all(16), spacing=12, expand=True)

    def bloco_amigos(self):
        campo = ft.TextField(label="E-mail do amigo", keyboard_type=ft.KeyboardType.EMAIL, expand=True, dense=True)
        msg = texto("", 12, cor=MUTED)

        def adicionar(e=None):
            import re
            email = (campo.value or "").strip().lower()
            if not re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", email):
                self.aviso("E-mail inválido.")
                return
            if email == self.g.email or any(a["email"] == email for a in self.cfg["amigos"]):
                self.aviso("Esse e-mail já está na lista ou é o seu.")
                return
            sid = self.cfg["planilhas"].get(self.g.email)
            if not sid:
                self.aviso("Aguarde a criação da sua planilha e tente novamente.")
                return
            try:
                self.g.compartilhar(sid, email)
            except gs.Offline:
                self.aviso("Sem conexão com a internet.")
                return
            except Exception as ex:
                self.aviso(str(ex))
                return
            with nc.TRAVA:
                self.cfg["amigos"].append({"email": email, "desde": date.today().isoformat()})
                nc.gravar_config(self.cfg)
            self.agendar_sync()
            self.aviso(f"Planilha compartilhada com {email}.")
            self.render()

        campo.on_submit = lambda e: self.page.run_thread(adicionar)
        linhas = []
        for a in self.cfg["amigos"]:
            email = a["email"]
            linhas.append(ft.ListTile(
                title=ft.Text(email), subtitle=ft.Text(f"Adicionado em {fmt_data(a['desde'])}"),
                trailing=ft.Row(tight=True, spacing=0, controls=[
                    ft.IconButton(ft.Icons.VISIBILITY, tooltip="Ver dados",
                                  on_click=lambda e, m=email: self.ver_amigo(m)),
                    ft.IconButton(ft.Icons.PERSON_REMOVE, icon_color=VERMELHO, tooltip="Remover",
                                  on_click=lambda e, m=email: self.remover_amigo(m))])))
        return bloco(ft.Column(spacing=8, controls=[
            texto("Amigos", 16, ft.FontWeight.BOLD),
            texto("Ao adicionar um amigo, sua planilha é compartilhada com ele somente para leitura. Para ver os "
                  "dados dele, ele também precisa adicionar você.", 12, cor=MUTED),
            ft.Row(controls=[campo, ft.IconButton(ft.Icons.PERSON_ADD, icon_color=VERDE,
                                                  on_click=lambda e: self.page.run_thread(adicionar))]),
            msg, *(linhas or [texto("Nenhum amigo adicionado.", 13, cor=MUTED)])]))

    def remover_amigo(self, email):
        def remover():
            sid = self.cfg["planilhas"].get(self.g.email)
            try:
                if sid:
                    self.g.descompartilhar(sid, email)
            except gs.Offline:
                self.aviso("Sem conexão com a internet.")
                return
            except Exception as ex:
                self.aviso(str(ex))
                return
            with nc.TRAVA:
                self.cfg["amigos"] = [a for a in self.cfg["amigos"] if a["email"] != email]
                nc.gravar_config(self.cfg)
            if self.visao == email:
                self.visao = None
                self.dados_amigo = {}
                self.mes = nc.mes_inicial()
                self.d = nc.carregar(self.mes)
            self.agendar_sync()
            self.render()

        self.perguntar("Remover amigo", f"{email} deixará de ter acesso à sua planilha.", "Remover",
                       lambda: self.page.run_thread(remover), perigo=True)

    def seletor_visao(self, o_que):
        """'Visualizando' (meus dados ou de um amigo), igual nas abas Apuração, Caixa e Radar."""
        itens = []
        if self.g.email and self.cfg["amigos"]:
            opcoes = [ft.DropdownOption(key="", text="Meus dados")] + [
                ft.DropdownOption(key=a["email"], text=a["email"]) for a in self.cfg["amigos"]]
            itens.append(ft.Dropdown(label="Visualizando", value=self.visao or "", options=opcoes,
                                     on_select=self.trocar_visao, dense=True, expand=True))
        if self.visao:
            itens.append(texto(f"{o_que} de {self.visao} · somente leitura", 12, cor=AMARELO))
        return itens

    def radar_lista(self):
        return self.amigo_radar if self.visao else nc.ordenar_radar(self.cfg["radar"])

    def ver_amigo(self, email):
        self.aba = 0
        self.page.navigation_bar.selected_index = 0
        self.page.run_thread(self.carregar_amigo, email)

    def trocar_visao(self, e):
        email = e.control.value or ""
        if not email:
            self.visao = None
            self.dados_amigo = {}
            self.amigo_radar, self.amigo_caixa = [], None
            self.mes = nc.mes_inicial()
            self.d = nc.carregar(self.mes)
            self.render(todas=True)
            return
        self.page.run_thread(self.carregar_amigo, email)

    def carregar_amigo(self, email):
        self.aviso(f"Carregando dados de {email}…")
        try:
            sid = self.g.buscar_planilha(email)
            if not sid:
                raise gs.ErroGoogle(f"{email} ainda não compartilhou a planilha com você. "
                                    f"Peça para ele adicionar {self.g.email} em Amigos.")
            meses, _, radar, _, caixa = nc.reconstruir(self.g.ler(sid))
        except gs.Offline:
            self.aviso("Sem conexão com a internet.")
            self.render()
            return
        except Exception as ex:
            self.aviso(str(ex))
            self.render()
            return
        trocou = self.visao != email
        self.visao = email
        self.dados_amigo = meses
        self.amigo_radar, self.amigo_caixa = nc.ordenar_radar(radar), caixa
        if trocou or self.mes not in meses:
            abertos = sorted(m for m, d in meses.items() if not d["fechado"])
            self.mes = abertos[0] if abertos else (max(meses) if meses else date.today().strftime("%Y-%m"))
        self.d = meses.get(self.mes) or nc.mes_vazio(self.mes)
        self.render(todas=True)
        if self.aba == ABA_RADAR:
            self.atualizar_radar()

    def trocar_tema(self, e):
        escuro = bool(e.control.value)
        self.page.theme_mode = ft.ThemeMode.DARK if escuro else ft.ThemeMode.LIGHT
        with nc.TRAVA:
            self.cfg["tema"] = "Dark" if escuro else "Light"
            nc.gravar_config(self.cfg)
        self.page.update()

    def definir_status(self, s):
        self.status = s
        self.atualizar_icone_sync()
        if self.aba == ABA_CONTA:
            self.render()
        else:
            try:
                self.page.update()
            except Exception:
                pass

    def atualizar_icone_sync(self):
        icones = {"off": (ft.Icons.CLOUD_OFF, None), "login": (ft.Icons.LOGIN, AMARELO),
                  "sync": (ft.Icons.CLOUD_SYNC, None), "ok": (ft.Icons.CLOUD_DONE, VERDE),
                  "pendente": (ft.Icons.CLOUD_UPLOAD, AMARELO), "offline": (ft.Icons.CLOUD_OFF, AMARELO),
                  "erro": (ft.Icons.ERROR_OUTLINE, VERMELHO)}
        icone, cor = icones[self.status]
        self.bt_sync.icon = icone
        self.bt_sync.icon_color = cor

    def conectar_token(self):
        try:
            self.definir_status("sync")
            self.g.carregar_token()
        except gs.Offline:
            self.definir_status("offline")
            return
        except Exception:
            self.g.sair()
            self.definir_status("off")
            return
        self.render()
        self.sincronizar()

    def conectar(self, e=None):
        if not self.g.tem_credencial():
            self.aviso("Credencial do Google não encontrada neste aplicativo.")
            return
        self.definir_status("login")
        try:
            self.g.login_navegador(self.abrir_url)
        except Exception as ex:
            self.definir_status("off")
            self.aviso(str(ex) or "O login não foi concluído.")
            return
        self.aviso(f"Conectado como {self.g.email}.")
        self.render()
        self.sincronizar()

    def sair(self, e=None):
        def sair():
            self.g.sair()
            self.visao = None
            self.dados_amigo = {}
            self.d = nc.carregar(self.mes)
            self.definir_status("off")
            self.render()

        self.perguntar("Sair da conta", "Os dados continuam salvos neste aparelho e na planilha.", "Sair", sair,
                       perigo=True)

    def agendar_sync(self):
        with nc.TRAVA:
            self.cfg["pendente"] = True
            nc.gravar_config(self.cfg)
        if not self.g.email:
            return
        self.status = "pendente"
        self.atualizar_icone_sync()
        if self.sync_timer:
            self.sync_timer.cancel()
        self.sync_timer = threading.Timer(1.5, self.sincronizar)
        self.sync_timer.daemon = True
        self.sync_timer.start()

    def sincronizar(self):
        if not self.g.email:
            return
        with self.trava_sync:
            if self.sync_rodando:
                self.resync = True
                return
            self.sync_rodando = True
        threading.Thread(target=self._sincronizar, daemon=True).start()

    def _sincronizar(self):
        try:
            self.definir_status("sync")
            email = self.g.email
            sid = self.cfg["planilhas"].get(email)
            if not sid:
                sid = self.g.buscar_planilha("me") or self.g.criar_planilha()
                with nc.TRAVA:
                    self.cfg["planilhas"][email] = sid
                    nc.gravar_config(self.cfg)
            while True:
                self.resync = False
                abas = self.g.ler(sid)
                with nc.TRAVA:
                    mudou = nc.mesclar_tudo(nc.reconstruir(abas), self.cfg, metas_r=nc.reconstruir_metas(abas))
                    dados = nc.montar_linhas(nc.listar_meses(), self.cfg)
                    if mudou and not self.visao:
                        self.d = nc.carregar(self.mes)
                if mudou:
                    self.render()
                self.g.escrever(sid, dados)
                if not self.resync:
                    break
            with nc.TRAVA:
                self.cfg["pendente"] = False
                nc.gravar_config(self.cfg)
            self.ultima_sync = datetime.now()
            self.ultima_puxada = time.time()
            self.ultimo_erro = ""
            self.definir_status("ok")
        except gs.LoginNecessario:
            self.g.sair()
            self.definir_status("off")
            self.aviso("Sessão expirada. Conecte sua conta Google novamente.")
        except gs.Offline:
            self.definir_status("offline")
        except Exception as e:
            if getattr(e, "status", 0) == 404 and self.g.email:
                with nc.TRAVA:
                    self.cfg["planilhas"].pop(self.g.email, None)
                    nc.gravar_config(self.cfg)
            self.ultimo_erro = str(e)
            self.definir_status("erro")
        finally:
            self.sync_rodando = False

    def laco(self):
        """Sincroniza alterações pendentes, busca as de outros aparelhos e atualiza o radar."""
        while True:
            time.sleep(30)
            try:
                if self.g.email:
                    if (self.cfg.get("pendente") or time.time() - self.ultima_puxada > 300) and not self.sync_rodando:
                        self.sincronizar()
                elif self.g.tem_token() and self.status in ("offline",):
                    self.conectar_token()
                if self.aba == ABA_RADAR and time.time() - self.radar_hora > 60:
                    self.atualizar_radar()
                self.atualizar_noticias()
                if date.today() != getattr(self, "dia_caixa", date.today()):  # virada do dia: liquidações
                    self.render(todas=True)
                if self.aba == 0:
                    em_carteira = {l["ticker"] for l in self.d["lotes"] if nc.restante(l) > 0}
                    self.cotacoes.atualizar(em_carteira, self.cotacoes_chegaram)
                self.verificar_metas()
            except Exception:
                traceback.print_exc()

    # ------------------------------------------------------------ metas de lucro / preço-alvo
    def verificar_metas(self):
        """Busca o histórico das metas ativas e registra as vendas dos alvos atingidos (roda em thread)."""
        try:
            rel = ms.verificar(self.cfg, mk.historico_desde)
        except Exception:
            traceback.print_exc()
            return
        if rel is None:
            return None
        if rel["mudou"]:
            with nc.TRAVA:
                if not self.visao:
                    self.d = nc.carregar(self.mes)
            self.agendar_sync()
            self.render(todas=True)
            for m in rel["executadas"]:
                ex = m["execucao"]
                self.aviso(f"Meta atingida: {m['ticker']} vendida a {brl(ex['preco_usado'])} em "
                           f"{fmt_data(ex['data'])} {ex['hora']}.")
            for m in rel["invalidas"]:
                self.aviso(f"Meta inválida ({m['ticker']}): {m.get('ultimo_erro', '')}")
        if self.metas_ui:
            self.metas_ui()
        return rel

    def dialogo_metas(self):
        """Calculadora de preço-alvo e lista das metas (vendas automáticas)."""
        if self.visao:
            self.aviso("Volte para os seus dados para criar metas.")
            return
        estado = {"calc": None}
        opcoes = {}
        compra = ft.Dropdown(label="Ativo / compra *", options=[], expand=True)
        qtd = ft.TextField(label="Quantidade *", keyboard_type=ft.KeyboardType.NUMBER)
        lucro = ft.TextField(label="Lucro líquido desejado (R$) *", keyboard_type=ft.KeyboardType.NUMBER,
                             hint_text="Ex.: 1.000,00")
        preco = ft.TextField(label="Preço-alvo da venda (R$) *", keyboard_type=ft.KeyboardType.NUMBER,
                             hint_text="Ex.: 21,78")
        resultado = ft.Column(spacing=4)
        nota = texto("", 11, cor=MUTED)
        erro = texto("", 12, cor=VERMELHO)
        lista = ft.Column(spacing=8)
        verif = texto("", 11, cor=MUTED)

        def atualizar_dlg():
            try:
                dlg.update()
            except Exception:  # diálogo ainda não exibido ou já fechado
                pass

        def lote_atual():
            return opcoes.get(compra.value)

        def mostrar(r, p):
            lote = lote_atual()[0]
            resultado.controls = [
                linha_valor("Lucro desejado", brl(r["lucro_desejado"]), tam=14),
                linha_valor("Preço médio do lote", brl(r["preco_medio"]), tam=14),
                linha_valor("Custo estimado de venda", brl(p["custos"]), tam=14),
                linha_valor("Imposto estimado", brl(p["imposto"]), tam=14),
                linha_valor("Preço-alvo sugerido", brl(r["preco"]), tam=14),
                linha_valor("Lucro bruto projetado", brl(p["bruto"]), cor_resultado(p["bruto"]), tam=14),
                linha_valor("Lucro líquido projetado", brl(p["lucro_apos_imposto"]),
                            cor_resultado(p["lucro_apos_imposto"]), tam=14)]
            regime = "Day trade (20%)" if r["day_trade"] else "Swing trade (15%)"
            irrf = f" IRRF retido estimado: {brl(p['irrf'])} (abate da DARF)." if p["irrf"] else ""
            nota.value = (f"{regime} · taxas B3 {brl(p['taxas'])} + corretagem {brl(p['corretagem'])}.{irrf} "
                          "Estimativa conservadora: sem isenção de R$ 20 mil e sem prejuízos anteriores.")

        def limpar(msg=""):
            resultado.controls = []
            nota.value = msg
            estado["calc"] = None

        def calcular(e=None):
            erro.value = ""
            sel = lote_atual()
            if not sel:
                limpar()
                return atualizar_dlg()
            try:
                q = nc.parse_qtd(qtd.value or "")
                l = nc.parse_valor(lucro.value or "")
            except ValueError:
                limpar("Informe a quantidade e o lucro líquido desejado.")
                return atualizar_dlg()
            lote, livre = sel
            if q > livre:
                limpar(f"Quantidade maior que a livre ({livre}).")
                return atualizar_dlg()
            try:
                r = ms.calcular_preco_alvo(lote, q, l, lote["data_compra"] == date.today().isoformat())
            except (ValueError, OverflowError) as ex:
                limpar(str(ex) if isinstance(ex, ValueError) else "Valores grandes demais para calcular.")
                return atualizar_dlg()
            estado["calc"] = r
            preco.value = nc.preco_texto(r["preco"])
            mostrar(r, ms.projetar(lote, q, r["preco"], r["day_trade"]))
            atualizar_dlg()

        def projetar_preco(e=None):
            r = estado["calc"]
            if not r or not lote_atual():
                return
            try:
                p = nc.parse_num(preco.value or "")
            except ValueError:
                return
            mostrar(r, ms.projetar(lote_atual()[0], r["qtd"], p, r["day_trade"]))
            atualizar_dlg()

        def escolheu_lote(e=None):
            sel = lote_atual()
            if sel:
                qtd.value = str(sel[1])
            calcular()

        def carregar_opcoes():
            opcoes.clear()
            for mes, l, livre in ms.lotes_para_meta(self.cfg):
                opcoes[f"{l['id']}"] = (l, livre)
            compra.options = [ft.DropdownOption(
                key=k, text=f"{l['ticker']} · {fmt_data(l['data_compra'])} · {brl(l['preco'])} · {livre} livres")
                for k, (l, livre) in opcoes.items()]
            if compra.value not in opcoes:
                compra.value = next(iter(opcoes), None)
            compra.disabled = not opcoes

        def desenhar_lista():
            cards = []
            for m in sorted(self.cfg.get("metas", []), key=lambda x: x["criada_em"], reverse=True):
                d = ms.descricao(m)
                cor = {"accent": VERDE, "danger": VERMELHO, "aviso": AMARELO, "muted": MUTED}[d["cor"]]
                linhas_card = [ft.Row(alignment=ft.MainAxisAlignment.SPACE_BETWEEN, controls=[
                    texto(d["titulo"], 14, ft.FontWeight.BOLD), texto(d["status"], 12, ft.FontWeight.BOLD, cor)]),
                    texto(d["detalhe"], 11, cor=VERMELHO if d["erro"] else MUTED)]
                if m.get("status") == "ativa":
                    linhas_card.append(ft.TextButton("Cancelar meta", on_click=lambda e, i=m["id"]: cancelar(i)))
                cards.append(bloco(ft.Column(spacing=4, controls=linhas_card), padding=12))
            lista.controls = cards or [texto("Nenhuma meta criada.", 12, cor=MUTED)]

        def atualizar_tudo():
            carregar_opcoes()
            desenhar_lista()
            atualizar_dlg()

        def cancelar(meta_id):
            try:
                ms.cancelar_meta(self.cfg, meta_id)
            except ValueError as ex:
                self.aviso(str(ex))
            self.agendar_sync()
            atualizar_tudo()

        def criar(e):
            sel = lote_atual()
            try:
                if not sel:
                    raise ValueError("Não há compra em aberto para criar a meta.")
                try:
                    q = nc.parse_qtd(qtd.value or "")
                except ValueError:
                    raise ValueError("Quantidade inválida.")
                try:
                    p = nc.parse_num(preco.value or "")
                except ValueError:
                    raise ValueError("Preço-alvo inválido.")
                try:
                    l = nc.parse_valor(lucro.value or "")
                except ValueError:
                    l = None
                ms.criar_meta(self.cfg, sel[0]["id"], q, p, l)
            except ValueError as ex:
                erro.value = str(ex)
                erro.color = VERMELHO
                return atualizar_dlg()
            self.agendar_sync()
            erro.value = "Meta criada. O app registra a venda quando o preço-alvo for atingido."
            erro.color = VERDE
            atualizar_tudo()
            self.page.run_thread(self.verificar_metas)

        def verificar_agora(e):
            verif.value = "Verificando o histórico de preços…"
            atualizar_dlg()

            def trabalho():
                rel = self.verificar_metas()
                if rel is None:
                    verif.value = ("Verificação já em andamento." if ms.metas_ativas(self.cfg)
                                   else "Não há metas ativas para verificar.")
                else:
                    verif.value = f"Verificado às {datetime.now():%H:%M}."
                atualizar_tudo()
            self.page.run_thread(trabalho)

        def fechou(e=None):
            self.metas_ui = None

        def atualizar_de_fora():
            carregar_opcoes()
            desenhar_lista()
            atualizar_dlg()

        qtd.on_change = calcular
        lucro.on_change = calcular
        preco.on_change = projetar_preco
        compra.on_select = escolheu_lote
        carregar_opcoes()
        desenhar_lista()
        sel0 = lote_atual()
        if sel0:
            qtd.value = str(sel0[1])
        self.metas_ui = atualizar_de_fora
        conteudo = [texto(ms.AVISO_REGISTRO, 12, ft.FontWeight.BOLD, AMARELO), compra, qtd, lucro, resultado, nota,
                    preco, erro, ft.FilledButton("Criar venda automática com este preço", on_click=criar),
                    ft.Divider(), ft.Row(controls=[rotulo("Metas"), ft.Container(expand=True),
                                                   ft.TextButton("Verificar agora", on_click=verificar_agora)]),
                    verif, lista]
        dlg = ft.AlertDialog(title=ft.Text("Meta de lucro / Preço-alvo"), scrollable=True, on_dismiss=fechou,
                             content=ft.Container(width=400, content=ft.Column(tight=True, spacing=12,
                                                                               controls=conteudo)),
                             actions=[ft.TextButton("Fechar", on_click=lambda e: self.page.pop_dialog())])
        self.page.show_dialog(dlg)

    # ------------------------------------------------------------ atualização do aplicativo
    def verificar_atualizacao(self, manual=False):
        try:
            info = upd.verificar(NOME_APK)
        except Exception:
            if manual:
                self.aviso("Não foi possível verificar atualizações.")
            return
        if not info:
            if manual:
                self.aviso(f"Você já está na versão mais recente ({VERSAO}).")
            return
        notas = info["notas"]
        if len(notas) > 500:
            notas = notas[:500].rstrip() + "…"
        msg = f"A versão {info['versao']} está disponível. Você está usando a {VERSAO}."
        if notas:
            msg += f"\n\nNovidades:\n{notas}"
        self.perguntar("Nova versão disponível", msg, "Atualizar", lambda: self.baixar_atualizacao(info),
                       nao="Depois")

    def baixar_atualizacao(self, info):
        if not no_android():
            self.abrir_url(URL_RELEASES)
            return
        barra = ft.ProgressBar(value=0, color=VERDE)
        status = texto("Baixando…", 13, cor=MUTED)
        cancelado = {"v": False}

        def cancelar(e):
            cancelado["v"] = True
            self.page.pop_dialog()

        bt = ft.TextButton("Cancelar", on_click=cancelar)
        dlg = ft.AlertDialog(modal=True, title=ft.Text(f"Atualizando para a versão {info['versao']}"),
                             content=ft.Column(tight=True, spacing=12, controls=[status, barra]), actions=[bt])
        self.page.show_dialog(dlg)
        ultimo = {"t": 0}

        def progresso(b, t):
            if cancelado["v"]:
                raise upd.ErroAtualizacao("Atualização cancelada.")
            if time.time() - ultimo["t"] < 0.3 and b != t:
                return
            ultimo["t"] = time.time()
            mb = 1024 * 1024
            barra.value = min(b / t, 1) if t else None
            status.value = (f"Baixando… {b / mb:.1f} de {t / mb:.1f} MB" if t else f"Baixando… {b / mb:.1f} MB"
                            ).replace(".", ",")
            dlg.update()

        def trabalho():
            destino = Path(pasta_cache()) / f"CalculadoraDARF-{info['versao']}.apk"
            try:
                upd.baixar(info, progresso, destino)
                if cancelado["v"]:
                    return
                status.value = "Abrindo o instalador do Android…"
                bt.content = "Fechar"
                bt.on_click = lambda e: self.page.pop_dialog()
                dlg.update()
                instalar_apk(destino)
            except Exception as ex:
                if cancelado["v"]:
                    return
                status.value = f"Não foi possível atualizar: {ex}"
                status.color = VERMELHO
                bt.content = "Fechar"
                bt.on_click = lambda e: self.page.pop_dialog()
                try:
                    dlg.update()
                except Exception:
                    pass

        self.page.run_thread(trabalho)


def main(page: ft.Page):
    App(page)


if __name__ == "__main__":
    ft.run(main)
