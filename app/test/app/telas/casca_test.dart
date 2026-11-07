import 'dart:async';

import 'package:calculadoradarf/app/estado/estado_app.dart';
import 'package:calculadoradarf/app/servicos/api.dart';
import 'package:calculadoradarf/app/servicos/eventos.dart';
import 'package:calculadoradarf/app/telas/apuracao/tela_apuracao.dart';
import 'package:calculadoradarf/app/telas/caixa/tela_caixa.dart';
import 'package:calculadoradarf/app/telas/casca.dart';
import 'package:calculadoradarf/app/telas/conta/tela_conta.dart';
import 'package:calculadoradarf/integracoes/integracoes.dart';
import 'package:calculadoradarf/app/telas/noticias/tela_noticias.dart';
import 'package:calculadoradarf/app/telas/radar/tela_radar.dart';
import 'package:calculadoradarf/app/tema/tema_visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../apoio/montar.dart';
import '../apoio/servicos_falsos.dart';

const _pequeno = Size(360, 800);

EstadoApp _estado(WidgetTester t) =>
    Provider.of<EstadoApp>(t.element(find.byType(Casca)), listen: false);

Finder _naBarra(String texto) =>
    find.descendant(of: find.byType(NavigationBar), matching: find.text(texto));

Finder _naLateral(String texto) => find.descendant(
  of: find.byType(NavigationRail),
  matching: find.text(texto),
);

/// Tela de teste com estado próprio, para provar que ele sobrevive.
class _Contador extends StatefulWidget {
  const _Contador(this.aba);

  final Aba aba;

  @override
  State<_Contador> createState() => _ContadorState();
}

class _ContadorState extends State<_Contador> {
  int toques = 0;

  @override
  Widget build(BuildContext context) => Center(
    child: TextButton(
      onPressed: () => setState(() => toques++),
      child: Text('${widget.aba.name}: $toques'),
    ),
  );
}

