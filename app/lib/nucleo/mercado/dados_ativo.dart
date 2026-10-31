import 'indicadores.dart';

double? _numOuNulo(Object? v) => v is num ? v.toDouble() : null;

/// Cotação e indicadores de um ativo (o dict de `mercado._extras`). As chaves
/// JSON são as do Python; `risco` é a lista de 3 textos.
class DadosAtivo {
  DadosAtivo({
    required this.ticker,
    this.nome = '',
    this.preco,
    this.media6m,
    this.atr,
    this.atrPct,
    this.risco,
    this.hora = 0,
    this.anterior,
    this.variacao,
    this.variacaoPct,
    this.min6m,
    this.max6m,
    this.variacao6mPct,
    this.vsMediaPct,
    this.maxDia,
    this.minDia,
    this.max52,
    this.min52,
    this.volume,
  });

  factory DadosAtivo.fromJson(Map<String, Object?> json) {
    final r = json['risco'];
    return DadosAtivo(
      ticker: json['ticker'] is String ? json['ticker']! as String : '',
      nome: json['nome'] is String ? json['nome']! as String : '',
      preco: _numOuNulo(json['preco']),
      media6m: _numOuNulo(json['media6m']),
      atr: _numOuNulo(json['atr']),
      atrPct: _numOuNulo(json['atr_pct']),
      risco: r is List && r.length == 3
          ? (
              rotulo: r[0]! as String,
              fundo: r[1]! as String,
              texto: r[2]! as String,
            )
          : null,
      hora: _numOuNulo(json['hora']) ?? 0,
      anterior: _numOuNulo(json['anterior']),
      variacao: _numOuNulo(json['var']),
      variacaoPct: _numOuNulo(json['var_pct']),
      min6m: _numOuNulo(json['min6m']),
      max6m: _numOuNulo(json['max6m']),
      variacao6mPct: _numOuNulo(json['var6m_pct']),
      vsMediaPct: _numOuNulo(json['vs_media_pct']),
      maxDia: _numOuNulo(json['max_dia']),
      minDia: _numOuNulo(json['min_dia']),
      max52: _numOuNulo(json['max52']),
      min52: _numOuNulo(json['min52']),
      volume: _numOuNulo(json['volume']),
    );
  }

  String ticker;
  String nome;
  double? preco;
  double? media6m;
  double? atr;
  double? atrPct;
  Risco? risco;

  /// Instante da cotação, em segundos desde a época (`ambiente.agora()`).
  double hora;
  double? anterior;
  double? variacao;
  double? variacaoPct;
  double? min6m;
  double? max6m;
  double? variacao6mPct;
  double? vsMediaPct;
  double? maxDia;
  double? minDia;
  double? max52;
  double? min52;
  double? volume;

  Map<String, Object?> toJson() => {
    'ticker': ticker,
    'nome': nome,
    'preco': preco,
    'media6m': media6m,
    'atr': atr,
    'atr_pct': atrPct,
    'risco': risco == null ? null : [risco!.rotulo, risco!.fundo, risco!.texto],
    'hora': hora,
    'anterior': anterior,
    'var': variacao,
    'var_pct': variacaoPct,
    'min6m': min6m,
    'max6m': max6m,
    'var6m_pct': variacao6mPct,
    'vs_media_pct': vsMediaPct,
    'max_dia': maxDia,
    'min_dia': minDia,
    'max52': max52,
    'min52': min52,
    'volume': volume,
  };
}
