// Goldens da lista de vendas com uma venda em várias compras expandida, no PC
// e no celular, tema Claro.
@Tags(['golden'])
library;

import 'package:calculadoradarf/app/app.dart';
import 'package:calculadoradarf/app/estado/estado_app.dart';
import 'package:calculadoradarf/app/telas/casca.dart';
import 'package:calculadoradarf/nucleo/nucleo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../apoio/dados_exemplo.dart';
import '../apoio/fontes.dart';
import '../apoio/montar.dart';
import '../apoio/plataforma_falsa.dart';
import '../apoio/servicos_falsos.dart';

const _tamanhos = {'pc': Size(1366, 1500), 'celular': Size(360, 2400)};

Lote _compra(String id, int qtd, double preco, Venda v) => Lote(
  id: id,
  ticker: 'BBAS3',
  tipo: 'Ação',
  dataCompra: '2026-10-02',
  qtd: qtd,
  preco: preco,
  vendas: [v],
);

void main() {
  setUp(() => ambiente = Ambiente.fixo(hoje: hojeExemplo));
  tearDown(() => ambiente = Ambiente.sistema());

  group('vendas_grupo', skip: motivoParaPularGoldens() ?? false, () {
    for (final tamanho in _tamanhos.entries) {
      final nome = 'vendas_grupo_claro_${tamanho.key}';
      testWidgets(nome, (t) async {
        debugDisableShadows = false;
        try {
          final s = ServicosFalsos();
          s.visoes['2026-10'] = visaoExemplo(
            Mes(
              mes: '2026-10',
              lotes: [
                _compra(
                  'B1',
                  100,
                  30,
                  Venda(id: 'G1.1', data: '2026-10-05', qtd: 100, preco: 35.1),
                ),
                _compra(
                  'B2',
                  50,
                  20,
                  Venda(id: 'G1.2', data: '2026-10-05', qtd: 50, preco: 35.1),
                ),
                _compra(
                  'B3',
                  10,
                  31,
                  Venda(id: 'V3', data: '2026-10-06', qtd: 10, preco: 33),
                ),
              ],
            ),
          );
          final celular = tamanho.key == 'celular';
          await montarApp(
            t,
            servicos: s,
            plataforma: PlataformaFalsa(windows: !celular),
            tamanho: tamanho.value,
          );
          await t.pumpAndSettle();
          Provider.of<EstadoApp>(
            t.element(find.byType(Casca)),
            listen: false,
          ).irPara(Aba.apuracao);
          await t.pumpAndSettle();
          final alvo = celular
              ? find.byKey(const Key('expandir-venda-G1'))
              : find.byKey(const Key('linha-G1'));
          for (var i = 0; i < 30 && alvo.evaluate().isEmpty; i++) {
            await t.drag(
              find.byType(celular ? CustomScrollView : ListView).first,
              const Offset(0, -300),
            );
            await t.pumpAndSettle();
          }
          await t.ensureVisible(alvo);
          await t.tap(alvo);
          await t.pump(const Duration(milliseconds: 400));
          await t.pumpAndSettle();
          await expectLater(
            find.byKey(chaveCaptura),
            matchesGoldenFile('arquivos/$nome.png'),
          );
        } finally {
          debugDisableShadows = true;
        }
      });
    }
  });
}
