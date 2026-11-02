import 'package:calculadoradarf/app/estado/estado_app.dart';
import 'package:calculadoradarf/app/regras/textos.dart';
import 'package:calculadoradarf/app/servicos/api.dart';
import 'package:calculadoradarf/app/servicos/eventos.dart';
import 'package:calculadoradarf/app/servicos/servicos_isolate.dart'
    show ErroRemoto, msgServicosEncerrados;
import 'package:calculadoradarf/app/tema/tema_visual.dart';
import 'package:calculadoradarf/integracoes/integracoes.dart';
import 'package:calculadoradarf/nucleo/nucleo.dart';

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../apoio/dados_exemplo.dart';
import '../apoio/plataforma_falsa.dart';
import '../apoio/servicos_falsos.dart';

Future<void> _soltar() => Future<void>.delayed(Duration.zero);

VisaoNoticias _visao(int naoLidas) => VisaoNoticias(
  itens: const [],
  detalhes: const {},
  naoLidas: naoLidas,
  hora: 0,
  lidasAte: 0,
  erros: const {},
  rodando: false,
  radar: const [],
);

Future<(EstadoApp, ServicosFalsos, PlataformaFalsa)> _criar({
  ServicosFalsos? servicos,
  PlataformaFalsa? plataforma,
}) async {
  final s = servicos ?? ServicosFalsos();
  final p = plataforma ?? PlataformaFalsa();
  final e = EstadoApp(s, p);
  addTearDown(e.dispose);
  await e.iniciar();
  return (e, s, p);
}

