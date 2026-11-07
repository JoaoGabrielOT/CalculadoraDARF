// O app inteiro no Windows: isolate de serviços real, disco numa pasta
// temporária e rede trocada por um cliente que responde 503.

import 'dart:io';

import 'package:calculadoradarf/app/app.dart';
import 'package:calculadoradarf/app/servicos/api.dart';
import 'package:calculadoradarf/app/servicos/parametros.dart';
import 'package:calculadoradarf/app/servicos/servicos_isolate.dart';
import 'package:calculadoradarf/nucleo/nucleo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/app/apoio/plataforma_falsa.dart';
import 'apoio.dart';

/// Bombeia quadros até [f] aparecer (a rede falsa e o isolate andam no
/// relógio de verdade, e há animações sem fim durante as cargas).
Future<void> ate(
  WidgetTester t,
  Finder f, {
  Duration limite = const Duration(seconds: 30),
}) async {
  final fim = DateTime.now().add(limite);
  while (f.evaluate().isEmpty) {
    if (DateTime.now().isAfter(fim)) {
      fail('não apareceu em ${limite.inSeconds} s: $f');
    }
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// Uma passada de quadros para a tela assentar sem `pumpAndSettle`.
Future<void> assentar(WidgetTester t) async {
  for (var i = 0; i < 10; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Finder _naLateral(String texto) => find.descendant(
  of: find.byType(NavigationRail),
  matching: find.text(texto),
);

/// Aba -> rótulo na barra lateral e um texto próprio da tela.
const _abas = {
  'apuracao': ('Apuração / DARF', 'Ativos comprados'),
  'caixa': ('Caixa', '+  Aporte'),
  'radar': ('Radar', '+  Adicionar'),
  'noticias': ('Notícias', 'Notificar notícias relevantes'),
  'conta': ('Conta', 'Verificar atualização'),
};

const _radar = [
  'PETR4', 'VALE3', 'ITUB4', 'BBDC4', 'BBAS3', 'WEGE3', 'ABEV3', 'MGLU3', //
  'RENT3', 'SUZB3', 'GGBR4', 'CSNA3', 'PRIO3', 'RADL3', 'EQTL3', 'LREN3',
];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('abre o app no Windows e navega pelas abas', (t) async {
    t.view.physicalSize = const Size(1366, 768);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);

    final pasta = Directory.systemTemp.createTempSync('darf_integracao');
    final dados = Directory('${pasta.path}/dados')..createSync();
    final hoje = ambiente.hoje();
    final mes = hoje.substring(0, 7);
    final repo = Repositorio(ArmazenamentoArquivos(dados.path));
    repo.salvar(
      Mes(
        mes: mes,
        lotes: [
          Lote(
            id: 'L1',
            ticker: 'PETR4',
            tipo: 'Ação',
            dataCompra: '$mes-01',
            qtd: 100,
            preco: 32.5,
          ),
        ],
      ),
    );
    repo.gravarConfig(
      Config(
        radar: [
          for (final (i, ticker) in _radar.indexed)
            ItemRadar(ticker: ticker, desde: hoje, pos: i),
        ],
      ),
    );

    ServicosApp? servicos;
    addTearDown(() async {
      await servicos?.encerrar();
      try {
        pasta.deleteSync(recursive: true);
      } on FileSystemException {
        // o Windows pode segurar um arquivo por um instante; fica no temp
      }
    });

    await iniciarApp(
      plataforma: PlataformaFalsa(),
      criarServicos: (plat) async => servicos = await ServicosIsolate.criar(
        ParametrosServicos(
          pastaDados: dados.path,
          pastaTemporaria: pasta.path,
          windows: true,
          criarCliente: criarClienteSemRede,
          timers: true,
        ),
        abrirUrl: plat.abrirUrl,
      ),
    );

    await ate(t, find.text('Calculadora DARF'));
    // a compra gravada no disco chegou pela ponte do isolate
    await ate(t, find.text('PETR4'));

    for (final (rotulo, texto) in _abas.values) {
      await t.tap(_naLateral(rotulo));
      await ate(t, find.text(texto));
    }

    // cada aba em cada tema
    for (final tema in ['terminal', 'claro', 'moderno']) {
      await t.tap(_naLateral('Conta'));
      await ate(t, find.byKey(Key('tema-$tema')));
      await t.tap(find.byKey(Key('tema-$tema')));
      await assentar(t);
      for (final MapEntry(key: aba, value: (rotulo, texto)) in _abas.entries) {
        await t.tap(_naLateral(rotulo));
        await ate(t, find.text(texto));
        await assentar(t);
        await capturar(t, '${aba}_$tema');
      }
    }

    // compra nova: interface -> isolate -> disco -> interface
    await t.tap(_naLateral('Apuração / DARF'));
    await ate(t, find.text('+  Novo ativo'));
    await t.tap(find.text('+  Novo ativo'));
    await ate(t, find.byKey(const ValueKey('ticker')));
    await t.enterText(find.byKey(const ValueKey('ticker')), 'wege3');
    await t.enterText(find.byKey(const ValueKey('qtd')), '10');
    await t.enterText(find.byKey(const ValueKey('preco')), '40,00');
    await t.pump();
    await t.tap(find.text('Salvar'));
    await ate(t, find.text('Ainda não'));
    await t.tap(find.text('Ainda não'));
    await assentar(t);
    expect(find.text('Ainda não'), findsNothing);
    expect(find.text('WEGE3'), findsOneWidget);
    expect(repo.carregar(mes).lotes.map((l) => l.ticker), contains('WEGE3'));

    // radar rolando enquanto as cotações falham: a mensagem fica na linha
    await t.tap(_naLateral('Radar'));
    await ate(t, find.text('+  Adicionar'));
    await t.scrollUntilVisible(
      find.text('LREN3'),
      200,
      scrollable: find.descendant(
        of: find.byKey(const Key('lista-radar')),
        matching: find.byType(Scrollable),
      ),
    );
    final linha = find.ancestor(
      of: find.text('LREN3'),
      matching: find.byType(Row),
    );
    await ate(
      t,
      find.descendant(
        of: linha.first,
        matching: find.textContaining('Erro ao consultar o histórico: 503'),
      ),
      limite: const Duration(minutes: 1),
    );
    await capturar(t, 'radar_rolado_503');

    // abaixo de 840 px vira barra inferior; de volta, barra lateral
    t.view.physicalSize = const Size(600, 768);
    await assentar(t);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    t.view.physicalSize = const Size(1366, 768);
    await assentar(t);
    expect(find.byType(NavigationRail), findsOneWidget);
  });
}
