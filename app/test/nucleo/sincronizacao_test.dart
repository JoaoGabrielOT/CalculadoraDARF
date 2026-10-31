import 'dart:convert';

import 'package:calculadoradarf/nucleo/ambiente.dart';
import 'package:calculadoradarf/nucleo/armazenamento.dart';
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
        r.linhas,
        saida['linhas'],
        caminho: r'$.linhas',
        // a ordem vem de um set no Python (nucleo.py:165-166)
        semOrdem: {r'$.linhas.Exclusões'},
      );
    });
  }
}
