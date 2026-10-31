import 'dart:convert';

import 'package:calculadoradarf/nucleo/ambiente.dart';
import 'package:calculadoradarf/nucleo/armazenamento.dart';
import 'package:calculadoradarf/nucleo/erros.dart';
import 'package:calculadoradarf/nucleo/fechamento.dart';
import 'package:calculadoradarf/nucleo/repositorio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'apoio/referencias.dart';

Map<String, Object?> _mapa(Object? o) => o! as Map<String, Object?>;

/// Executa uma operação do roteiro; devolve o retorno como JSON.
Object? _executar(Repositorio repo, Map<String, Object?> op) {
  try {
    switch (op['op']) {
      case 'fechar_mes':
        final (r, prox) = fecharMes(repo, repo.carregar(op['mes']! as String));
        return {'apuracao': r.toJson(), 'prox': prox};
      case 'mes_aceita':
        return mesAceitaVendaRetroativa(
          repo,
          op['mes']! as String,
          op['mes_atual']! as String,
        );
      case 'registrar_retroativa':
        final v = _mapa(op['venda']);
        return registrarVendaRetroativa(
          repo,
          repo.carregar(op['mes']! as String),
          op['lote_id']! as String,
          (
            data: v['data']! as String,
            qtd: (v['qtd']! as num).toInt(),
            preco: (v['preco']! as num).toDouble(),
          ),
        );
      case 'corrigir_tipos':
        return corrigirTipos(repo);
      case 'historico':
        final (freq, tipos) = historicoTickers(
          repo,
          mesesRecentes: (op['meses_recentes']! as num).toInt(),
        );
        return {'freq': freq, 'tipos': tipos};
      case 'sugestoes':
        final (lista, tipos) = sugestoesTickers(
          repo,
          repo.carregar(op['mes']! as String),
          soCustodia: op['so_custodia']! as bool,
        );
        return {'lista': lista, 'tipos': tipos};
      case 'custodia_atual':
        return custodiaAtual(repo).toList()..sort();
    }
  } on ErroValidacao catch (e) {
    return {'erro': e.mensagem};
  }
  throw StateError('operação desconhecida: ${op['op']}');
}

void main() {
  tearDown(() => ambiente = Ambiente.sistema());

  test('referências geradas com Python 3.12', () {
    expect(versaoPythonDasReferencias('fechamento'), startsWith('3.12'));
  });

  for (final caso in carregarCasos('fechamento')) {
    test('roteiro: ${caso.nome}', () {
      final entrada = _mapa(caso.entrada);
      final memoria = ArmazenamentoMemoria();
      for (final e in _mapa(entrada['arquivos']).entries) {
        memoria.gravar(e.key, jsonEncode(e.value));
      }
      final repo = Repositorio(memoria);
      final fixo = Ambiente.fixo();
      var agora = 0.0;
      // ids contínuos no roteiro; só o relógio muda entre as operações
      ambiente = Ambiente(
        agora: () => agora,
        novoId: fixo.novoId,
        hoje: fixo.hoje,
        agoraBr: fixo.agoraBr,
      );
      final esperados = _mapa(caso.saida)['resultados']! as List<Object?>;
      final operacoes = entrada['operacoes']! as List<Object?>;
      for (final (i, bruta) in operacoes.indexed) {
        final op = _mapa(bruta);
        agora = (op['agora']! as num).toDouble();
        final esperado = _mapa(esperados[i]);
        final caminho = '\$.resultados[$i]';
        conferir(
          _executar(repo, op),
          esperado['retorno'],
          caminho: '$caminho.retorno',
        );
        final arquivos = _mapa(esperado['arquivos']);
        expect(
          memoria.listar().toSet(),
          arquivos.keys.toSet(),
          reason: '$caminho: arquivos',
        );
        for (final a in arquivos.entries) {
          conferir(
            jsonDecode(memoria.ler(a.key)!),
            a.value,
            caminho: '$caminho.${a.key}',
          );
        }
      }
    });
  }
}
