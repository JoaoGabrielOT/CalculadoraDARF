// Referências geradas pelo Python 3.12 (ferramentas/referencias/sugestoes.py).
// Exceção: onde o Python lança OverflowError (ATR infinito), o Dart lança
// ErroValidacao com a mesma mensagem; compara-se a mensagem.

import 'dart:convert';

import 'package:calculadoradarf/nucleo/ambiente.dart';
import 'package:calculadoradarf/nucleo/armazenamento.dart';
import 'package:calculadoradarf/nucleo/erros.dart';
import 'package:calculadoradarf/nucleo/modelos/barras.dart';
import 'package:calculadoradarf/nucleo/modelos/config.dart';
import 'package:calculadoradarf/nucleo/modelos/lote.dart';
import 'package:calculadoradarf/nucleo/repositorio.dart';
import 'package:calculadoradarf/nucleo/sugestoes/patrimonio.dart';
import 'package:calculadoradarf/nucleo/sugestoes/sugestoes.dart';
import 'package:calculadoradarf/nucleo/sugestoes/textos.dart';
import 'package:flutter_test/flutter_test.dart';

import 'apoio/referencias.dart';

Map<String, Object?> _mapa(Object? o) => o! as Map<String, Object?>;
List<Object?> _lista(Object? o) => o! as List<Object?>;
double? _dbl(Object? o) => o == null ? null : (o as num).toDouble();

List<Object?> _linhas(List<LinhaCard> l) => [
  for (final x in l) [x.$1, x.$2, x.$3],
];

Map<String, Object?> _sug(Sugestao s) => {
  'modo': s.modo,
  'atr14': s.atr14,
  'atr22': s.atr22,
  if (s.modo == 'swing') ...{
    'stop_inicial': s.stopInicial,
    'chandelier': s.chandelier,
  } else ...{
    'pp': s.pp,
    'r1': s.r1,
    's1': s.s1,
  },
  'stop': s.stop,
  'alvo': s.alvo,
  'movel_disponivel': s.movelDisponivel,
  'base_data': s.baseData,
  'preco_atual': s.precoAtual,
  'stop_valido': s.stopValido,
  'alvo_imediato': s.alvoImediato,
  'avisos': s.avisos,
};

Map<String, Object?> _aval(Avaliacao a) => {
  'proj_alvo': a.projAlvo.toJson(),
  'proj_stop': a.projStop.toJson(),
  'lucro_alvo': a.lucroAlvo,
  'perda_stop': a.perdaStop,
  'dist_alvo_pct': a.distAlvoPct,
  'dist_stop_pct': a.distStopPct,
  'rr_preco': a.rrPreco,
  'rr_liquido': a.rrLiquido,
};

Map<String, Object?> _alerta(AlertaRisco a) => {
  'pct': a.pct,
  'limite': a.limite,
  'excede': a.excede,
};

Map<String, Object?> _item(ItemSugestao i) => {
  'qtd': i.qtd,
  'sug': i.sug == null ? null : _sug(i.sug!),
  'aval': i.aval == null ? null : _aval(i.aval!),
  'alerta': i.alerta == null ? null : _alerta(i.alerta!),
  'erro': i.erro,
  'preco_atual': i.precoAtual,
};

Map<String, Object?> _pat(Patrimonio p) => {
  'valor': p.valor,
  'caixa': p.caixa,
  'posicoes': p.posicoes,
  'caixa_definido': p.caixaDefinido,
  'sem_cotacao': p.semCotacao,
};

Patrimonio? _patDe(Object? o) {
  if (o == null) return null;
  final m = _mapa(o);
  return Patrimonio(
    valor: _dbl(m['valor'])!,
    caixa: _dbl(m['caixa'])!,
    posicoes: _dbl(m['posicoes'])!,
    caixaDefinido: m['caixa_definido']! as bool,
    semCotacao: [for (final t in _lista(m['sem_cotacao'])) t! as String],
  );
}

