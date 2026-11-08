// Goldens do formulário de venda por quantidade (modos Automático e Manual),
// no PC e no celular, tema Claro. As janelas são mais altas que as reais para o
// formulário inteiro aparecer na imagem.
@Tags(['golden'])
library;

import 'package:calculadoradarf/app/servicos/api.dart';
import 'package:calculadoradarf/app/telas/formularios/abrir_formulario.dart';
import 'package:calculadoradarf/nucleo/nucleo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../apoio/abrir_formulario.dart';
import '../apoio/dados_exemplo.dart';
import '../apoio/fontes.dart';
import '../apoio/servicos_falsos.dart';

const _tamanhos = {'pc': Size(1366, 1500), 'celular': Size(360, 1250)};

Lote _compra(String id, String data, int qtd, double preco) => Lote(
  id: id,
  ticker: 'BBAS3',
  tipo: 'Ação',
  dataCompra: data,
  qtd: qtd,
  preco: preco,
);

ServicosFalsos _servicos() {
  final a = _compra('B1', '2026-10-02', 100, 30);
  final b = _compra('B2', '2026-10-05', 100, 20);
  final s = ServicosFalsos();
  s.visoes['2026-10'] = visaoExemplo(Mes(mes: '2026-10', lotes: [a, b]));
  s.precoVendaResp = (35.1, 'Cotação atual');
  s.previaResp = PreviaVenda(
    linhas: [
      LinhaPrevia(ItemAlocacao(b, 100), custoUnitarioEfetivo(b), 1489.5),
      LinhaPrevia(ItemAlocacao(a, 50), custoUnitarioEfetivo(a), 247.2),
    ],
    gerencial: 1736.7,
    fiscal: 1650.4,
    qtdDt: 0,
    qtdComum: 150,
    custoMedio: true,
  );
  return s;
}

void main() {
  setUp(() => ambiente = Ambiente.fixo(hoje: hojeExemplo));
  tearDown(() => ambiente = Ambiente.sistema());

  group('form_venda', skip: motivoParaPularGoldens() ?? false, () {
    for (final modo in ['automatico', 'manual']) {
      for (final tamanho in _tamanhos.entries) {
        final nome = 'form_venda_${modo}_claro_${tamanho.key}';
        testWidgets(nome, (t) async {
          debugDisableShadows = false;
          try {
            final s = _servicos();
            await abrirNoTeste<VendaRegistrada>(
              t,
              s,
              (c) => abrirFormVenda(c, s.visoes['2026-10']!, ticker: 'BBAS3'),
              tamanho: tamanho.value,
            );
            await t.enterText(find.byKey(const ValueKey('qtd')), '150');
            await t.pump();
            if (modo == 'manual') {
              await t.tap(find.text('Manual'));
              await t.pump();
            }
            await t.pump(const Duration(milliseconds: 400));
            await t.pumpAndSettle();
            await expectLater(
              find.byType(MaterialApp),
              matchesGoldenFile('arquivos/$nome.png'),
            );
          } finally {
            debugDisableShadows = true;
          }
        });
      }
    }
  });
}
