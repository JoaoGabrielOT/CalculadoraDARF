import 'dart:convert';

import 'package:calculadoradarf/nucleo/ambiente.dart';
import 'package:calculadoradarf/nucleo/armazenamento.dart';
import 'package:calculadoradarf/nucleo/fechamento.dart';
import 'package:calculadoradarf/nucleo/modelos/mes.dart';
import 'package:calculadoradarf/nucleo/planilha/celula.dart';
import 'package:calculadoradarf/nucleo/planilha/sincronizacao.dart';
import 'package:calculadoradarf/nucleo/repositorio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'apoio/referencias.dart';

Map<String, Object?> _mapa(Object? o) => o! as Map<String, Object?>;

void main() {
  tearDown(() => ambiente = Ambiente.sistema());

  test('referências geradas com Python 3.12', () {
    expect(versaoPythonDasReferencias('sincronizacao'), startsWith('3.12'));
  });

  for (final caso in carregarCasos('sincronizacao')) {
    test('sincronizar: ${caso.nome}', () {
      final entrada = _mapa(caso.entrada);
      final saida = _mapa(caso.saida);
      ambiente = Ambiente.fixo(agora: (entrada['agora']! as num).toDouble());
      final memoria = ArmazenamentoMemoria();
      for (final e in _mapa(entrada['arquivos']).entries) {
        memoria.gravar(e.key, jsonEncode(e.value));
      }
      final repo = Repositorio(memoria);
      final cfg = repo.lerConfig();
      final abas = <String, List<Linha>>{
        for (final e in _mapa(entrada['abas']).entries)
          e.key: [
            for (final l in e.value! as List<Object?>)
              List<Object?>.of(l! as List<Object?>),
          ],
      };

      final r = sincronizarLinhas(repo, cfg, abas);

      expect(r.mudou, saida['mudou']);
      expect(r.avisos, saida['avisos']);
      conferir(cfg.toJson(), saida['cfg'], caminho: r'$.cfg');
      conferir(
        {
          for (final nome in memoria.listar())
            nome: jsonDecode(memoria.ler(nome)!),
        },
        saida['arquivos'],
        caminho: r'$.arquivos',
      );
      conferir(
        semDetalhesDoResumo(r.linhas),
        saida['linhas'],
        caminho: r'$.linhas',
        // a ordem vem de um set no Python (nucleo.py:165-166)
        semOrdem: {r'$.linhas.Exclusões'},
      );
    });
  }

  test('mês fechado pelo custo médio continua marcado depois de uma '
      'regravação da 1.12 (13 colunas, mod maior)', () {
    ambiente = Ambiente.fixo(agora: 100);
    final memoria = ArmazenamentoMemoria();
    final repo = Repositorio(memoria);
    repo.salvar(
      Mes(
        mes: '2026-11',
        fechado: true,
        mod: 10,
        metodo: metodoCustoMedio,
        posicaoInicial: {},
        prejuizoAnterior: PrejuizoAcumulado(comum: 3.5),
      ),
      carimbar: false,
    );
    final cfg = repo.lerConfig();
    final r = sincronizarLinhas(repo, cfg, {
      'Resumo': [
        ['11/2026', 'Fechado', 0, 'Sim', 0, 0, 0, 0, 0, 0, 0, 0, 20.0],
      ],
    });
    final d = repo.carregar('2026-11');
    expect(d.metodo, metodoCustoMedio);
    expect(d.mod, 20.0);
    expect(mesPorCustoMedio(repo, '2026-11'), isTrue);
    expect(mesPorCustoMedio(repo, '2026-12'), isTrue);
    expect(
      r.linhas['Resumo']!.single[13],
      '{"mes":"2026-11","mod":20.0,"metodo":"custo_medio",'
      '"posicao_inicial":{},'
      '"prejuizo_anterior":{"comum":3.5,"day_trade":0.0}}',
    );
  });
}
