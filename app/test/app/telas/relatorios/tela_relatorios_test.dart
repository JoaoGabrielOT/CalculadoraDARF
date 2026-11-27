import 'dart:async';

import 'package:calculadoradarf/app/estado/estado_app.dart';
import 'package:calculadoradarf/app/servicos/api.dart';
import 'package:calculadoradarf/app/servicos/eventos.dart';
import 'package:calculadoradarf/app/servicos/locais/relatorios_local.dart';
import 'package:calculadoradarf/app/telas/relatorios/tela_relatorios.dart';
import 'package:calculadoradarf/app/telas/relatorios/vista_relatorio.dart';
import 'package:calculadoradarf/app/tema/tema_visual.dart';
import 'package:calculadoradarf/integracoes/integracoes.dart';
import 'package:calculadoradarf/nucleo/nucleo.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../../nucleo/apoio/fixture_relatorio.dart';
import '../../apoio/montar.dart';
import '../../apoio/plataforma_falsa.dart';
import '../../apoio/servicos_falsos.dart';

const _pc = Size(1366, 768);
const _celular = Size(360, 800);

const _tituloFixture = 'Relatório de Abertura de Mercado — 26/11/2026';
const _textoHoje =
    'O relatório de hoje ainda não está disponível (fica pronto até 9h30 em '
    'dias de pregão)';
const _textoSemConexao =
    'Sem conexão com o Google. Mostrando os relatórios salvos neste aparelho.';
const _textoNovoLogin = 'Para ver os relatórios, entre de novo com o Google';
const _textoSemConta = 'Entre com a sua conta Google para ver os relatórios.';
const _textoVazio =
    'Nenhum relatório encontrado na pasta "Calculadora DARF - Relatórios". '
    'Se o acesso acabou de ser liberado, toque em Atualizar.';

const _termo = Termometro(positiva: 7, mista: 7, neutra: 3, negativa: 5);

String _nome(String data) => 'relatorio-abertura-$data.json';

/// A fixture com outra data e, se pedido, outro título.
Relatorio _rel(String data, {String? titulo}) {
  final j = fixtureRelatorio();
  j['data'] = data;
  if (titulo != null) j['titulo'] = titulo;
  return Relatorio.deJson(j);
}

List<ResumoRelatorio> _itens([
  List<String> datas = const ['2026-11-26', '2026-11-25', '2026-11-24'],
]) => [
  for (final d in datas)
    ResumoRelatorio(nome: _nome(d), data: d, termometro: _termo),
];

VisaoRelatorios _visao({
  String hoje = '2026-11-26',
  bool ehHoje = true,
  List<ResumoRelatorio>? itens,
  Relatorio? atual,
  bool semAtual = false,
  SituacaoRelatorios situacao = SituacaoRelatorios.ok,
}) => VisaoRelatorios(
  itens: itens ?? _itens(),
  hoje: hoje,
  atual: semAtual ? null : atual ?? Relatorio.deJson(fixtureRelatorio()),
  ehHoje: ehHoje,
  situacao: situacao,
);

ServicosFalsos _servicos([VisaoRelatorios? visao]) => ServicosFalsos()
  ..visaoRelatorios = visao ?? _visao()
  ..relatoriosAbertos = {
    _nome('2026-11-25'): _rel('2026-11-25', titulo: 'Relatório do dia 25'),
    _nome('2026-11-24'): _rel('2026-11-24', titulo: 'Relatório do dia 24'),
  };

/// `abrirRelatorio` só responde depois de [antes]: imita a fila do serviço,
/// em que a abertura espera o `atualizar` em curso.
class _ServicosFila extends ServicosFalsos {
  Future<void> antes = Future.value();

  @override
  Future<Relatorio> abrirRelatorio(String nome) async {
    final r = super.abrirRelatorio(nome);
    await antes;
    return r;
  }
}

class _Cena {
  _Cena(this.servicos, this.plataforma);

