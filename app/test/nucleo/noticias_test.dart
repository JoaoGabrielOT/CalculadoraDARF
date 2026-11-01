// Referências geradas pelo Python 3.12 (ferramentas/referencias/noticias.py).

import 'dart:convert';

import 'package:calculadoradarf/nucleo/ambiente.dart';
import 'package:calculadoradarf/nucleo/armazenamento.dart';
import 'package:calculadoradarf/nucleo/noticias/estado.dart';
import 'package:calculadoradarf/nucleo/noticias/texto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'apoio/referencias.dart';

Map<String, Object?> _mapa(Object? o) => o! as Map<String, Object?>;
List<Object?> _lista(Object? o) => o! as List<Object?>;

Noticia _noticia(Object? o) => Noticia.fromJson(_mapa(o));
List<Noticia> _noticias(Object? o) => [for (final i in _lista(o)) _noticia(i)];
List<Object?> _json(List<Noticia> l) => [for (final i in l) i.toJson()];
List<Object?> _textos(List<(String, String, String)> l) => [
  for (final t in l) [t.$1, t.$2, t.$3],
];

const _nome = 'noticias.json';

void main() {
  final casos = carregarCasos('noticias');
  Iterable<Caso> da(String funcao) => casos.where((c) => c.funcao == funcao);

  test('as referências vêm do Python 3.12', () {
    expect(versaoPythonDasReferencias('noticias'), startsWith('3.12'));
  });

  group('titulo', () {
    for (final c in da('titulo')) {
      test(c.nome, () {
        final e = _mapa(c.entrada);
        final s = _mapa(c.saida);
        final titulo = e['titulo']! as String;
        expect(semAcento(titulo), s['sem_acento']);
        expect(temas(titulo), s['temas']);
        expect(chaveTitulo(titulo), s['chave']);
        expect([
          for (final a in _lista(e['alvos']))
            pertinente(
              titulo,
              _lista(a)[0]! as String,
              nome: _lista(a)[1]! as String,
            ),
        ], s['pertinentes']);
      });
    }
  });

  group('nomeBusca e consulta', () {
    for (final c in da('nome_busca')) {
      test(c.nome, () {
        final e = _mapa(c.entrada);
        final s = _mapa(c.saida);
        final nome = e['nome'] as String?;
        expect(nomeBusca(nome), s['nome_busca']);
        expect(
          consulta(e['ticker']! as String, nome: nome ?? ''),
          s['consulta'],
        );
      });
    }
  });

  group('dominio e urlFavicon', () {
    for (final c in da('dominio')) {
      test(c.nome, () {
        final url = _mapa(c.entrada)['url']! as String;
        final s = _mapa(c.saida);
        expect(dominio(url), s['dominio']);
        final item = Noticia(
          id: 'x',
          titulo: 't',
          link: 'l',
          fonte: 'f',
          fonteUrl: url,
          data: 0,
          tickers: [],
          temas: [],
        );
        expect(urlFavicon(item), s['favicon']);
      });
    }
  });

  group('tempoRelativo', () {
    for (final c in da('tempo_relativo')) {
      test(c.nome, () {
        final e = _mapa(c.entrada);
        expect(
          tempoRelativo(
            (e['ts']! as num).toDouble(),
            agora: (e['agora']! as num).toDouble(),
          ),
          _mapa(c.saida)['texto'],
        );
      });
    }

    test('tempoRelativo acima de 7 dias usa a data local dd/mm/aaaa', () {
      const agora = 1761000000.0;
      const ts = agora - 8 * 86400;
      final d = DateTime.fromMillisecondsSinceEpoch((ts * 1000).toInt());
      final esperado =
          '${d.day.toString().padLeft(2, '0')}/'
          '${d.month.toString().padLeft(2, '0')}/${d.year}';
      expect(tempoRelativo(ts, agora: agora), esperado);
      expect(
        tempoRelativo(agora - 7 * 86400, agora: agora),
        isNot(startsWith('há')),
      );
      expect(tempoRelativo(agora - 7 * 86400 + 1, agora: agora), 'há 6 dias');
    });

    test('sem agora usa o relógio do ambiente', () {
      final antes = ambiente;
      addTearDown(() => ambiente = antes);
      ambiente = Ambiente.fixo(agora: 1761000000.0);
      expect(tempoRelativo(1761000000.0 - 120), 'há 2 min');
    });
  });

  group('iniciais e urlsLogo', () {
    for (final c in da('iniciais')) {
      test(c.nome, () {
        final t = _mapa(c.entrada)['ticker']! as String;
        final s = _mapa(c.saida);
        expect(iniciais(t), s['iniciais']);
        final (png, svg) = urlsLogo(t);
        expect(png, s['png']);
        expect(svg, s['svg']);
      });
    }
  });

  group('mesclar', () {
    for (final c in da('mesclar')) {
      test(c.nome, () {
        final listas = [
          for (final l in _lista(_mapa(c.entrada)['listas'])) _noticias(l),
        ];
        conferir(_json(mesclar(listas)), _mapa(c.saida)['itens']);
      });
    }

    test('não altera as listas de entrada', () {
      final a = _noticia({
        'id': 'a',
        'titulo': 'Título qualquer com dividendos',
        'link': 'l',
        'fonte': 'f',
        'fonte_url': 'u',
        'data': 1.0,
        'tickers': ['A'],
        'temas': ['Proventos'],
      });
      final b = _noticia(a.toJson())..tickers = ['B'];
      mesclar([
        [a],
        [b],
      ]);
      expect(a.tickers, ['A']);
    });
  });

  group('textosNotificacao', () {
    for (final c in da('textos_notificacao')) {
      test(c.nome, () {
        final novas = _noticias(_mapa(c.entrada)['novas']);
        conferir(_textos(textosNotificacao(novas)), _mapa(c.saida)['textos']);
      });
    }
  });

  group('lerEstado', () {
    for (final c in da('ler_estado')) {
      test(c.nome, () {
        final a = ArmazenamentoMemoria();
        final texto = _mapa(c.entrada)['arquivo'] as String?;
        if (texto != null) a.gravar(_nome, texto);
        conferir(lerEstado(a).toJson(), _mapa(c.saida)['estado']);
      });
    }
  });

  group('gravarEstado', () {
    for (final c in da('gravar_estado')) {
      test(c.nome, () {
        final a = ArmazenamentoMemoria();
        final estado = EstadoNoticias.fromJson(
          _mapa(_mapa(c.entrada)['estado']),
        );
        gravarEstado(a, estado);
        final s = _mapa(c.saida);
        expect(a.ler(_nome), s['arquivo']);
        expect(estado.vistos.keys.toList(), s['vistos']);
      });
    }
  });

  group('aplicarBusca, marcarLidas e não lidas', () {
    for (final c in da('roteiro')) {
      test(c.nome, () {
        final e = _mapa(c.entrada);
        final a = ArmazenamentoMemoria();
        final inicial = e['estado_inicial'];
        if (inicial != null) a.gravar(_nome, jsonEncode(inicial));
        final deslocamentos = [
          for (final d in _lista(e['deslocamentos'])) (d! as num).toDouble(),
        ];
        final esperados = _lista(_mapa(c.saida)['passos']);
        final passos = _lista(e['passos']);
        for (var i = 0; i < passos.length; i++) {
          final p = _mapa(passos[i]);
          final agora = (p['agora']! as num).toDouble();
          var novas = <Noticia>[];
          if (p['op'] == 'buscar') {
            final d = lerEstado(a);
            final tickers = <(String, String)>[];
            final listas = <List<Noticia>>[];
            final erros = <String, String>{};
            final respostas = _mapa(p['respostas']);
            for (final r in _lista(p['radar'])) {
              final t = _mapa(r)['ticker']! as String;
              tickers.add((t, _mapa(r)['nome']! as String));
              final resp = respostas[t];
              if (resp is Map) {
                erros[t] = '${resp['erro']}'.substring(
                  0,
                  '${resp['erro']}'.length < 200
                      ? '${resp['erro']}'.length
                      : 200,
                );
              } else {
                listas.add(_noticias(resp));
              }
            }
            novas = aplicarBusca(d, tickers, listas, erros, agora);
            gravarEstado(a, d);
          } else {
            marcarLidas(a, agora: agora);
          }
          final d = lerEstado(a);
          final esp = _mapa(esperados[i]);
          final onde = '${c.nome} passo $i';
          conferir(_json(novas), esp['novas'], caminho: '$onde novas');
          conferir(
            _textos(textosNotificacao(novas)),
            esp['textos'],
            caminho: '$onde textos',
          );
          expect(a.ler(_nome), esp['arquivo'], reason: '$onde arquivo');
          expect(naoLidas(d), esp['nao_lidas'], reason: '$onde nao_lidas');
          expect(
            [for (final item in d.itens) ehNova(d, item)],
            esp['eh_nova'],
            reason: '$onde eh_nova',
          );
          expect(
            [
              for (final dz in deslocamentos)
                precisaAtualizar(d, agora: agora + dz),
            ],
            esp['precisa'],
            reason: '$onde precisa',
          );
        }
      });
    }

    test('precisaAtualizar sem agora usa o relógio do ambiente', () {
      final antes = ambiente;
      addTearDown(() => ambiente = antes);
      ambiente = Ambiente.fixo(agora: 1000.0);
      final d = EstadoNoticias.fromJson({'hora': 400.0});
      expect(precisaAtualizar(d), isTrue);
      d.hora = 401.0;
      expect(precisaAtualizar(d), isFalse);
    });
  });
}
