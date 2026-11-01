// Reconstrução dos dados a partir das linhas lidas da planilha, com a
// compatibilidade de leitura da 1.12 (nucleo.py:837-972).

import '../ambiente.dart';
import '../apuracao.dart';
import '../compat/conversao.dart';
import '../compat/json_python.dart';
import '../datas.dart';
import '../modelos/com_mod.dart';
import '../modelos/config.dart';
import '../modelos/lote.dart';
import '../modelos/mes.dart';
import '../modelos/meta.dart';
import 'celula.dart';

/// O que `reconstruir` devolve: (meses, amigos, radar, exclusões da
/// configuração, caixa).
class DadosPlanilha {
  DadosPlanilha({
    required this.meses,
    required this.amigos,
    required this.radar,
    required this.excluidos,
    required this.caixa,
  });

  final Map<String, Mes> meses;
  final List<Amigo> amigos;
  final List<ItemRadar> radar;

  /// `"<lista>:<chave>"` -> momento da exclusão.
  final Map<String, double> excluidos;
  final Caixa? caixa;
}

/// Onde o Python captura `(ValueError, TypeError[, IndexError])`. `TypeError`
/// fica por paridade com o `except TypeError` do Python (as conversões de
/// compat já lançam `FormatException` onde o Python lançaria `TypeError`).
bool _erroDeLeitura(Object e) =>
    e is FormatException || e is RangeError || e is TypeError;

/// Linhas completadas com `""` até [largura], sem cortar as mais largas.
List<Linha> _completar(List<Linha>? linhas, int largura) => [
  for (final r in linhas ?? const <Linha>[])
    [...r, for (var i = r.length; i < largura; i++) ''],
];

/// `reconstruir` (nucleo.py:837-927).
DadosPlanilha reconstruir(Map<String, List<Linha>> abas) {
  final resumo = _completar(abas['Resumo'], 13);
  final compras = _completar(abas['Compras'], 13);
  final vendas = _completar(abas['Vendas'], 17);
  final amigosLinhas = _completar(abas['Amigos'], 3);
  final radarLinhas = _completar(abas['Radar'], 5);
  final exclusoes = _completar(abas['Exclusões'], 4);
  final caixaLinhas = _completar(abas['Caixa'], 3);

  final meses = <String, Mes>{};
  final lotes = <(String, String), Lote>{};
  for (final row in resumo) {
    try {
      final mes = mesIso(row[0]);
      meses[mes] = Mes(
        mes: mes,
        fechado: row[1] == 'Fechado',
        darfAnterior: numOuPadrao(row[10]),
        mod: numOuPadrao(row[12]),
      );
    } catch (e) {
      if (!_erroDeLeitura(e)) rethrow;
    }
  }
  for (final row in compras) {
    final String mes;
    final Lote l;
    try {
      mes = mesIso(row[0]);
      // a ordem importa: o id novo é gasto antes de qualquer outra falha
      final id = strPython(row[10]);
      final idFinal = id.isNotEmpty ? id : ambiente.novoId();
      l = Lote(
        id: idFinal,
        ticker: strPython(row[1]).toUpperCase(),
        tipo: strPython(row[2]),
        dataCompra: deSerial(row[3]),
        qtd: intPython(row[4]),
        preco: floatPython(row[5]),
        mod: numOuPadrao(row[12]),
      );
    } catch (e) {
      if (!_erroDeLeitura(e)) rethrow;
      continue;
    }
    if (verdadeiroPython(row[11])) l.origem = strPython(row[11]);
    meses.putIfAbsent(mes, () => mesVazio(mes)).lotes.add(l);
    lotes[(mes, l.id)] = l;
  }
  for (final row in vendas) {
    try {
      final mes = mesIso(row[0]);
      final l = lotes[(mes, strPython(row[15]))];
      if (l != null) {
        final id = strPython(row[14]);
        final idFinal = id.isNotEmpty ? id : ambiente.novoId();
        l.vendas.add(
          Venda(
            id: idFinal,
            data: deSerial(row[5]),
            qtd: intPython(row[6]),
            preco: floatPython(row[7]),
            mod: numOuPadrao(row[16]),
          ),
        );
      }
    } catch (e) {
      if (!_erroDeLeitura(e)) rethrow;
    }
  }
  final exclCfg = <String, double>{};
  for (final row in exclusoes) {
    try {
      final tipo = strPython(row[0]);
      final rotulo = row[1];
      final valor = strPython(row[2]);
      final t = numOuPadrao(row[3]);
      if (tipo == 'registro') {
        final mes = mesIso(rotulo);
        meses.putIfAbsent(mes, () => mesVazio(mes)).excluidos[valor] = t;
      } else if (valor.isNotEmpty) {
        exclCfg['$tipo:$valor'] = t;
      }
    } catch (e) {
      if (!_erroDeLeitura(e)) rethrow;
    }
  }
  final amigos = <Amigo>[];
  for (final row in amigosLinhas) {
    final email = strPython(row[0]).trim().toLowerCase();
    if (email.isNotEmpty) {
      amigos.add(
        Amigo(
          email: email,
          desde: _dataOuHoje(row[1]),
          mod: numOuPadrao(row[2]),
        ),
      );
    }
  }
  final radar = <ItemRadar>[];
  for (final row in radarLinhas) {
    final ticker = strPython(row[0]).trim().toUpperCase();
    if (ticker.isNotEmpty && radar.every((r) => r.ticker != ticker)) {
      final desde = _dataOuHoje(row[2]);
      radar.add(
        ItemRadar(
          ticker: ticker,
          nome: verdadeiroPython(row[1]) ? strPython(row[1]) : '',
          desde: desde,
          mod: numOuPadrao(row[3]),
          // planilhas antigas não têm a coluna Posição
          pos: _posicao(row[4]),
        ),
      );
    }
  }
  Caixa? caixa;
  for (final row in caixaLinhas.take(1)) {
    try {
      caixa = Caixa(
        saldo: numOuPadrao(row[0]),
        data: deSerial(row[1]),
        mod: numOuPadrao(row[2]),
      );
    } catch (e) {
      if (!_erroDeLeitura(e)) rethrow;
      caixa = null;
    }
  }
  for (final d in meses.values) {
    corrigirTiposMes(d);
  }
  return DadosPlanilha(
    meses: meses,
    amigos: amigos,
    radar: radar,
    excluidos: exclCfg,
    caixa: caixa,
  );
}

