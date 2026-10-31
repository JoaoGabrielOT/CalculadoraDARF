import 'dart:convert';

import 'package:calculadoradarf/nucleo/ambiente.dart';
import 'package:calculadoradarf/nucleo/armazenamento.dart';
import 'package:calculadoradarf/nucleo/datas.dart';
import 'package:calculadoradarf/nucleo/erros.dart';
import 'package:calculadoradarf/nucleo/fechamento.dart';
import 'package:calculadoradarf/nucleo/metas/cadeia.dart';
import 'package:calculadoradarf/nucleo/metas/criacao.dart';
import 'package:calculadoradarf/nucleo/modelos/config.dart';
import 'package:calculadoradarf/nucleo/planilha/montagem.dart';
import 'package:calculadoradarf/nucleo/planilha/reconstrucao.dart';
import 'package:calculadoradarf/nucleo/repositorio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'apoio/referencias.dart';

Map<String, Object?> _mapa(Object? o) => o! as Map<String, Object?>;

/// Números não finitos vêm como texto ("inf", "-inf", "nan").
double _num(Object? v) {
  if (v is String) {
    return switch (v) {
      'inf' => double.infinity,
      '-inf' => double.negativeInfinity,
      'nan' => double.nan,
      _ => throw ArgumentError(v),
    };
  }
  return (v! as num).toDouble();
}

/// qtd pode ser inteira ou fracionária; o texto vira não finito.
num _qtd(Object? v) => v is String ? _num(v) : v! as num;

DataHora? _agora(Map<String, Object?> op) => op['agora_meta'] == null
    ? null
    : DataHora.parse(op['agora_meta']! as String);

/// Executa uma operação do roteiro; devolve o retorno como JSON.
Object? _executar(Repositorio repo, Config cfg, Map<String, Object?> op) {
  try {
    switch (op['op']) {
      case 'criar_meta':
        return criarMeta(
          repo,
          cfg,
          op['lote_id']! as String,
          _qtd(op['qtd']),
          _num(op['preco_alvo']),
          lucroDesejado: op['lucro_desejado'] == null
              ? null
              : _num(op['lucro_desejado']),
          agora: _agora(op),
          ocoCom: op['oco_com'] as String?,
        ).toJson();
      case 'criar_stop':
        return criarStop(
          repo,
          cfg,
          op['lote_id']! as String,
          _qtd(op['qtd']),
          _num(op['preco_stop']),
          movel: (op['movel'] as bool?) ?? false,
          ocoCom: op['oco_com'] as String?,
          precoAtual: op['preco_atual'] == null
              ? null
              : _num(op['preco_atual']),
          agora: _agora(op),
          sugestao: op['sugestao'] == null ? null : _mapa(op['sugestao']),
        ).toJson();
      case 'cancelar':
        cancelarMeta(repo, cfg, op['meta_id']! as String);
        return null;
      case 'reservado':
        return reservado(
          repo,
          cfg,
          op['lote_id']! as String,
          ignorar: {...?(op['ignorar'] as List<Object?>?)?.cast<String>()},
        );
      case 'cadeia':
        return [
          for (final e in cadeia(
            repo.carregarMeses(),
            op['lote_id']! as String,
          ))
            [e.mes, e.lote.id],
        ];
      case 'venda_existente':
        final achado = vendaExistente(
          repo.carregarMeses(),
          op['venda_id']! as String,
        );
        return achado == null ? null : [achado.$1.id, achado.$2.id];
      case 'raizes':
        return raizes(repo.carregarMeses());
      case 'lotes_abertos':
        return [
          for (final e in lotesAbertos(repo.carregarMeses()))
            [e.mes, e.lote.id],
        ];
      case 'posicoes_abertas':
        return [
          for (final p in posicoesAbertas(repo, cfg))
            [
              p.mes,
              p.lote.id,
              p.restante,
              p.livre,
              [for (final m in p.ativas) m.id],
            ],
        ];
      case 'lotes_para_meta':
        return [
          for (final p in lotesParaMeta(repo, cfg)) [p.mes, p.lote.id, p.livre],
        ];
      case 'parceira_oco':
        return parceiraOco(
          repo,
          cfg,
          op['lote_id']! as String,
          op['gatilho']! as String,
        )?.id;
      case 'fechar_mes':
        final (r, prox) = fecharMes(repo, repo.carregar(op['mes']! as String));
        return {'prox': prox, 'darf': r.darf};
      case 'ida_e_volta':
        final linhas = montarLinhas(repo.carregarMeses().values.toList(), cfg);
        return [for (final m in reconstruirMetas(linhas)) m.toJson()];
    }
  } on ErroValidacao catch (e) {
    return {'erro': e.mensagem};
  }
  throw StateError('operação desconhecida: ${op['op']}');
}

void main() {
  tearDown(() => ambiente = Ambiente.sistema());

  test('referências geradas com Python 3.12', () {
    expect(versaoPythonDasReferencias('metas_criacao'), startsWith('3.12'));
  });

  for (final caso in carregarCasos('metas_criacao')) {
    test('roteiro: ${caso.nome}', () {
      final entrada = _mapa(caso.entrada);
      final memoria = ArmazenamentoMemoria();
      for (final e in _mapa(entrada['arquivos']).entries) {
        memoria.gravar(e.key, jsonEncode(e.value));
      }
      final repo = Repositorio(memoria);
      final cfg = repo.lerConfig();
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
          _executar(repo, cfg, op),
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