void _grade(Caso caso) {
  final e = _mapa(caso.entrada);
  final series = <String, List<BarraDiaria>>{
    for (final s in _mapa(e['series']).entries)
      s.key: [
        for (final b in _lista(s.value))
          BarraDiaria(
            data: _mapa(b)['data']! as String,
            abre: _dbl(_mapa(b)['abre']),
            alta: _dbl(_mapa(b)['alta'])!,
            baixa: _dbl(_mapa(b)['baixa'])!,
            fech: _dbl(_mapa(b)['fech'])!,
          ),
      ],
  };
  final saida = _lista(_mapa(caso.saida)['resultados']);
  for (final (i, bruto) in _lista(e['entradas']).indexed) {
    final x = _mapa(bruto);
    final lote = Lote.fromJson(_mapa(x['lote']));
    final diarias = Diarias(
      barras: series[x['serie']]!,
      hoje: '2026-10-28',
      preco: _dbl(x['preco']),
      fonte: 'Yahoo Finance',
    );
    Object? obtido;
    try {
      final item = montarItem(
        lote,
        (x['qtd']! as num).toInt(),
        diarias,
        valorPatrimonio: _dbl(x['patrimonio']),
        hoje: x['hoje'] as String?,
      );
      obtido = {'item': _item(item), 'linhas': _linhas(linhasCard(item))};
    } on Exception catch (ex) {
      final esperado = _mapa(saida[i]);
      expect(
        esperado.containsKey('excecao'),
        isTrue,
        reason: 'entrada $i: $ex',
      );
      obtido = {'excecao': esperado['excecao'], 'mensagem': ex.toString()};
    }
    conferir(obtido, saida[i], caminho: '\$.resultados[$i]');
  }
}

void _erros(Caso caso) {
  final saida = _lista(_mapa(caso.saida)['resultados']);
  for (final (i, bruto) in _lista(_mapa(caso.entrada)['entradas']).indexed) {
    final x = _mapa(bruto);
    final Object d = x['tipo'] == 'sem_dados'
        ? SemDados(x['valor']! as String)
        : x['valor']! as String;
    final item = montarItem(
      Lote.fromJson(_mapa(x['lote'])),
      (x['qtd']! as num).toInt(),
      d,
    );
    conferir(
      {'erro': item.erro, 'linhas': _linhas(linhasCard(item))},
      saida[i],
      caminho: '\$.resultados[$i]',
    );
  }
}

void _alertas(Caso caso) {
  final e = _mapa(caso.entrada);
  final saida = _mapa(caso.saida);
  for (final (i, r) in _lista(e['resultados']).indexed) {
    for (final (j, p) in _lista(e['patrimonios']).indexed) {
      conferir(
        _alerta(alertaRisco(_dbl(r)!, _dbl(p))),
        saida['$i|$j'],
        caminho: '\$.$i|$j',
      );
    }
  }
}

void _patrimonio(Caso caso) {
  final e = _mapa(caso.entrada);
  final memoria = ArmazenamentoMemoria();
  for (final a in _mapa(e['arquivos']).entries) {
    memoria.gravar(a.key, jsonEncode(a.value));
  }
  final repo = Repositorio(memoria);
  final meses = repo.carregarMeses();
  final saida = _lista(_mapa(caso.saida)['cenarios']);
  for (final (i, bruto) in _lista(e['cenarios']).indexed) {
    final c = _mapa(bruto);
    final cfg = Config.fromJson({'caixa': c['caixa']});
    final cotacoes = <String, double>{
      for (final k in _mapa(c['cotacoes']).entries) k.key: _dbl(k.value)!,
    };
    final hoje = c['hoje']! as String;
    final (pat2, res) = resumoPatrimonio(repo, cfg, cotacoes, hoje: hoje);
    final esperado = _mapa(saida[i]);
    conferir(
      {
        'patrimonio': _pat(patrimonio(cfg, cotacoes, meses, hoje: hoje)),
        'resumo': [_pat(pat2), res],
        'resultados': {
          for (final m in _mapa(esperado['resultados']).keys)
            m: resultadoMes(meses, m),
        },
      },
      esperado,
      caminho: '\$.cenarios[$i]',
    );
  }
}

void _rodape(Caso caso) {
  final e = _mapa(caso.entrada);
  final saida = _mapa(caso.saida);
  for (final (i, p) in _lista(e['patrimonios']).indexed) {
    for (final (j, r) in _lista(e['resultados']).indexed) {
      conferir(
        _linhas(linhasRodape(_patDe(p), _dbl(r)!)),
        saida['$i|$j'],
        caminho: '\$.$i|$j',
      );
    }
  }
}

void main() {
  setUp(() => ambiente = Ambiente.fixo());
  tearDown(() => ambiente = Ambiente.sistema());

  for (final caso in carregarCasos('sugestoes')) {
    test('${caso.funcao}: ${caso.nome}', () {
      switch (caso.funcao) {
        case 'grade_sugestoes':
          _grade(caso);
        case 'erros_item':
          _erros(caso);
        case 'alerta_risco':
          _alertas(caso);
        case 'patrimonio':
          _patrimonio(caso);
        case 'rodape':
          _rodape(caso);
        default:
          fail('função desconhecida: ${caso.funcao}');
      }
    });
  }
}