void main() {
  testWidgets('1366 de largura mostra barra lateral e cabeçalho', (t) async {
    await montarApp(t);
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('Calculadora DARF'), findsOneWidget);
    expect(find.text('Ações e BDRs · apuração mensal de IR'), findsOneWidget);
    expect(find.textContaining('Saldo: '), findsOneWidget);
    expect(find.text('○ Google não conectado'), findsOneWidget);
    expect(find.text('Meta de lucro'), findsOneWidget);
    expect(find.text('Amigos'), findsOneWidget);
    expect(find.text('Conectar Google'), findsOneWidget);
    expect(_naLateral('Apuração / DARF'), findsOneWidget);
  });

  testWidgets("o botão 'Meta de lucro' do cabeçalho abre as metas", (t) async {
    await montarApp(t);
    await t.pumpAndSettle();
    await t.tap(find.text('Meta de lucro'));
    await t.pumpAndSettle();
    expect(find.text('Meta de lucro / Preço-alvo'), findsOneWidget);
    expect(find.text('METAS'), findsOneWidget);
  });

  testWidgets('o cartão de metas do celular abre as metas em tela cheia', (
    t,
  ) async {
    await montarApp(t, tamanho: _pequeno);
    await t.pumpAndSettle();
    await t.tap(find.text('Meta de lucro / Preço-alvo'));
    await t.pumpAndSettle();
    expect(find.byType(TabBar), findsOneWidget);
    expect(find.text('Calculadora'), findsOneWidget);
  });

  testWidgets('cabeçalho mostra a conta cortada em 26 e o amigo', (t) async {
    final s = ServicosFalsos();
    await montarApp(t, servicos: s);
    s.eventosFalsos.add(
      const EventoConta(
        EstadoConta(email: 'nome.muito.comprido.demais@gmail.com'),
      ),
    );
    await t.pump();
    expect(find.text('nome.muito.comprido.dema…'), findsOneWidget);
    await _estado(t).trocarVisao('bia@gmail.com');
    await t.pump();
    expect(
      find.text('Dados de bia@gmail.com · somente leitura'),
      findsOneWidget,
    );
  });

  testWidgets('360 de largura mostra barra inferior e AppBar', (t) async {
    await montarApp(t, tamanho: _pequeno);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text('Calculadora DARF'),
      ),
      findsOneWidget,
    );
    for (final r in ['Apuração', 'Caixa', 'Radar', 'Notícias', 'Conta']) {
      expect(_naBarra(r), findsOneWidget);
    }
  });

  testWidgets('a aba Apuração mostra a tela de Apuração, não o espaço', (
    t,
  ) async {
    await montarApp(t);
    await t.pumpAndSettle();
    expect(find.byType(TelaApuracao), findsOneWidget);
    expect(find.text('Apuração (em construção)'), findsNothing);
    expect(find.text('Lucro bruto'), findsOneWidget);
    expect(find.text('Ativos comprados'), findsOneWidget);
  });

  testWidgets('a aba Conta mostra a tela de Conta, não o espaço', (t) async {
    await montarApp(t, tamanho: _pequeno);
    await t.tap(_naBarra('Conta'));
    await t.pumpAndSettle();
    expect(_estado(t).aba, Aba.conta);
    expect(find.byType(TelaConta), findsOneWidget);
    expect(find.text('Conta (em construção)'), findsNothing);
  });

  group('atualização do app', () {
    const info = InfoAtualizacao(
      versao: '9.9.9',
      notas: 'Novo.',
      url: 'https://exemplo.com/a.exe',
      tamanho: 10,
      sha256: '',
    );

    testWidgets('verifica 3 s depois de abrir e oferece uma vez', (t) async {
      final s = ServicosFalsos()..infoAtualizacao = info;
      await montarApp(t, servicos: s);
      await t.pump(const Duration(seconds: 2));
      expect(s.chamadas, isNot(contains('verificarAtualizacao()')));
      await t.pump(const Duration(seconds: 1));
      await t.pumpAndSettle();
      expect(
        s.chamadas.where((c) => c == 'verificarAtualizacao()'),
        hasLength(1),
      );
      expect(find.text('Nova versão disponível'), findsOneWidget);
      await t.tap(find.text('Depois'));
      await t.pumpAndSettle();
      expect(find.text('Nova versão disponível'), findsNothing);
      expect(_estado(t).atualizacao, isNull);
    });

    testWidgets('sem versão nova ou com erro não mostra nada', (t) async {
      final s = ServicosFalsos()..erros['verificarAtualizacao'] = Offline();
      await montarApp(t, servicos: s);
      await t.pump(const Duration(seconds: 4));
      await t.pumpAndSettle();
      expect(s.chamadas, contains('verificarAtualizacao()'));
      expect(find.text('Nova versão disponível'), findsNothing);
      expect(find.textContaining('Não foi possível verificar'), findsNothing);
    });
  });

  testWidgets('tocar nas abas troca a tela', (t) async {
    await montarApp(t, tamanho: _pequeno);
    expect(_estado(t).aba, Aba.apuracao);
    await t.tap(_naBarra('Radar'));
    await t.pumpAndSettle();
    expect(_estado(t).aba, Aba.radar);
    expect(find.byType(TelaRadar), findsOneWidget);
    expect(find.text('Radar (em construção)'), findsNothing);
    await t.tap(_naBarra('Notícias'));
    await t.pumpAndSettle();
    expect(find.byType(TelaNoticias), findsOneWidget);
    expect(find.text('Notícias (em construção)'), findsNothing);
  });

  testWidgets('tocar na barra lateral troca a tela', (t) async {
    await montarApp(t);
    await t.tap(_naLateral('Caixa'));
    await t.pumpAndSettle();
    expect(_estado(t).aba, Aba.caixa);
    expect(find.byType(TelaCaixa), findsOneWidget);
    expect(find.text('Caixa (em construção)'), findsNothing);
  });

  testWidgets('o botão de saldo leva ao Caixa', (t) async {
    await montarApp(t);
    await t.tap(find.textContaining('Saldo: '));
    await t.pumpAndSettle();
    expect(_estado(t).aba, Aba.caixa);
  });

  testWidgets('o ícone de sincronização leva à Conta no celular', (t) async {
    await montarApp(t, tamanho: _pequeno);
    await t.tap(find.byTooltip('○ Google não conectado'));
    await t.pumpAndSettle();
    expect(_estado(t).aba, Aba.conta);
  });

  testWidgets('deslizar troca de aba no celular', (t) async {
    await montarApp(t, tamanho: _pequeno);
    await t.drag(find.byType(PageView), const Offset(-300, 0));
    await t.pumpAndSettle();
    expect(_estado(t).aba, Aba.caixa);
    expect(find.byType(TelaCaixa), findsOneWidget);
    expect(find.text('Caixa (em construção)'), findsNothing);
  });

  testWidgets('no PC deslizar não troca de aba', (t) async {
    await montarApp(t);
    await t.drag(find.byType(PageView), const Offset(-300, 0));
    await t.pumpAndSettle();
    expect(_estado(t).aba, Aba.apuracao);
  });

  testWidgets('selo de não lidas some na aba Notícias', (t) async {
    final s = ServicosFalsos();
    await montarApp(t, servicos: s, tamanho: _pequeno);
    s.eventosFalsos.add(
      EventoNoticias(
        const VisaoNoticias(
          itens: [],
          detalhes: {},
          naoLidas: 4,
          hora: 0,
          lidasAte: 0,
          erros: {},
          rodando: false,
          radar: [],
        ),
        const [],
      ),
    );
    await t.pump();
    expect(
      find.descendant(of: find.byType(NavigationBar), matching: find.text('4')),
      findsOneWidget,
    );
    await t.tap(_naBarra('Notícias'));
    await t.pumpAndSettle();
    expect(
      find.descendant(of: find.byType(NavigationBar), matching: find.text('4')),
      findsNothing,
    );
  });

  testWidgets('aviso de config ilegível na casca', (t) async {
    final s = ServicosFalsos()
      ..estadoInicial = const EstadoInicial(
        mesInicial: '2026-10',
        mesesComDados: ['2026-10'],
        preferencias: Preferencias(),
        erroConfig: 'O arquivo config.json está ilegível; nada foi alterado.',
      );
    await montarApp(t, servicos: s);
    expect(
      find.textContaining('O arquivo config.json está ilegível'),
      findsOneWidget,
    );
    expect(find.textContaining('vazio ou corrompido'), findsOneWidget);
    expect(find.textContaining('nenhuma alteração é gravada'), findsOneWidget);
  });

  testWidgets('aviso vira diálogo no PC', (t) async {
    final s = ServicosFalsos();
    await montarApp(t, servicos: s);
    s.eventosFalsos.add(const EventoAviso('Erro inesperado', 'algo falhou'));
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('algo falhou'), findsOneWidget);
    await t.tap(find.text('OK'));
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(_estado(t).avisos, isEmpty);
  });

  testWidgets('aviso vira SnackBar no celular', (t) async {
    final s = ServicosFalsos();
    await montarApp(t, servicos: s, tamanho: _pequeno);
    s.eventosFalsos.add(const EventoAviso('Erro inesperado', 'algo falhou'));
    await t.pump();
    await t.pump();
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining('algo falhou'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets(
    'redimensionar atravessando 840 mantém a aba e o estado da tela',
    (t) async {
      await montarApp(t, tela: Casca(telaDaAba: _Contador.new));
      await t.tap(_naLateral('Radar'));
      await t.pumpAndSettle();
      await t.tap(find.text('radar: 0'));
      await t.pump();
      expect(find.text('radar: 1'), findsOneWidget);

      t.view.physicalSize = _pequeno;
      await t.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(_estado(t).aba, Aba.radar);
      expect(find.text('radar: 1'), findsOneWidget);

      t.view.physicalSize = const Size(1366, 768);
      await t.pumpAndSettle();
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(_estado(t).aba, Aba.radar);
      expect(find.text('radar: 1'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('morte do isolate mostra a faixa de serviços encerrados', (
    t,
  ) async {
    final s = ServicosFalsos();
    await montarApp(t, servicos: s);
    expect(find.textContaining('foram encerrados'), findsNothing);
    await s.eventosFalsos.close();
    await t.pump();
    await t.pump();
    expect(
      find.text(
        'Os serviços do app foram encerrados. Feche e abra o app de novo.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('mostra o carregamento até o estado inicial chegar', (t) async {
    final s = _Lento();
    await montarApp(t, servicos: s, tema: TemaVisual.terminal);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    s.liberar.complete();
    await t.pump();
    await t.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(NavigationRail), findsOneWidget);
  });

  testWidgets('falha ao iniciar mostra o motivo e Tentar de novo', (t) async {
    final s = ServicosFalsos()..erros['iniciar'] = StateError('quebrou');
    await montarApp(t, servicos: s);
    expect(find.textContaining('quebrou'), findsOneWidget);
    expect(find.textContaining('Exception:'), findsNothing);
    expect(find.byType(NavigationRail), findsNothing);
    s.erros.remove('iniciar');
    await t.tap(find.text('Tentar de novo'));
    await t.pump();
    await t.pump();
    expect(find.byType(NavigationRail), findsOneWidget);
  });
}

/// `iniciar` só termina quando o teste liberar.
class _Lento extends ServicosFalsos {
  final Completer<void> liberar = Completer<void>();

  @override
  Future<EstadoInicial> iniciar() async {
    await liberar.future;
    return super.iniciar();
  }
}