  final ServicosFalsos servicos;
  final PlataformaFalsa plataforma;
}

Future<_Cena> _montar(
  WidgetTester t, {
  ServicosFalsos? servicos,
  Size tamanho = _pc,
  TemaVisual tema = TemaVisual.claro,
  bool naAba = true,
}) async {
  final cena = _Cena(servicos ?? _servicos(), PlataformaFalsa());
  await montarApp(
    t,
    servicos: cena.servicos,
    plataforma: cena.plataforma,
    tamanho: tamanho,
    tema: tema,
    tela: const TelaRelatorios(),
  );
  await t.pumpAndSettle();
  if (naAba) {
    _estado(t).irPara(Aba.relatorios);
    await t.pumpAndSettle();
  }
  return cena;
}

EstadoApp _estado(WidgetTester t) => Provider.of<EstadoApp>(
  t.element(find.byType(TelaRelatorios)),
  listen: false,
);

int _contar(ServicosFalsos s, String chamada) =>
    s.chamadas.where((c) => c == chamada).length;

Finder _item(String data) => find.byKey(Key('item-relatorio-$data'));

Finder _lista() => find.byKey(const Key('lista-relatorios'));

Future<void> _conta(WidgetTester t, ServicosFalsos s, String? email) async {
  s.eventosFalsos.add(EventoConta(EstadoConta(email: email)));
  await t.pumpAndSettle();
}

