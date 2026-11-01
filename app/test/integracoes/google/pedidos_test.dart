import 'package:calculadoradarf/integracoes/integracoes.dart';
import 'package:calculadoradarf/nucleo/nucleo.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../nucleo/apoio/referencias.dart';

Map<String, Object?> _mapa(Object? o) => o! as Map<String, Object?>;
List<Object?> _lista(Object? o) => o! as List<Object?>;

Map<String, Object?> _pedido(Caso c, int i) =>
    _mapa(_lista(_mapa(c.saida)['pedidos'])[i]);

Object? _jsonDoPedido(Caso c, int i) => _pedido(c, i)['json'];

List<Object?> _args(Caso c) => _lista(_mapa(c.entrada)['args']);

Map<String, Object?> _jsonDaResposta(Caso c, int i) =>
    _mapa(_mapa(_lista(_mapa(c.entrada)['respostas'])[i])['json']);

/// `{título: sheetId}` de `sheets[].properties` (criação) ou de
/// `replies[].addSheet.properties` (abas novas).
Map<String, int> _ids(Iterable<Object?> propriedades) => {
  for (final p in propriedades)
    _mapa(p)['title']! as String: _mapa(p)['sheetId']! as int,
};

Iterable<Object?> _propsDeSheets(Map<String, Object?> json) =>
    ((json['sheets'] as List<Object?>?) ?? const <Object?>[]).map(
      (s) => _mapa(s)['properties'],
    );

Map<String, PropriedadesAba> _propriedades(Map<String, Object?> meta) => {
  for (final p in _propsDeSheets(meta))
    _mapa(p)['title']! as String: PropriedadesAba(
      sheetId: _mapa(p)['sheetId']! as int,
      titulo: _mapa(p)['title']! as String,
      linhas: _mapa(_mapa(p)['gridProperties'])['rowCount'] as int?,
      colunas: _mapa(_mapa(p)['gridProperties'])['columnCount'] as int?,
    ),
};

void main() {
  test('há casos', () {
    expect(carregarCasos('google_pedidos').length, greaterThanOrEqualTo(23));
  });

  test('rgb, letra e consultaPlanilha', () {
    expect(rgb('#1f2937'), {
      'red': 0x1f / 255,
      'green': 0x29 / 255,
      'blue': 0x37 / 255,
    });
    expect(letra(1), 'A');
    expect(letra(13), 'M');
    expect(
      consultaPlanilha("o'bri\\en@x.com"),
      "name = 'Calculadora DARF' and mimeType = "
      "'application/vnd.google-apps.spreadsheet' and trashed = false and "
      "'o\\'bri\\\\en@x.com' in owners",
    );
  });

  for (final caso in carregarCasos('google_pedidos')) {
    test('corpos do Python: ${caso.nome}', () {
      switch (caso.funcao) {
        case 'criar_planilha':
          conferir(_jsonDoPedido(caso, 0), corpoCriacao());
          final ids = _ids(_propsDeSheets(_jsonDaResposta(caso, 0)));
          conferir(_jsonDoPedido(caso, 1), {
            'requests': pedidosFormatacao(ids),
          });
        case 'garantir_abas':
          final meta = _jsonDaResposta(caso, 0);
          final existentes = _propsDeSheets(meta)
              .map((p) => _mapa(p)['title'])
              .toSet();
          final faltando = [
            for (final a in esquemaAbas)
              if (!existentes.contains(a.nome)) a.nome,
          ];
          if (faltando.isEmpty) {
            expect(_lista(_mapa(caso.saida)['pedidos']), hasLength(1));
            break;
          }
          conferir(_jsonDoPedido(caso, 1), pedidoAbasFaltantes(faltando));
          final novas = _ids(
            _lista(_jsonDaResposta(caso, 1)['replies'])
                .map((r) => _mapa(_mapa(r)['addSheet'])['properties']),
          );
          conferir(_jsonDoPedido(caso, 2), {
            'requests': pedidosFormatacao(novas),
          });
        case 'escrever':
          final dados = {
            for (final e in _mapa(_args(caso)[1]).entries)
              e.key: [for (final l in _lista(e.value)) _lista(l)],
          };
          final pedidos = _lista(_mapa(caso.saida)['pedidos']);
          conferir(_jsonDoPedido(caso, pedidos.length - 1), {
            'requests': pedidosEscrita(
              _propriedades(_jsonDaResposta(caso, 0)),
              dados,
            ),
          });
        case 'ler':
          final respostas = _lista(_mapa(caso.entrada)['respostas']);
          final meta = _mapa(_mapa(respostas[0])['json']);
          final colunas = {
            for (final p in _propsDeSheets(meta))
              _mapa(p)['title']! as String:
                  (_mapa(p)['gridProperties']
                          as Map<String, Object?>?)?['columnCount']
                      as int?,
          };
          if (_lista(_mapa(caso.saida)['pedidos']).length == 1) {
            expect(rangesLeitura(colunas), isEmpty);
            break;
          }
          final ranges = rangesLeitura(colunas);
          expect(_mapa(_pedido(caso, 1)['params'])['ranges'], ranges);
          final nomes = colunas.keys.where(
            (n) => esquemaAbas.any((a) => a.nome == n),
          );
          final ordenados = [
            for (final a in esquemaAbas)
              if (nomes.contains(a.nome)) a.nome,
          ];
          final valueRanges = _lista(
            _mapa(_mapa(respostas[1])['json'])['valueRanges'],
          );
          final lidas = <String, List<List<Object?>>>{
            for (var i = 0; i < ordenados.length; i++)
              ordenados[i]: [
                for (final l
                    in (_mapa(valueRanges[i])['values'] as List<Object?>?) ??
                        const <Object?>[])
                  _lista(l),
              ],
          };
          conferir(normalizarLeitura(lidas), _mapa(caso.saida)['resultado']);
        case 'buscar_planilha':
          expect(_mapa(_pedido(caso, 0)['params'])['q'], [
            consultaPlanilha(_args(caso)[0]! as String),
          ]);
        default:
        // planilha_existe, compartilhar e descompartilhar: pedidos sem
        // corpo montado em funções deste arquivo (Tarefa 10).
      }
    });
  }

  test('escrever sem endRowIndex: as linhas que sobram são limpas', () {
    final reqs = pedidosEscrita(
      {
        'Compras': PropriedadesAba(
          sheetId: 7,
          titulo: 'Compras',
          linhas: 1000,
          colunas: 13,
        ),
      },
      {'Compras': []},
    );
    final dados = reqs.last['updateCells']! as Map;
    expect(dados['range'], {
      'sheetId': 7,
      'startRowIndex': 1,
      'startColumnIndex': 0,
      'endColumnIndex': 13,
    });
    expect(dados['rows'], isEmpty);
    expect(dados['fields'], 'userEnteredValue');
  });
}
