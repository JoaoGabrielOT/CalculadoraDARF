import 'package:flutter/material.dart';

import 'cores_app.dart';
import 'tema_visual.dart';

/// Automático: Claro com o sistema claro, Moderno com o sistema escuro.
TemaVisual resolverTema(TemaVisual escolhido, Brightness sistema) {
  if (escolhido != TemaVisual.automatico) return escolhido;
  return sistema == Brightness.dark ? TemaVisual.moderno : TemaVisual.claro;
}

/// Verde para alta, vermelho para queda, suave para zero ou ausente
/// (calculadora_darf.py:938-941).
Color corVariacao(BuildContext context, double? v) {
  final cores = CoresApp.de(context);
  if (v != null && v > 0) return cores.alta;
  if (v != null && v < 0) return cores.queda;
  return cores.textoSuave;
}

const _terminal = CoresApp(
  fundo: Color(0xFF0D1117),
  cartao: Color(0xFF161B22),
  cartaoBorda: Color(0xFF30363D),
  sombraCartao: [],
  raioCartao: 6,
  texto: Color(0xFFE6EDF3),
  textoSuave: Color(0xFF8B949E),
  alta: Color(0xFF3FB950),
  queda: Color(0xFFF85149),
  seloAltaFundo: Color(0x00000000),
  seloQuedaFundo: Color(0x00000000),
  aviso: Color(0xFFD29922),
  destaque: Color(0xFF2EA043),
  chipFundo: Color(0xFF161B22),
  chipTexto: Color(0xFF9DA7B3),
  chipAtivoFundo: Color(0xFF161B22),
  chipAtivoTexto: Color(0xFF3FB950),
  chipAtivoBorda: Color(0xFF2EA043),
  linha: Color(0xFF21262D),
  logoFundo: Color(0xFF161B22),
  navAtivo: Color(0xFF3FB950),
  densa: true,
);

const _claro = CoresApp(
  fundo: Color(0xFFF6F7FB),
  cartao: Color(0xFFFFFFFF),
  cartaoBorda: Color(0x00000000),
  sombraCartao: [
    BoxShadow(
      color: Color.fromRGBO(20, 30, 60, .08),
      offset: Offset(0, 1),
      blurRadius: 3,
    ),
  ],
  raioCartao: 16,
  texto: Color(0xFF1B1F2A),
  textoSuave: Color(0xFF5F657D),
  alta: Color(0xFF14833B),
  queda: Color(0xFFC62828),
  seloAltaFundo: Color(0xFFE3F6EA),
  seloQuedaFundo: Color(0xFFFDE8E8),
  aviso: Color(0xFF9A5B00),
  destaque: Color(0xFF1B1F2A),
  chipFundo: Color(0xFFE8EAF2),
  chipTexto: Color(0xFF4A5068),
  chipAtivoFundo: Color(0xFF1B1F2A),
  chipAtivoTexto: Color(0xFFFFFFFF),
  linha: Color(0xFFE8EAF2),
  logoFundo: Color(0xFFEEF0F7),
  navAtivo: Color(0xFF1B1F2A),
  densa: false,
);

const _moderno = CoresApp(
  fundo: Color(0xFF0B0E1A),
  // 160° no CSS: de cima, levemente à esquerda, para baixo; parada em 60%.
  fundoGradiente: LinearGradient(
    begin: Alignment(-0.342, -0.940),
    end: Alignment(0.342, 0.940),
    colors: [Color(0xFF151A2E), Color(0xFF0B0E1A)],
    stops: [0, 0.6],
  ),
  cartao: Color.fromRGBO(255, 255, 255, .05),
  cartaoBorda: Color.fromRGBO(255, 255, 255, .07),
  sombraCartao: [],
  raioCartao: 18,
  texto: Color(0xFFF1F3FB),
  textoSuave: Color(0xFF8F97BA),
  alta: Color(0xFF55EFC4),
  queda: Color(0xFFFF7675),
  seloAltaFundo: Color.fromRGBO(0, 184, 148, .18),
  seloQuedaFundo: Color.fromRGBO(255, 99, 99, .18),
  aviso: Color(0xFFFDCB6E),
  destaque: Color(0xFF6C5CE7),
  destaqueGradiente: LinearGradient(
    colors: [Color(0xFF6C5CE7), Color(0xFF00B894)],
  ),
  chipFundo: Color.fromRGBO(255, 255, 255, .06),
  chipTexto: Color(0xFFAAB1CF),
  chipAtivoFundo: Color(0xFF6C5CE7),
  chipAtivoTexto: Color(0xFFFFFFFF),
  linha: Color.fromRGBO(255, 255, 255, .07),
  logoFundo: Color.fromRGBO(255, 255, 255, .10),
  navAtivo: Color(0xFFA29BFE),
  densa: false,
);

