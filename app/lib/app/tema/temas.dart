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
  textoSuave: Color(0xFF7D8590),
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
  textoSuave: Color(0xFF8A90A6),
  alta: Color(0xFF14833B),
  queda: Color(0xFFC62828),
  seloAltaFundo: Color(0xFFE3F6EA),
  seloQuedaFundo: Color(0xFFFDE8E8),
  aviso: Color(0xFFB26A00),
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
  textoSuave: Color(0xFF7C84A8),
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

/// Tema Material 3 para um tema já resolvido (nunca `automatico`).
ThemeData temaDe(TemaVisual resolvido) {
  assert(resolvido != TemaVisual.automatico, 'resolva o automático antes');
  final cores = switch (resolvido) {
    TemaVisual.terminal => _terminal,
    TemaVisual.moderno => _moderno,
    _ => _claro,
  };
  final escuro = cores != _claro;
  final base = ColorScheme.fromSeed(
    seedColor: cores.destaque,
    brightness: escuro ? Brightness.dark : Brightness.light,
  );
  final esquema = base.copyWith(
    primary: cores.destaque,
    onPrimary: Colors.white,
    surface: cores.cartao,
    onSurface: cores.texto,
    error: cores.queda,
    outline: cores.cartaoBorda,
    outlineVariant: cores.linha,
  );
  return ThemeData(
    useMaterial3: true,
    fontFamily: 'Roboto',
    colorScheme: esquema,
    scaffoldBackgroundColor: cores.fundo,
    canvasColor: cores.fundo,
    dividerColor: cores.linha,
    visualDensity: cores.densa ? VisualDensity.compact : VisualDensity.standard,
    extensions: [cores],
  );
}