void main() {
  group('EstadoApp', () {
    test('iniciar aplica o estado inicial e o saldo', () async {
      final s = ServicosFalsos()
        ..estadoInicial = const EstadoInicial(
          mesInicial: '2026-09',
          mesesComDados: ['2026-09'],
          preferencias: Preferencias(tema: TemaVisual.moderno),
          erroConfig: 'O arquivo config.json está ilegível; nada foi alterado.',
        );
      final (e, _, _) = await _criar(servicos: s);
      expect(e.mes, '2026-09');
      expect(e.preferencias.tema, TemaVisual.moderno);
      expect(e.erroConfig, contains('ilegível'));
      expect(e.textoSaldo, 'Saldo: ${brl(caixaExemplo().resumo.disponivel)}');
    });

    test('saldo não definido mostra Definir saldo', () async {
      final s = ServicosFalsos()
        ..visaoCaixa = VisaoCaixa(
          resumo: resumoCaixa(Config(), {}, hoje: hojeExemplo),
          projecao: const [],
          agenda: const [],
          hoje: hojeExemplo,
        );
      final (e, _, _) = await _criar(servicos: s);
      expect(e.textoSaldo, 'Definir saldo');
    });

    test('eventos atualizam conta, naoLidas e versaoDados', () async {
      final (e, s, _) = await _criar();
      expect(e.versaoDados, 0);
      s.eventosFalsos.add(
        const EventoConta(EstadoConta(email: 'ana@gmail.com')),
      );
      s.eventosFalsos.add(EventoNoticias(_visao(3), const []));
      s.eventosFalsos.add(const EventoDadosMudaram());
      await _soltar();
      expect(e.conta.email, 'ana@gmail.com');
      expect(e.naoLidas, 3);
      expect(e.versaoDados, 1);
      expect(s.chamadas.where((c) => c.startsWith('caixa(')).length, 2);
    });

    test('aviso do isolate entra na fila sem o prefixo Exception', () async {
      final (e, s, _) = await _criar();
      s.eventosFalsos.add(const EventoAviso('Erro inesperado', 'Exception: x'));
      await _soltar();
      expect(e.avisos.single.titulo, 'Erro inesperado');
      expect(e.avisos.single.texto, 'x');
    });

    test('config ilegível avisada depois do início vira faixa', () async {
      final (e, s, _) = await _criar();
      s.eventosFalsos.add(const EventoConfigIlegivel('ilegível'));
      await _soltar();
      expect(e.erroConfig, 'ilegível');
    });

    test('trocarTema muda na hora e chama salvarPreferencias', () async {
      final (e, s, _) = await _criar();
      final pronto = e.trocarTema(TemaVisual.terminal);
      expect(e.preferencias.tema, TemaVisual.terminal);
      await pronto;
      expect(s.preferenciasSalvas!.tema, TemaVisual.terminal);
      expect(e.avisos, isEmpty);
    });

    test('falha ao gravar o tema mostra o erro e mantém o tema', () async {
      final s = ServicosFalsos()
        ..erros['salvarPreferencias'] = ErroValidacao(
          'O arquivo config.json está ilegível; nada foi alterado.',
        );
      final (e, _, _) = await _criar(servicos: s);
      await e.trocarTema(TemaVisual.terminal);
      expect(e.preferencias.tema, TemaVisual.terminal);
      expect(e.avisos.single.texto, contains('config.json está ilegível'));
    });

    test(
      'definirNotificar e definirOrdemRadar gravam as preferências',
      () async {
        final (e, s, _) = await _criar();
        await e.definirNotificar(false);
        expect(s.preferenciasSalvas!.notificarNoticias, isFalse);
        await e.definirOrdemRadar('alfabetica');
        expect(s.preferenciasSalvas!.ordemRadar, 'alfabetica');
        expect(s.preferenciasSalvas!.notificarNoticias, isFalse);
      },
    );

    test('trocarVisao carrega o amigo e define o mês dele', () async {
      final s = ServicosFalsos()
        ..resumoAmigo = const ResumoAmigo(
          email: 'bia@gmail.com',
          meses: ['2026-08'],
          mesInicial: '2026-08',
        );
      final (e, _, _) = await _criar(servicos: s);
      final pronto = e.trocarVisao('bia@gmail.com');
      expect(e.carregandoAmigo, isTrue);
      await pronto;
      expect(e.carregandoAmigo, isFalse);
      expect(e.amigo, 'bia@gmail.com');
      expect(e.mes, '2026-08');
    });

    test('trocarVisao com erro avisa Não foi possível carregar', () async {
      final s = ServicosFalsos()..erros['carregarAmigo'] = Offline('x');
      final (e, _, _) = await _criar(servicos: s);
      await e.trocarVisao('bia@gmail.com');
      expect(e.amigo, isNull);
      expect(e.carregandoAmigo, isFalse);
      expect(e.avisos.single.titulo, 'Não foi possível carregar');
      expect(e.avisos.single.texto, 'Sem conexão com a internet.');
    });

    test('pedido de amigo superado não aparece ao usuário', () async {
      final s = ServicosFalsos()
        ..erros['carregarAmigo'] = PedidoSuperado(
          'O carregamento dos dados do amigo foi cancelado.',
        );
      final (e, _, _) = await _criar(servicos: s);
      await e.trocarVisao('bia@gmail.com');
      expect(e.avisos, isEmpty);
      expect(e.carregandoAmigo, isFalse);
    });

    test('trocarVisao(null) volta aos meus dados no mês inicial', () async {
      final (e, s, _) = await _criar();
      await e.trocarVisao('bia@gmail.com');
      e.trocarMes('2026-08');
      await e.trocarVisao(null);
      expect(e.amigo, isNull);
      expect(e.mes, s.mesAberto);
      expect(s.chamadas, contains('esquecerAmigo()'));
    });

    test('prepararOperacao com amigo ativo volta para meus dados', () async {
      final (e, s, _) = await _criar();
      await e.trocarVisao('bia@gmail.com');
      final v = await e.prepararOperacao();
      expect(e.amigo, isNull);
      expect(v.mes, '2026-10');
      expect(v.editavel, isTrue);
      expect(s.chamadas, contains('esquecerAmigo()'));
    });

    test('prepararOperacao com mês fechado vai para o mês inicial', () async {
      final (e, _, _) = await _criar();
      e.trocarMes('2026-09');
      final v = await e.prepararOperacao();
      expect(e.mes, '2026-10');
      expect(v.dados.fechado, isFalse);
    });

    test('iniciarNotificacoes roda uma vez só na vida do app', () async {
      final (e, _, p) = await _criar();
      await e.iniciar();
      expect(p.notificacoesIniciadas, 1);
    });

    test('tocar numa notificação abre o link ou a aba Notícias', () async {
      final (e, _, p) = await _criar();
      p.tocar('https://exemplo.com/n1');
      await _soltar();
      expect(p.urlsAbertas.single.toString(), 'https://exemplo.com/n1');
      p.tocar('');
      expect(e.aba, Aba.noticias);
    });

    test('link que não abre vira aviso', () async {
      final (e, _, p) = await _criar();
      p.respostaAbrirUrl = false;
      p.tocar('https://exemplo.com/n1');
      await _soltar();
      expect(e.avisos.single.texto, 'Não foi possível abrir o navegador.');
    });

    test('notícias novas viram notificações quando ligado', () async {
      final (e, s, p) = await _criar();
      s.eventosFalsos.add(
        EventoNoticias(_visao(1), const [
          ('PETR4 · Dividendos', 'Texto', 'l1'),
        ]),
      );
      await _soltar();
      expect(p.notificacoes.single.titulo, 'PETR4 · Dividendos');
      expect(p.notificacoes.single.link, 'l1');
      await e.definirNotificar(false);
      s.eventosFalsos.add(
        EventoNoticias(_visao(2), const [('Outra', 'Texto', 'l2')]),
      );
      await _soltar();
      expect(p.notificacoes, hasLength(1));
    });

    test('falha de plugin vira aviso e não escapa', () async {
      final p = PlataformaFalsa()
        ..falhaPlugin = PlatformException(code: 'x', message: 'quebrou');
      final (e, s, _) = await _criar(plataforma: p);
      expect(e.avisos, isNotEmpty); // iniciarNotificacoes falhou na partida
      for (final a in e.avisos) {
        expect(a.texto, isNot(contains('Exception:')));
      }
      e.avisos.clear();
      s.eventosFalsos.add(EventoNoticias(_visao(1), const [('T', 'C', 'l')]));
      await _soltar();
      expect(e.avisos, isEmpty); // um aviso por sessão, nada solto
      expect(p.notificacoes, isEmpty);
    });

    test('voltar ao primeiro plano verifica as metas', () async {
      final (e, s, _) = await _criar();
      e.aoMudarCiclo(AppLifecycleState.paused);
      await _soltar();
      expect(s.chamadas.where((c) => c.startsWith('verificarMetas')), isEmpty);
      e.aoMudarCiclo(AppLifecycleState.resumed);
      await _soltar();
      expect(
        s.chamadas.where((c) => c.startsWith('verificarMetas')),
        hasLength(1),
      );
      expect(e.avisos, isEmpty); // a falha da verificação não vira aviso
    });

    test('falha ao iniciar os serviços vira falha de inicialização', () async {
      final s = ServicosFalsos()..erros['iniciar'] = StateError('x');
      final (e, _, p) = await _criar(servicos: s);
      expect(e.falhaInicial, 'Erro inesperado: StateError (Bad state: x)');
      expect(e.falhaInicial, isNot(contains('Exception:')));
      expect(e.carregando, isFalse);
      expect(e.avisos, isEmpty);
      expect(p.notificacoesIniciadas, 0);
      // tentar de novo funciona e roda o resto uma vez
      s.erros.remove('iniciar');
      await e.iniciar();
      expect(e.falhaInicial, isNull);
      expect(e.mes, '2026-10');
      await e.iniciar();
      expect(p.notificacoesIniciadas, 1);
    });

    test('carregando até o estado inicial chegar', () async {
      final s = ServicosFalsos();
      final e = EstadoApp(s, PlataformaFalsa());
      addTearDown(e.dispose);
      expect(e.carregando, isTrue);
      await e.iniciar();
      expect(e.carregando, isFalse);
    });

    test('PedidoSuperado atravessa o isolate com o tipo', () async {
      await expectLater(
        Isolate.run<void>(() => throw PedidoSuperado('x foi cancelado.')),
        throwsA(isA<PedidoSuperado>()),
      );
    });

    test('definirNotificar não pede permissão se a gravação falhou', () async {
      final s = ServicosFalsos()..erros['salvarPreferencias'] = StateError('x');
      final p = PlataformaFalsa(windows: false);
      final (e, _, _) = await _criar(servicos: s, plataforma: p);
      p.pedidosPermissao = 0;
      await e.definirNotificar(true);
      expect(p.pedidosPermissao, 0);
      s.erros.clear();
      await e.definirNotificar(true);
      expect(p.pedidosPermissao, 1);
    });

    test('sair da conta com amigo ativo volta aos meus dados', () async {
      final s = ServicosFalsos()
        ..estadoConta = const EstadoConta(email: 'ana@gmail.com');
      final (e, _, _) = await _criar(servicos: s);
      await e.trocarVisao('bia@gmail.com');
      e.trocarMes('2026-08');
      final antes = e.versaoDados;
      s.estadoConta = const EstadoConta();
      s.eventosFalsos.add(const EventoConta(EstadoConta()));
      await _soltar();
      expect(e.amigo, isNull);
      expect(e.carregandoAmigo, isFalse);
      expect(e.mes, s.mesAberto);
      expect(e.versaoDados, greaterThan(antes));
    });

    test('remover o amigo aberto volta aos meus dados', () async {
      final s = ServicosFalsos()
        ..estadoConta = const EstadoConta(email: 'ana@gmail.com')
        ..listaAmigos = [Amigo(email: 'bia@gmail.com', desde: '2026-10-01')];
      final (e, _, _) = await _criar(servicos: s);
      await e.trocarVisao('bia@gmail.com');
      s.eventosFalsos.add(const EventoDadosMudaram());
      await _soltar();
      expect(e.amigo, 'bia@gmail.com'); // ainda é amigo: continua
      s.listaAmigos = [];
      s.eventosFalsos.add(const EventoDadosMudaram());
      await _soltar();
      expect(e.amigo, isNull);
      expect(e.mes, s.mesAberto);
    });

    test('carregamento em voo não recoloca o amigo depois de sair', () async {
      final s = _AmigoLento()
        ..estadoConta = const EstadoConta(email: 'ana@gmail.com');
      final (e, _, _) = await _criar(servicos: s);
      final pronto = e.trocarVisao('bia@gmail.com');
      expect(e.carregandoAmigo, isTrue);
      e.trocarMes('2026-08');
      s.estadoConta = const EstadoConta();
      s.eventosFalsos.add(const EventoConta(EstadoConta()));
      await _soltar();
      expect(e.carregandoAmigo, isFalse);
      s.resposta.complete(
        const ResumoAmigo(
          email: 'bia@gmail.com',
          meses: ['2026-08'],
          mesInicial: '2026-08',
        ),
      );
      await pronto;
      expect(e.amigo, isNull);
      expect(e.mes, s.mesAberto);
    });

    test('trocarVisao(null) superado não aplica o mês antigo', () async {
      final s = _MesLento()
        ..estadoConta = const EstadoConta(email: 'ana@gmail.com');
      final (e, _, _) = await _criar(servicos: s);
      await e.trocarVisao('bia@gmail.com');
      s.travar = true;
      final volta = e.trocarVisao(null);
      await _soltar();
      s.travar = false;
      await e.trocarVisao('bia@gmail.com'); // pedido novo supera o antigo
      s.mesPendente.completeError(StateError('x'));
      await volta;
      expect(e.avisos, isEmpty);
      expect(e.amigo, 'bia@gmail.com');
    });

    test('remover o amigo durante a carga não recoloca o amigo', () async {
      final s = _AmigoLento()
        ..estadoConta = const EstadoConta(email: 'ana@gmail.com')
        ..listaAmigos = [Amigo(email: 'bia@gmail.com', desde: '2026-10-01')];
      final (e, _, _) = await _criar(servicos: s);
      final pronto = e.trocarVisao('bia@gmail.com');
      e.trocarMes('2026-08');
      s.eventosFalsos.add(const EventoDadosMudaram());
      await _soltar();
      expect(e.carregandoAmigo, isTrue); // ainda é amigo: a carga segue
      s.listaAmigos = [];
      s.eventosFalsos.add(const EventoDadosMudaram());
      await _soltar();
      expect(e.amigo, isNull);
      expect(e.carregandoAmigo, isFalse);
      expect(e.mes, s.mesAberto);
      s.resposta.complete(
        const ResumoAmigo(
          email: 'bia@gmail.com',
          meses: ['2026-08'],
          mesInicial: '2026-08',
        ),
      );
      await pronto;
      expect(e.amigo, isNull);
      expect(e.carregandoAmigo, isFalse);
    });

    test('eventos seguidos conferem a visão uma vez e mais uma', () async {
      final s = _AmigosLentos()
        ..estadoConta = const EstadoConta(email: 'ana@gmail.com')
        ..listaAmigos = [Amigo(email: 'bia@gmail.com', desde: '2026-10-01')];
      final (e, _, _) = await _criar(servicos: s);
      await e.trocarVisao('bia@gmail.com');
      s.chamadas.clear();
      for (var i = 0; i < 5; i++) {
        s.eventosFalsos.add(const EventoDadosMudaram());
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(
        s.chamadas.where((c) => c.startsWith('amigos(')).length,
        lessThan(3),
      );
      expect(e.amigo, 'bia@gmail.com');
    });

    test('remover a carga em voo não limpa o amigo já aberto', () async {
      final s = _DoisAmigos()
        ..estadoConta = const EstadoConta(email: 'ana@gmail.com')
        ..listaAmigos = [
          Amigo(email: 'bia@gmail.com', desde: '2026-10-01'),
          Amigo(email: 'caio@gmail.com', desde: '2026-10-01'),
        ];
      final (e, _, _) = await _criar(servicos: s);
      await e.trocarVisao('bia@gmail.com');
      final pronto = e.trocarVisao('caio@gmail.com');
      expect(e.carregandoAmigo, isTrue);
      s.listaAmigos = [Amigo(email: 'bia@gmail.com', desde: '2026-10-01')];
      s.eventosFalsos.add(const EventoDadosMudaram());
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(e.amigo, 'bia@gmail.com');
      expect(e.carregandoAmigo, isFalse);
      s.cargaCaio.complete(
        const ResumoAmigo(
          email: 'caio@gmail.com',
          meses: ['2026-08'],
          mesInicial: '2026-08',
        ),
      );
      await pronto;
      expect(e.amigo, 'bia@gmail.com');
    });

    test('geração que muda durante a conferência reconfere', () async {
      final s = _DoisAmigos()
        ..demora = const Duration(milliseconds: 20)
        ..estadoConta = const EstadoConta(email: 'ana@gmail.com')
        ..listaAmigos = [
          Amigo(email: 'bia@gmail.com', desde: '2026-10-01'),
          Amigo(email: 'caio@gmail.com', desde: '2026-10-01'),
        ];
      final (e, _, _) = await _criar(servicos: s);
      await e.trocarVisao('bia@gmail.com');
      s.listaAmigos = [Amigo(email: 'caio@gmail.com', desde: '2026-10-01')];
      s.eventosFalsos.add(const EventoDadosMudaram()); // conferência em curso
      await _soltar();
      final pronto = e.trocarVisao('caio@gmail.com'); // muda a geração
      await Future<void>.delayed(const Duration(milliseconds: 100));
      s.cargaCaio.completeError(Offline('x'));
      await pronto;
      expect(e.amigo, isNull);
      expect(e.carregandoAmigo, isFalse);
    });

    test('aplicarInicial evita um segundo servicos.iniciar()', () async {
      final s = ServicosFalsos();
      final p = PlataformaFalsa();
      final e = EstadoApp(s, p);
      addTearDown(e.dispose);
      e.aplicarInicial(
        const EstadoInicial(
          mesInicial: '2026-09',
          mesesComDados: ['2026-09'],
          preferencias: Preferencias(tema: TemaVisual.terminal),
        ),
      );
      expect(e.carregando, isFalse);
      expect(e.preferencias.tema, TemaVisual.terminal);
      await e.iniciar();
      await e.iniciar();
      expect(s.chamadas.where((c) => c == 'iniciar()'), isEmpty);
      expect(p.notificacoesIniciadas, 1);
      expect(e.mes, '2026-09');
    });

    test('morte do isolate mostra serviços encerrados', () async {
      final s = ServicosFalsos();
      final (e, _, _) = await _criar(servicos: s);
      expect(e.servicosEncerrados, isFalse);
      await s.eventosFalsos.close();
      await _soltar();
      expect(e.servicosEncerrados, isTrue);
    });

    test('irPara muda a aba', () async {
      final (e, _, _) = await _criar();
      e.irPara(Aba.radar);
      expect(e.aba, Aba.radar);
    });
  });

  group('textos', () {
    test('textoStatusSync para os 7 estados', () {
      String t(StatusSync s) => textoStatusSync(EstadoConta(status: s));
      expect(t(StatusSync.off), '○ Google não conectado');
      expect(t(StatusSync.login), '◌ Aguardando login no navegador…');
      expect(t(StatusSync.sync), '◌ Sincronizando…');
      expect(t(StatusSync.ok), '● Sincronizado');
      expect(t(StatusSync.pendente), '● Alterações pendentes');
      expect(t(StatusSync.offline), '● Sem conexão · será enviado depois');
      expect(t(StatusSync.erro), '● Erro ao sincronizar');
    });

    test('textoStatusSync sincronizado acrescenta a hora', () {
      final instante = DateTime(2026, 10, 28, 9, 5);
      final epoch = instante.millisecondsSinceEpoch / 1000;
      expect(horaMinuto(epoch), '09:05');
      expect(
        textoStatusSync(EstadoConta(status: StatusSync.ok, ultimaSync: epoch)),
        '● Sincronizado às 09:05',
      );
    });

    test('textoErro nunca começa com Exception', () {
      expect(
        textoErro(ErroValidacao('Informe o ticker.')),
        'Informe o ticker.',
      );
      expect(textoErro(ErroGoogle('Sem permissão.')), 'Sem permissão.');
      expect(textoErro(Offline('x')), 'Sem conexão com a internet.');
      expect(textoErro(ErroConexao('x')), 'Sem conexão com a internet.');
      expect(
        textoErro(LimiteConsultas('x')),
        'Limite de consultas do Yahoo atingido. Tente em alguns minutos.',
      );
      expect(textoErro(StateError('x')), 'Erro inesperado: StateError');
      expect(
        textoErro(PlatformException(code: 'c', message: 'm')),
        isNot(startsWith('Exception')),
      );
      expect(textoErro(const ErroRemoto('Exception: y')), 'y');
    });

    test(
      'textoErro usa a mensagem de PlatformException e ProcessException',
      () {
        expect(
          textoErro(PlatformException(code: 'c', message: 'Sem permissão')),
          'Sem permissão',
        );
        expect(textoErro(PlatformException(code: 'sem_msg')), 'sem_msg');
        expect(
          textoErro(PlatformException(code: 'vazio', message: '')),
          'vazio',
        );
        final t = textoErro(
          ProcessException('instalador.exe', [], 'acesso negado'),
        );
        expect(t, contains('instalador.exe'));
        expect(t, contains('acesso negado'));
        expect(t, isNot(contains('Exception')));
      },
    );

    test('textoFalha mostra só o texto da exceção', () {
      expect(textoFalha(Exception('x')), 'x');
      expect(
        textoFalha(StateError('y')),
        'Erro inesperado: StateError (Bad state: y)',
      );
      expect(textoFalha(ErroValidacao('Informe.')), 'Informe.');
    });

    test('textoErro traduz o StateError de serviços encerrados', () {
      expect(
        textoErro(StateError(msgServicosEncerrados)),
        'Os serviços do app foram encerrados. Feche e abra o app de novo.',
      );
    });
  });
}

class _AmigoLento extends ServicosFalsos {
  final Completer<ResumoAmigo> resposta = Completer<ResumoAmigo>();

  @override
  Future<ResumoAmigo> carregarAmigo(String email) => resposta.future;
}

class _MesLento extends ServicosFalsos {
  bool travar = false;
  final Completer<String> mesPendente = Completer<String>();

  @override
  Future<String> mesInicial({String? amigo}) =>
      travar ? mesPendente.future : super.mesInicial(amigo: amigo);
}

class _AmigosLentos extends ServicosFalsos {
  @override
  Future<List<Amigo>> amigos() async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return super.amigos();
  }
}

class _DoisAmigos extends ServicosFalsos {
  final Completer<ResumoAmigo> cargaCaio = Completer<ResumoAmigo>();
  Duration demora = Duration.zero;

  @override
  Future<ResumoAmigo> carregarAmigo(String email) =>
      email.startsWith('caio') ? cargaCaio.future : super.carregarAmigo(email);

  @override
  Future<List<Amigo>> amigos() async {
    await Future<void>.delayed(demora);
    return super.amigos();
  }
}