/// Superfícies opacas de cada tema (a translucidez fica só em `CoresApp.cartao`).
class _Superficies {
  const _Superficies(
    this.surface,
    this.lowest,
    this.low,
    this.mid,
    this.high,
    this.highest,
  );
  final Color surface, lowest, low, mid, high, highest;
}

const _supTerminal = _Superficies(
  Color(0xFF161B22),
  Color(0xFF0D1117),
  Color(0xFF12171E),
  Color(0xFF161B22),
  Color(0xFF1C2128),
  Color(0xFF21262D),
);
const _supClaro = _Superficies(
  Color(0xFFFFFFFF),
  Color(0xFFFFFFFF),
  Color(0xFFF6F7FB),
  Color(0xFFEEF0F7),
  Color(0xFFFFFFFF),
  Color(0xFFF6F7FB),
);
// Cartão (branco 5%) composto sobre #0b0e1a.
const _supModerno = _Superficies(
  Color(0xFF171A26),
  Color(0xFF0B0E1A),
  Color(0xFF111422),
  Color(0xFF171A26),
  Color(0xFF1E2232),
  Color(0xFF262B3E),
);

/// Tema Material 3 para um tema já resolvido. `automatico` (sem sistema para
/// consultar) cai no Claro.
ThemeData temaDe(TemaVisual resolvido) {
  return switch (resolvido) {
    // Terminal: texto escuro sobre o verde de destaque (contraste AA).
    TemaVisual.terminal => _montar(
      _terminal,
      _supTerminal,
      Brightness.dark,
      _terminal.fundo,
    ),
    TemaVisual.moderno => _montar(
      _moderno,
      _supModerno,
      Brightness.dark,
      Colors.white,
    ),
    _ => _montar(_claro, _supClaro, Brightness.light, Colors.white),
  };
}