/// Posição do radar (nucleo.py:900-901). Posição que não cabe em int64 (o
/// Python segue com inteiro grande) fica nula, como a de um item sem Posição,
/// em vez de derrubar a planilha; NaN e infinito continuam lançando, como no
/// Python.
int? _posicao(Object? v) {
  if (strPython(v).trim() == '') return null;
  final n = numOuPadrao(v);
  if (n.isFinite && (n >= 9.223372036854776e18 || n < -9.223372036854776e18)) {
    return null;
  }
  return intPython(n);
}

String _dataOuHoje(Object? v) {
  try {
    return deSerial(v);
  } catch (e) {
    if (!_erroDeLeitura(e)) rethrow;
    return ambiente.hoje();
  }
}

/// `str(v)` de um valor vindo de JSON. Listas e mapas (cujo `repr` o Dart não
/// reproduz) resultam em `FormatException`.
String _strJson(Object? v) {
  if (v is Map || v is List) {
    throw const FormatException('str() de lista ou objeto não suportado');
  }
  return strPython(v);
}

/// O que `for x in v` percorre: itens de lista, chaves de objeto, caracteres
/// de texto; os demais não são iteráveis (`TypeError`).
Iterable<Object?> _iterar(Object? v) {
  if (v is List) return v;
  if (v is Map) return v.keys;
  if (v is String) return v.runes.map(String.fromCharCode);
  throw const FormatException('valor não iterável');
}

/// `detalhes[chave]`; chave ausente é `KeyError`.
Object? _obrigatorio(Map<Object?, Object?> m, String chave) {
  if (!m.containsKey(chave)) throw FormatException('falta "$chave"');
  return m[chave];
}

class _CamposStop {
  _CamposStop(this.stopInicial, this.stopAtual, this.movel, this.niveis);

  final double stopInicial;
  final double stopAtual;
  final bool movel;
  final List<Nivel> niveis;
}

