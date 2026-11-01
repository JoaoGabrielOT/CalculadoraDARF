import 'package:flutter/material.dart';

/// Paleta e medidas do tema visual ativo (extensão do `ThemeData`).
@immutable
class CoresApp extends ThemeExtension<CoresApp> {
  const CoresApp({
    required this.fundo,
    this.fundoGradiente,
    required this.cartao,
    required this.cartaoBorda,
    required this.sombraCartao,
    required this.raioCartao,
    required this.texto,
    required this.textoSuave,
    required this.alta,
    required this.queda,
    required this.seloAltaFundo,
    required this.seloQuedaFundo,
    required this.aviso,
    required this.destaque,
    this.destaqueGradiente,
    required this.chipFundo,
    required this.chipTexto,
    required this.chipAtivoFundo,
    required this.chipAtivoTexto,
    this.chipAtivoBorda,
    required this.bordaCampo,
    required this.linha,
    required this.logoFundo,
    required this.navAtivo,
    required this.densa,
  });

  final Color fundo;
  final Gradient? fundoGradiente;
  final Color cartao;
  final Color cartaoBorda;
  final List<BoxShadow> sombraCartao;
  final double raioCartao;
  final Color texto;
  final Color textoSuave;
  final Color alta;
  final Color queda;
  final Color seloAltaFundo;
  final Color seloQuedaFundo;
  final Color aviso;
  final Color destaque;

  /// Só decorativo: texto sobre ele precisa de cor escura (o branco não passa
  /// de 4,5:1 sobre o verde final #00b894).
  final Gradient? destaqueGradiente;
  final Color chipFundo;
  final Color chipTexto;
  final Color chipAtivoFundo;
  final Color chipAtivoTexto;
  final Color? chipAtivoBorda;

  /// Borda de campo e controle (WCAG 1.4.11, 3:1 sobre as superfícies); `linha`
  /// fica para divisórias e cartões decorativos.
  final Color bordaCampo;
  final Color linha;
  final Color logoFundo;
  final Color navAtivo;
  final bool densa;

  static CoresApp de(BuildContext context) =>
      Theme.of(context).extension<CoresApp>()!;

  @override
  CoresApp copyWith({
    Color? fundo,
    Gradient? fundoGradiente,
    Color? cartao,
    Color? cartaoBorda,
    List<BoxShadow>? sombraCartao,
    double? raioCartao,
    Color? texto,
    Color? textoSuave,
    Color? alta,
    Color? queda,
    Color? seloAltaFundo,
    Color? seloQuedaFundo,
    Color? aviso,
    Color? destaque,
    Gradient? destaqueGradiente,
    Color? chipFundo,
    Color? chipTexto,
    Color? chipAtivoFundo,
    Color? chipAtivoTexto,
    Color? chipAtivoBorda,
    Color? bordaCampo,
    Color? linha,
    Color? logoFundo,
    Color? navAtivo,
    bool? densa,
  }) => CoresApp(
    fundo: fundo ?? this.fundo,
    fundoGradiente: fundoGradiente ?? this.fundoGradiente,
    cartao: cartao ?? this.cartao,
    cartaoBorda: cartaoBorda ?? this.cartaoBorda,
    sombraCartao: sombraCartao ?? this.sombraCartao,
    raioCartao: raioCartao ?? this.raioCartao,
    texto: texto ?? this.texto,
    textoSuave: textoSuave ?? this.textoSuave,
    alta: alta ?? this.alta,
    queda: queda ?? this.queda,
    seloAltaFundo: seloAltaFundo ?? this.seloAltaFundo,
    seloQuedaFundo: seloQuedaFundo ?? this.seloQuedaFundo,
    aviso: aviso ?? this.aviso,
    destaque: destaque ?? this.destaque,
    destaqueGradiente: destaqueGradiente ?? this.destaqueGradiente,
    chipFundo: chipFundo ?? this.chipFundo,
    chipTexto: chipTexto ?? this.chipTexto,
    chipAtivoFundo: chipAtivoFundo ?? this.chipAtivoFundo,
    chipAtivoTexto: chipAtivoTexto ?? this.chipAtivoTexto,
    chipAtivoBorda: chipAtivoBorda ?? this.chipAtivoBorda,
    bordaCampo: bordaCampo ?? this.bordaCampo,
    linha: linha ?? this.linha,
    logoFundo: logoFundo ?? this.logoFundo,
    navAtivo: navAtivo ?? this.navAtivo,
    densa: densa ?? this.densa,
  );

  /// Os temas trocam por inteiro: sem interpolação, vale o mais próximo.
  @override
  CoresApp lerp(ThemeExtension<CoresApp>? other, double t) =>
      other is CoresApp && t >= 0.5 ? other : this;
}
