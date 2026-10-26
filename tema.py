import customtkinter as ctk

FONTE = "Segoe UI"
C = {
    "bg": ("#eef0f4", "#0e1014"),
    "card": ("#ffffff", "#161920"),
    "card2": ("#f5f6f9", "#1c2029"),
    "zebra": ("#fafbfc", "#191c24"),
    "borda": ("#e1e4ea", "#262b35"),
    "texto": ("#141720", "#e8eaef"),
    "muted": ("#687084", "#8a92a6"),
    "accent": ("#0e9f6e", "#10b981"),
    "accent_h": ("#0b8a5f", "#0d9e70"),
    "accent_bg": ("#d9f5ea", "#0f2f25"),
    "danger": ("#dc2626", "#f05252"),
    "danger_h": ("#b91c1c", "#d93f3f"),
    "aviso": ("#d97706", "#f59e0b"),
    "neutro": ("#e9ecf1", "#252a34"),
    "neutro_h": ("#dde1e8", "#2e3440"),
    "selecao": ("#cdeedf", "#1d4436"),
}


def cor(k):
    return C[k][0 if ctk.get_appearance_mode() == "Light" else 1]


def F(tam, peso="normal"):
    return ctk.CTkFont(family=FONTE, size=tam, weight=peso)


def estilo_botao(nome):
    return {
        "accent": dict(fg_color=C["accent"], hover_color=C["accent_h"], text_color="#ffffff"),
        "neutro": dict(fg_color=C["neutro"], hover_color=C["neutro_h"], text_color=C["texto"]),
        "perigo": dict(fg_color="transparent", hover_color=C["neutro"], text_color=C["danger"],
                       border_width=1, border_color=C["danger"]),
        "perigo_cheio": dict(fg_color=C["danger"], hover_color=C["danger_h"], text_color="#ffffff"),
        "chip": dict(fg_color=C["card2"], hover_color=C["neutro_h"], text_color=C["texto"],
                     border_width=1, border_color=C["borda"]),
        "chip_ativo": dict(fg_color=C["accent_bg"], hover_color=C["accent_bg"], text_color=C["accent"],
                           border_width=1, border_color=C["accent"]),
        "link": dict(fg_color="transparent", hover_color=C["neutro"], text_color=C["accent"]),
    }[nome]


def botao(pai, texto, comando, estilo="neutro", altura=36, fonte=13, **kw):
    return ctk.CTkButton(pai, text=texto, command=comando, height=altura, corner_radius=8,
                         font=F(fonte, "bold"), **estilo_botao(estilo), **kw)