/// `_campos_stop` (nucleo.py:930-941): nulo se faltam campos ou estão
/// malformados.
_CamposStop? _camposStop(Map<String, Object?> detalhes) {
  try {
    final stopInicial = floatPython(_obrigatorio(detalhes, 'stop_inicial'));
    final stopAtual = floatPython(_obrigatorio(detalhes, 'stop_atual'));
    final movel = verdadeiroPython(detalhes['movel']);
    final niveis = <Nivel>[];
    for (final n in _iterar(_obrigatorio(detalhes, 'niveis'))) {
      if (n is! Map) throw const FormatException('nível malformado');
      final desde = _strJson(_obrigatorio(n, 'desde'));
      niveis.add(
        Nivel(
          desde: desde,
          stop: floatPython(_obrigatorio(n, 'stop')),
          calcEm: _strJson(
            n.containsKey('calc_em') ? n['calc_em'] : n['desde'],
          ),
        ),
      );
    }
    return _CamposStop(stopInicial, stopAtual, movel, niveis);
  } catch (e) {
    if (!_erroDeLeitura(e)) rethrow;
    return null;
  }
}

/// `reconstruir_metas` (nucleo.py:944-972): metas da aba "Metas". A linha só
/// é um stop quando os Detalhes são desta linha e trazem os campos do stop;
/// do contrário vale o Preço-alvo (se também não for número, é descartada).
List<Meta> reconstruirMetas(Map<String, List<Linha>> abas) {
  final metas = <Meta>[];
  for (final linha in _completar(abas['Metas'], 14)) {
    final row = linha.sublist(0, 14);
    var detalhes = <String, Object?>{};
    if (verdadeiroPython(row[13])) {
      try {
        final lido = jsonPythonDecode(strPython(row[13]));
        // os detalhes só valem se são desta linha (a planilha pode ter sido
        // reordenada à mão)
        if (lido is Map && lido['id'] == strPython(row[0]).trim()) {
          detalhes = lerMapa(lido);
        }
      } on FormatException {
        // JSON inválido: sem detalhes
      }
    }
    final campos = detalhes.isNotEmpty ? _camposStop(detalhes) : null;
    final stop =
        campos != null &&
        (strPython(row[12]).trim() == 'stop' || detalhes['gatilho'] == 'stop');
    final Meta m;
    try {
      m = Meta(
        id: strPython(row[0]).trim(),
        ticker: strPython(row[1]).trim().toUpperCase(),
        tipo: strPython(row[2]),
        loteId: strPython(row[3]),
        qtd: intPython(row[4]),
        criadaEm: strPython(row[7]),
        status: strPython(row[8]).isNotEmpty ? strPython(row[8]) : 'ativa',
        mod: numOuPadrao(row[11]),
      );
      if (stop) {
        m.gatilho = 'stop';
        m.stopInicial = campos.stopInicial;
        m.stopAtual = campos.stopAtual;
        m.movel = campos.movel;
        m.niveis = campos.niveis;
      } else {
        m.precoAlvo = floatPython(row[5]);
      }
      DataHora.parse(m.criadaEm);
    } catch (e) {
      if (!_erroDeLeitura(e)) rethrow;
      continue;
    }
    if (m.id.isEmpty || m.ticker.isEmpty) continue;
    if (row[6] != '') m.lucroDesejado = numOuPadrao(row[6]);
    if (verdadeiroPython(row[10])) {
      try {
        final lido = jsonPythonDecode(strPython(row[10]));
        // Meta só guarda a execução quando é um objeto
        if (lido is Map) m.execucao = lerMapa(lido);
      } on FormatException {
        // JSON inválido: sem execução
      }
    }
    if (verdadeiroPython(row[9])) m.ultimoErro = strPython(row[9]);
    for (final k in const ['oco', 'cancelada_por', 'cancelada_detalhe']) {
      if (!verdadeiroPython(detalhes[k])) continue;
      final String texto;
      try {
        texto = _strJson(detalhes[k]);
      } on FormatException {
        continue;
      }
      switch (k) {
        case 'oco':
          m.oco = texto;
        case 'cancelada_por':
          m.canceladaPor = texto;
        default:
          m.canceladaDetalhe = texto;
      }
    }
    if (detalhes['sugestao'] is Map) m.sugestao = lerMapa(detalhes['sugestao']);
    metas.add(m);
  }
  return metas;
}