ThemeData _montar(
  CoresApp c,
  _Superficies s,
  Brightness brilho,
  Color onPrimary,
) {
  final borda = c.cartaoBorda.a == 0 ? c.linha : c.cartaoBorda;
  final forma = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(c.raioCartao),
    side: BorderSide(color: borda),
  );
  final formaSemBorda = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(c.raioCartao),
  );
  final esquema =
      ColorScheme.fromSeed(seedColor: c.destaque, brightness: brilho).copyWith(
        primary: c.destaque,
        onPrimary: onPrimary,
        surface: s.surface,
        onSurface: c.texto,
        onSurfaceVariant: c.textoSuave,
        surfaceTint: Colors.transparent,
        surfaceContainerLowest: s.lowest,
        surfaceContainerLow: s.low,
        surfaceContainer: s.mid,
        surfaceContainerHigh: s.high,
        surfaceContainerHighest: s.highest,
        error: c.queda,
        outline: borda,
        outlineVariant: c.linha,
      );
  final base = ThemeData(
    useMaterial3: true,
    fontFamily: 'Roboto',
    colorScheme: esquema,
    brightness: brilho,
  );
  final estadoNav = WidgetStateProperty.resolveWith<Color>(
    (e) => e.contains(WidgetState.selected) ? c.navAtivo : c.textoSuave,
  );
  final estiloBotao = ButtonStyle(shape: WidgetStatePropertyAll(formaSemBorda));
  OutlineInputBorder campo(Color cor, [double largura = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(c.raioCartao),
        borderSide: BorderSide(color: cor, width: largura),
      );
  return base.copyWith(
    scaffoldBackgroundColor: c.fundo,
    canvasColor: c.fundo,
    dividerColor: c.linha,
    dividerTheme: DividerThemeData(color: c.linha),
    visualDensity: c.densa ? VisualDensity.compact : VisualDensity.standard,
    textTheme: base.textTheme.apply(
      bodyColor: c.texto,
      displayColor: c.texto,
      fontFamily: 'Roboto',
    ),
    extensions: [c],
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: s.lowest,
      labelStyle: TextStyle(color: c.textoSuave),
      hintStyle: TextStyle(color: c.textoSuave),
      border: campo(borda),
      enabledBorder: campo(borda),
      focusedBorder: campo(c.destaque, 2),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: s.high,
      surfaceTintColor: Colors.transparent,
      shape: forma,
      titleTextStyle: TextStyle(
        color: c.texto,
        fontFamily: 'Roboto',
        fontSize: 20,
        fontWeight: FontWeight.w500,
      ),
      contentTextStyle: TextStyle(
        color: c.texto,
        fontFamily: 'Roboto',
        fontSize: 14,
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: c.fundo,
      foregroundColor: c.texto,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: s.low,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Colors.transparent,
      iconTheme: WidgetStateProperty.resolveWith(
        (e) => IconThemeData(color: estadoNav.resolve(e)),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (e) => TextStyle(color: estadoNav.resolve(e), fontSize: 12),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: s.low,
      indicatorColor: Colors.transparent,
      selectedIconTheme: IconThemeData(color: c.navAtivo),
      unselectedIconTheme: IconThemeData(color: c.textoSuave),
      selectedLabelTextStyle: TextStyle(color: c.navAtivo),
      unselectedLabelTextStyle: TextStyle(color: c.textoSuave),
    ),
    cardTheme: CardThemeData(
      color: s.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: forma,
    ),
    dataTableTheme: DataTableThemeData(
      headingRowColor: const WidgetStatePropertyAll(Colors.transparent),
      dataRowColor: const WidgetStatePropertyAll(Colors.transparent),
      headingTextStyle: TextStyle(
        color: c.textoSuave,
        fontFamily: 'Roboto',
        fontWeight: FontWeight.w500,
      ),
      dataTextStyle: TextStyle(color: c.texto, fontFamily: 'Roboto'),
      dividerThickness: 1,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Color.alphaBlend(c.chipFundo, c.fundo),
      selectedColor: c.chipAtivoFundo,
      labelStyle: TextStyle(color: c.chipTexto),
      secondaryLabelStyle: TextStyle(color: c.chipAtivoTexto),
      side: BorderSide(color: c.chipAtivoBorda ?? c.linha),
      shape: formaSemBorda,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: s.high,
      surfaceTintColor: Colors.transparent,
      shape: forma,
      textStyle: TextStyle(color: c.texto, fontFamily: 'Roboto'),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: s.high,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(c.raioCartao)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: s.highest,
      contentTextStyle: TextStyle(color: c.texto, fontFamily: 'Roboto'),
      actionTextColor: c.navAtivo,
      shape: formaSemBorda,
      behavior: SnackBarBehavior.floating,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: estiloBotao.copyWith(
        backgroundColor: WidgetStatePropertyAll(c.destaque),
        foregroundColor: WidgetStatePropertyAll(onPrimary),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: estiloBotao.copyWith(
        backgroundColor: WidgetStatePropertyAll(s.highest),
        foregroundColor: WidgetStatePropertyAll(c.texto),
        elevation: const WidgetStatePropertyAll(0),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: estiloBotao.copyWith(
        foregroundColor: WidgetStatePropertyAll(c.texto),
        side: WidgetStatePropertyAll(BorderSide(color: borda)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: estiloBotao.copyWith(
        foregroundColor: WidgetStatePropertyAll(c.navAtivo),
      ),
    ),
  );
}