void main() {
  group('layouts e temas', () {
    for (final tema in [
      TemaVisual.terminal,
      TemaVisual.claro,
      TemaVisual.moderno,
    ]) {
      testWidgets('${tema.name} no PC: lista ao lado da vista', (t) async {
        await _montar(t, tema: tema);
        expect(t.takeException(), isNull);
        expect(find.text('Relatórios anteriores'), findsOneWidget);
        expect(_lista(), findsOneWidget);
        expect(
          t.getTopLeft(_lista()).dx,
          greaterThan(t.getTopRight(find.byKey(const Key('secao-a'))).dx),
        );
        expect(t.getSize(_lista()).width, 320);
        expect(find.text('Anteriores'), findsNothing);
      });

      testWidgets('${tema.name} no celular: botão Anteriores', (t) async {
        await _montar(t, tema: tema, tamanho: _celular);
        expect(t.takeException(), isNull);
        expect(find.byKey(const Key('secao-a')), findsOneWidget);
        expect(find.text('Anteriores'), findsOneWidget);
        expect(_lista(), findsNothing);
        expect(find.text('Relatórios anteriores'), findsNothing);
      });
    }
  });

  testWidgets('abrir a aba lê o cache e a pasta e mostra o de hoje', (t) async {
    final cena = await _montar(t);
    expect(cena.servicos.chamadas, contains('relatorios()'));
    expect(cena.servicos.chamadas, contains('atualizarRelatorios()'));
    expect(find.text(_tituloFixture), findsOneWidget);
    expect(find.text(_textoHoje), findsNothing);
  });

  testWidgets('fora da aba lê só o cache', (t) async {
    final cena = await _montar(t, naAba: false);
    expect(cena.servicos.chamadas, contains('relatorios()'));
    expect(_contar(cena.servicos, 'atualizarRelatorios()'), 0);
    expect(find.text(_tituloFixture), findsOneWidget);
  });

  testWidgets('sem o de hoje: mensagem e data do mais recente', (t) async {
    await _montar(
      t,
      servicos: _servicos(_visao(hoje: '2026-11-27', ehHoje: false)),
    );
    expect(find.text(_textoHoje), findsOneWidget);
    final mostrando = find.text(
      'Mostrando o relatório de Quinta-feira, 26 de novembro de 2026',
    );
    expect(mostrando, findsOneWidget);
    expect(t.widget<Text>(mostrando).style?.fontWeight, FontWeight.bold);
    expect(
      t.getTopLeft(mostrando).dy,
      greaterThan(t.getTopLeft(find.text(_textoHoje)).dy),
    );
    expect(find.text(_tituloFixture), findsOneWidget);
  });

  testWidgets('lista do mais recente para o mais antigo com o termômetro', (
    t,
  ) async {
    await _montar(t);
    final ys = [
      for (final d in ['2026-11-26', '2026-11-25', '2026-11-24'])
        t.getTopLeft(_item(d)).dy,
    ];
    expect(ys, orderedEquals([...ys]..sort()));
    expect(
      find.descendant(
        of: _item('2026-11-26'),
        matching: find.text('Quinta-feira, 26 de novembro de 2026'),
      ),
      findsOneWidget,
    );
    for (final s in ['7 positivas', '7 mistas', '3 neutras', '5 negativas']) {
      expect(
        find.descendant(of: _lista(), matching: find.text(s)),
        findsNWidgets(3),
      );
    }
  });

  testWidgets('tocar num item abre o relatório', (t) async {
    final cena = await _montar(t);
    await t.tap(_item('2026-11-25'));
    await t.pumpAndSettle();
    expect(
      cena.servicos.chamadas,
      contains('abrirRelatorio(relatorio-abertura-2026-11-25.json)'),
    );
    expect(find.text('Relatório do dia 25'), findsOneWidget);
    expect(find.text(_tituloFixture), findsNothing);
    final aberto = t.widget<ListTile>(
      find.descendant(of: _item('2026-11-25'), matching: find.byType(ListTile)),
    );
    expect(aberto.selected, isTrue);
  });

  testWidgets('Atualizar lista a pasta de novo', (t) async {
    final cena = await _montar(t);
    final antes = _contar(cena.servicos, 'atualizarRelatorios()');
    await t.tap(find.byKey(const Key('relatorios-atualizar')));
    await t.pumpAndSettle();
    expect(_contar(cena.servicos, 'atualizarRelatorios()'), antes + 1);
    expect(find.text('Atualizar'), findsOneWidget);
  });

  testWidgets('sair e voltar à aba atualiza de novo', (t) async {
    final cena = await _montar(t);
    final antes = _contar(cena.servicos, 'atualizarRelatorios()');
    _estado(t).irPara(Aba.caixa);
    await t.pumpAndSettle();
    expect(_contar(cena.servicos, 'atualizarRelatorios()'), antes);
    _estado(t).irPara(Aba.relatorios);
    await t.pumpAndSettle();
    expect(_contar(cena.servicos, 'atualizarRelatorios()'), antes + 1);
  });

  group('o relatório aberto', () {
    testWidgets('continua aberto depois de Atualizar e de voltar à aba', (
      t,
    ) async {
      await _montar(t);
      await t.tap(_item('2026-11-25'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('relatorios-atualizar')));
      await t.pumpAndSettle();
      expect(find.text('Relatório do dia 25'), findsOneWidget);
      _estado(t).irPara(Aba.caixa);
      await t.pumpAndSettle();
      _estado(t).irPara(Aba.relatorios);
      await t.pumpAndSettle();
      expect(find.text('Relatório do dia 25'), findsOneWidget);
    });

    testWidgets('volta ao atual quando o nome some da lista', (t) async {
      final cena = await _montar(t);
      await t.tap(_item('2026-11-25'));
      await t.pumpAndSettle();
      cena.servicos.visaoRelatorios = _visao(
        itens: _itens(['2026-11-26', '2026-11-24']),
      );
      await t.tap(find.byKey(const Key('relatorios-atualizar')));
      await t.pumpAndSettle();
      expect(find.text('Relatório do dia 25'), findsNothing);
      expect(find.text(_tituloFixture), findsOneWidget);
    });

    testWidgets('volta ao atual quando a conta muda', (t) async {
      final cena = await _montar(t);
      await _conta(t, cena.servicos, 'ana@gmail.com');
      await t.tap(_item('2026-11-25'));
      await t.pumpAndSettle();
      expect(find.text('Relatório do dia 25'), findsOneWidget);
      final antes = _contar(cena.servicos, 'atualizarRelatorios()');
      await _conta(t, cena.servicos, 'bia@gmail.com');
      expect(_contar(cena.servicos, 'atualizarRelatorios()'), antes + 1);
      expect(find.text('Relatório do dia 25'), findsNothing);
      expect(find.text(_tituloFixture), findsOneWidget);
    });

    testWidgets('sem o conteúdo do escolhido em cache, abre pela pasta', (
      t,
    ) async {
      final s = _servicos(_visao(semAtual: true));
      s.relatoriosAbertos[_nome('2026-11-26')] = _rel(
        '2026-11-26',
        titulo: 'Baixado agora',
      );
      await _montar(t, servicos: s);
      expect(
        s.chamadas,
        contains('abrirRelatorio(relatorio-abertura-2026-11-26.json)'),
      );
      expect(find.text('Baixado agora'), findsOneWidget);
    });
  });

  testWidgets('resposta atrasada de um pedido antigo é descartada', (t) async {
    final s = _servicos();
    final pedidos = <Completer<VisaoRelatorios>>[];
    s.atualizarRelatoriosFn = () {
      final c = Completer<VisaoRelatorios>();
      pedidos.add(c);
      return c.future;
    };
    await _montar(t, servicos: s);
    await _conta(t, s, 'ana@gmail.com');
    expect(pedidos, hasLength(2));
    pedidos[1].complete(_visao(atual: _rel('2026-11-26', titulo: 'Novo')));
    await t.pumpAndSettle();
    pedidos[0].complete(_visao(atual: _rel('2026-11-26', titulo: 'Velho')));
    await t.pumpAndSettle();
    expect(find.text('Novo'), findsOneWidget);
    expect(find.text('Velho'), findsNothing);
  });

  group('novo login', () {
    testWidgets('texto, botão e nada de relatório', (t) async {
      final s = _servicos(
        _visao(
          itens: const [],
          semAtual: true,
          situacao: SituacaoRelatorios.novoLogin,
        ),
      );
      s.estadoConta = const EstadoConta(email: 'ana@gmail.com');
      await _montar(t, servicos: s);
      expect(find.text(_textoNovoLogin), findsOneWidget);
      expect(
        find.text('A sincronização continua funcionando normalmente.'),
        findsOneWidget,
      );
      expect(find.byType(VistaRelatorio), findsNothing);
      await t.tap(find.text('Entrar de novo com o Google'));
      await t.pumpAndSettle();
      expect(s.chamadas, contains('entrarDeNovoGoogle()'));
    });

    testWidgets('sem e-mail conhecido, sem o botão', (t) async {
      await _montar(
        t,
        servicos: _servicos(
          _visao(
            itens: const [],
            semAtual: true,
            situacao: SituacaoRelatorios.novoLogin,
          ),
        ),
      );
      expect(find.text(_textoNovoLogin), findsOneWidget);
      expect(find.text('Entrar de novo com o Google'), findsNothing);
    });
  });

  testWidgets('sem conta: botão Entrar com o Google', (t) async {
    final s = _servicos(
      _visao(
        itens: const [],
        semAtual: true,
        situacao: SituacaoRelatorios.semConta,
      ),
    );
    await _montar(t, servicos: s);
    expect(find.text(_textoSemConta), findsOneWidget);
    expect(find.byType(VistaRelatorio), findsNothing);
    await t.tap(find.text('Entrar com o Google'));
    await t.pumpAndSettle();
    expect(s.chamadas, contains('conectar()'));
  });

  testWidgets('sem conexão: aviso discreto e o cache', (t) async {
    await _montar(
      t,
      servicos: _servicos(_visao(situacao: SituacaoRelatorios.semConexao)),
    );
    expect(find.text(_textoSemConexao), findsOneWidget);
    expect(find.text(_tituloFixture), findsOneWidget);
    expect(_item('2026-11-25'), findsOneWidget);
  });

  testWidgets('pasta vazia: mensagem', (t) async {
    await _montar(
      t,
      servicos: _servicos(
        _visao(itens: const [], semAtual: true, ehHoje: false),
      ),
    );
    expect(find.text(_textoVazio), findsOneWidget);
    expect(find.text(_textoHoje), findsNothing);
    expect(find.byType(VistaRelatorio), findsNothing);
  });

  group('falha ao abrir', () {
    testWidgets('mostra o erro e mantém o anterior', (t) async {
      final s = _servicos()..erros['abrirRelatorio'] = Offline('x');
      await _montar(t, servicos: s);
      await t.tap(_item('2026-11-25'));
      await t.pumpAndSettle();
      expect(find.text('Sem conexão com a internet.'), findsOneWidget);
      expect(find.text(_tituloFixture), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('arquivo inválido: o texto do relatório inválido', (t) async {
      final s = _servicos()
        ..erros['abrirRelatorio'] = ErroValidacao(textoRelatorioInvalido);
      await _montar(t, servicos: s);
      await t.tap(_item('2026-11-24'));
      await t.pumpAndSettle();
      expect(find.text(textoRelatorioInvalido), findsOneWidget);
      expect(find.text(_tituloFixture), findsOneWidget);
    });
  });

  testWidgets('um link do relatório abre no navegador', (t) async {
    final cena = await _montar(t);
    final fonte = find.descendant(
      of: find.byKey(const Key('secao-k')),
      matching: find.text('InfoMoney'),
    );
    await t.scrollUntilVisible(
      fonte,
      600,
      scrollable: find
          .descendant(
            of: find.byType(VistaRelatorio),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await t.pumpAndSettle();
    await t.tap(fonte);
    await t.pumpAndSettle();
    expect(cena.plataforma.urlsAbertas, hasLength(1));
    expect(cena.plataforma.urlsAbertas.single.host, 'www.infomoney.com.br');
  });

  testWidgets('data inválida na lista não trava', (t) async {
    await _montar(
      t,
      servicos: _servicos(
        _visao(
          ehHoje: false,
          itens: const [ResumoRelatorio(nome: 'x.json', data: 'xx')],
        ),
      ),
    );
    expect(t.takeException(), isNull);
    expect(find.descendant(of: _lista(), matching: find.text('xx')), findsOne);
    expect(find.text('Mostrando o relatório de xx'), findsOneWidget);
  });

  testWidgets('no celular, Anteriores abre a folha com os itens', (t) async {
    final cena = await _montar(t, tamanho: _celular);
    await t.tap(find.text('Anteriores'));
    await t.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('Relatórios anteriores'), findsOneWidget);
    expect(_item('2026-11-24'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.tap(_item('2026-11-25'));
    await t.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(
      cena.servicos.chamadas,
      contains('abrirRelatorio(relatorio-abertura-2026-11-25.json)'),
    );
    expect(find.text('Relatório do dia 25'), findsOneWidget);
  });

  testWidgets('toque na lista durante a atualização não se perde', (t) async {
    final s = _ServicosFila()
      ..visaoRelatorios = _visao()
      ..relatoriosAbertos = {
        _nome('2026-11-25'): _rel('2026-11-25', titulo: 'Relatório do dia 25'),
      };
    await _montar(t, servicos: s);
    final pasta = Completer<VisaoRelatorios>();
    s.atualizarRelatoriosFn = () => pasta.future;
    s.antes = pasta.future;
    await t.tap(find.byKey(const Key('relatorios-atualizar')));
    await t.pump();
    await t.tap(_item('2026-11-25'));
    await t.pump();
    pasta.complete(_visao());
    await t.pumpAndSettle();
    expect(find.text('Relatório do dia 25'), findsOneWidget);
    final item = t.widget<ListTile>(
      find.descendant(of: _item('2026-11-25'), matching: find.byType(ListTile)),
    );
    expect(item.selected, isTrue);
  });

  testWidgets('sem conexão e sem itens: só a faixa de sem conexão', (t) async {
    await _montar(
      t,
      servicos: _servicos(
        _visao(
          itens: const [],
          semAtual: true,
          ehHoje: false,
          situacao: SituacaoRelatorios.semConexao,
        ),
      ),
    );
    expect(
      find.text(
        'Sem conexão. Os relatórios aparecem aqui quando houver internet.',
      ),
      findsOneWidget,
    );
    expect(find.text(_textoVazio), findsNothing);
    expect(find.text(_textoSemConexao), findsNothing);
  });

  testWidgets('Entrar com o Google superado não avisa', (t) async {
    final s = _servicos(
      _visao(
        itens: const [],
        semAtual: true,
        situacao: SituacaoRelatorios.semConta,
      ),
    )..erros['conectar'] = PedidoSuperado('saiu');
    await _montar(t, servicos: s);
    await t.tap(find.text('Entrar com o Google'));
    await t.pumpAndSettle();
    expect(s.chamadas, contains('conectar()'));
    expect(_estado(t).avisos, isEmpty);
  });

  for (final situacao in [
    SituacaoRelatorios.novoLogin,
    SituacaoRelatorios.semConta,
  ]) {
    testWidgets('${situacao.name}: a falha ao atualizar aparece', (t) async {
      final s = _servicos(
        _visao(itens: const [], semAtual: true, situacao: situacao),
      );
      await _montar(t, servicos: s);
      s.erros['atualizarRelatorios'] = ErroValidacao('Falhou a leitura.');
      _estado(t).irPara(Aba.caixa);
      await t.pumpAndSettle();
      _estado(t).irPara(Aba.relatorios);
      await t.pumpAndSettle();
      expect(find.text('Falhou a leitura.'), findsOneWidget);
    });
  }

  group('listas preguiçosas', () {
    final muitas = [
      for (var d = 1; d <= 28; d++) '2026-10-${d.toString().padLeft(2, '0')}',
    ].reversed.toList();

    bool preguicosa(WidgetTester t, Finder lista) {
      final v = t.widget<ListView>(lista);
      return v.childrenDelegate is SliverChildBuilderDelegate && !v.shrinkWrap;
    }

    testWidgets('no PC, a coluna constrói só o que está à vista', (t) async {
      await _montar(
        t,
        servicos: _servicos(_visao(ehHoje: false, itens: _itens(muitas))),
      );
      final lista = find.descendant(
        of: _lista(),
        matching: find.byType(ListView),
      );
      expect(preguicosa(t, lista), isTrue);
      expect(_item(muitas.last), findsNothing);
    });

    testWidgets('no celular, a folha rola até o último', (t) async {
      await _montar(
        t,
        tamanho: _celular,
        servicos: _servicos(_visao(ehHoje: false, itens: _itens(muitas))),
      );
      await t.tap(find.text('Anteriores'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      final lista = find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(ListView),
      );
      expect(preguicosa(t, lista), isTrue);
      expect(_item(muitas.last), findsNothing);
      await t.scrollUntilVisible(
        _item(muitas.last),
        300,
        scrollable: find.descendant(
          of: lista,
          matching: find.byType(Scrollable),
        ),
      );
      expect(_item(muitas.last), findsOneWidget);
    });
  });

  testWidgets('no PC, o título da lista numa linha e Atualizar abaixo', (
    t,
  ) async {
    await _montar(t);
    final titulo = find.text('Relatórios anteriores');
    final linha = t.renderObject<RenderParagraph>(titulo);
    expect(linha.didExceedMaxLines, isFalse);
    expect(
      linha.getMaxIntrinsicWidth(double.infinity),
      lessThanOrEqualTo(linha.size.width + .01),
    );
    expect(t.getSize(titulo).height, lessThan(30));
    expect(
      t.getTopLeft(find.byKey(const Key('relatorios-atualizar'))).dy,
      greaterThanOrEqualTo(t.getBottomLeft(titulo).dy),
    );
  });
}
