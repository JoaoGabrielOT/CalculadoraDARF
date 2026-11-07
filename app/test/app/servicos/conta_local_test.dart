import 'dart:async';

import 'package:calculadoradarf/app/servicos/api.dart';
import 'package:calculadoradarf/app/servicos/eventos.dart';
import 'package:calculadoradarf/app/servicos/locais/conta_local.dart';
import 'package:calculadoradarf/integracoes/integracoes.dart';
import 'package:calculadoradarf/nucleo/nucleo.dart';
import 'package:flutter_test/flutter_test.dart';

import '../apoio/conta_falsa.dart';

class _Cenario {
  _Cenario({String? email = 'ana@gmail.com'})
    : conta = ContaFalsa(email: email),
      repo = Repositorio(ArmazenamentoMemoria()) {
    local = ContaLocal(
      repo: repo,
      conta: conta,
      abrirUrl: (_) async {},
      emitir: eventos.add,
      atrasoAgendamento: const Duration(milliseconds: 20),
    );
  }

  final ContaFalsa conta;
  final Repositorio repo;
  final eventos = <EventoServico>[];
  late final ContaLocal local;

  List<EstadoConta> get estados => [
    for (final e in eventos)
      if (e is EventoConta) e.conta,
  ];

  List<EventoAviso> get avisos => [
    for (final e in eventos)
      if (e is EventoAviso) e,
  ];

  void comPlanilha([String sid = 'sid1']) {
    final c = repo.lerConfig();
    c.planilhas['ana@gmail.com'] = sid;
    repo.gravarConfig(c, carimbar: false);
  }

  /// Planilha da amiga: dois meses, um fechado e um aberto.
  void planilhaDaBia({bool fechadoSep = true, bool fechadoOut = false}) {
    conta.planilhaAmigo = 'sid-bia';
    conta.abasAmigo = montarLinhas([
      Mes(
        mes: '2026-09',
        fechado: fechadoSep,
        lotes: [
          Lote(
            id: 'B1',
            ticker: 'VALE3',
            tipo: 'Ação',
            dataCompra: '2026-09-02',
            qtd: 10,
            preco: 5,
          ),
        ],
      ),
      Mes(
        mes: '2026-10',
        fechado: fechadoOut,
        lotes: [
          Lote(
            id: 'B2',
            ticker: 'PETR4',
            tipo: 'Ação',
            dataCompra: '2026-10-02',
            qtd: 10,
            preco: 5,
          ),
        ],
      ),
    ], Config());
  }
}

Future<void> _espera(Future<Object?> f, String mensagem) => expectLater(
  f,
  throwsA(isA<ErroNucleo>().having((e) => e.mensagem, 'mensagem', mensagem)),
);

Future<void> _pausa([int ms = 80]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  setUp(() => ambiente = Ambiente.fixo(agora: 1761000000.0));
  tearDown(() => ambiente = Ambiente.sistema());

  group('estado e eventos', () {
    test('cada mudança de status emite EventoConta com email, status e '
        'ultimaSync', () async {
      final c = _Cenario()..comPlanilha();
      await c.local.sincronizarAgora();
      expect(c.estados.map((e) => e.status), [StatusSync.sync, StatusSync.ok]);
      final ok = c.estados.last;
      expect(ok.email, 'ana@gmail.com');
      expect(ok.ultimaSync, 1761000000.0);
      expect(ok.temCredencial, isTrue);
      expect(ok.linkPlanilha, 'https://docs.google.com/spreadsheets/d/sid1');
      expect(c.local.estado().status, StatusSync.ok);
    });

    test('sem planilha o estado não tem link', () {
      final c = _Cenario();
      expect(c.local.estado().linkPlanilha, isNull);
      expect(_Cenario(email: null).local.estado().email, isNull);
    });

    test(
      'config ilegível: o estado sai sem link e a lista de amigos recusa',
      () async {
        final c = _Cenario();
        c.repo.armazenamento.gravar('config.json', '{quebrado');
        expect(c.local.estado().email, 'ana@gmail.com');
        expect(c.local.estado().linkPlanilha, isNull);
        await _espera(
          c.local.amigos(),
          'O arquivo config.json está ilegível; nada foi alterado.',
        );
      },
    );

    test('avisoDe: títulos do Windows', () {
      var a = avisoDe('Ajuste manual necessário: PETR4 duplicada');
      expect(
        (a.titulo, a.texto),
        ('Ajuste manual necessário', 'PETR4 duplicada'),
      );
      a = avisoDe('Sessão expirada. Conecte sua conta Google novamente.');
      expect(
        (a.titulo, a.texto),
        ('Sessão expirada', 'Conecte sua conta Google novamente.'),
      );
      a = avisoDe('Conectado como ana@gmail.com.');
      expect(
        (a.titulo, a.texto),
        ('Conectado', 'Conectado como ana@gmail.com.'),
      );
      a = avisoDe('O login foi cancelado.');
      expect(
        (a.titulo, a.texto),
        ('Login não concluído', 'O login foi cancelado.'),
      );
    });

    test('sessão expirada vira EventoAviso e off', () async {
      final c = _Cenario()..comPlanilha();
      c.conta.falhaLer = LoginNecessario('x');
      await c.local.sincronizarAgora();
      expect(c.avisos.single.titulo, 'Sessão expirada');
      expect(c.avisos.single.texto, 'Conecte sua conta Google novamente.');
      expect(c.estados.last.status, StatusSync.off);
    });

    test('mesclagem que mudou dados emite EventoDadosMudaram', () async {
      // a planilha da própria conta traz meses que o disco ainda não tem
      final c = _Cenario()..comPlanilha('sid-bia');
      c.planilhaDaBia();
      await c.local.sincronizarAgora();
      expect(c.eventos.whereType<EventoDadosMudaram>(), isNotEmpty);
      expect(c.repo.listarMeses(), ['2026-09', '2026-10']);
    });

    test('mesclagem sem mudança não emite EventoDadosMudaram', () async {
      final c = _Cenario()..comPlanilha();
      await c.local.sincronizarAgora();
      expect(c.eventos.whereType<EventoDadosMudaram>(), isEmpty);
    });
  });

  group('conectar e cancelar', () {
    test('conectar com sessão ativa não chama login', () async {
      final c = _Cenario();
      await c.local.conectar();
      expect(c.conta.chamadas, isNot(contains('login')));
      expect(c.eventos, isEmpty);
    });

    test('conectar durante outro login não chama login de novo', () async {
      final c = _Cenario(email: null);
      c.conta.achada = 'sid1';
      final segura = Completer<void>();
      c.conta.segurarLogin = segura.future;
      final primeiro = c.local.conectar();
      await _pausa(10);
      expect(c.local.estado().ocupado, isTrue);
      await c.local.conectar();
      expect(c.conta.chamadas.where((x) => x == 'login'), hasLength(1));
      segura.complete();
      await primeiro;
      expect(c.local.estado().ocupado, isFalse);
      expect(c.avisos.first.titulo, 'Conectado');
    });

    test('sem credencial avisa e não chama login', () async {
      final c = _Cenario(email: null);
      c.conta.credencial = false;
      await c.local.conectar();
      expect(c.conta.chamadas, isEmpty);
      expect(c.avisos.single.titulo, 'Credencial não encontrada');
      expect(
        c.avisos.single.texto,
        'Coloque o arquivo credentials.json na mesma pasta do programa '
        'ou gere o .exe com ele na pasta.',
      );
    });

    test('cancelarLogin repassa ao sincronizador e volta a off', () async {
      final c = _Cenario(email: null);
      c.conta.segurarLogin = Completer<void>().future;
      final f = c.local.conectar();
      await _pausa(10);
      expect(c.estados.last.status, StatusSync.login);
      await c.local.cancelarLogin();
      await f;
      expect(c.estados.last.status, StatusSync.off);
      expect(c.estados.last.ocupado, isFalse);
      expect(c.avisos.single.texto, 'O login foi cancelado.');
      expect(c.local.estado().email, isNull);
    });
  });

  group('sair e sincronizar', () {
    test('sair limpa o amigo carregado e emite off', () async {
      final c = _Cenario()..comPlanilha();
      c.planilhaDaBia();
      await c.local.carregarAmigo('bia@gmail.com');
      expect(c.local.amigo, isNotNull);
      c.eventos.clear();
      await c.local.sair();
      expect(c.local.amigo, isNull);
      expect(c.estados.last.status, StatusSync.off);
      expect(c.estados.last.email, isNull);
      expect(c.eventos.whereType<EventoDadosMudaram>(), isNotEmpty);
    });

    test('sincronizarAgora marca pendente e sincroniza', () async {
      final c = _Cenario()..comPlanilha();
      await c.local.sincronizarAgora();
      expect(c.conta.chamadas, ['ler:sid1', 'escrever:sid1']);
      expect(c.repo.lerConfig().pendente, isFalse);
    });

    test(
      'sincronizarAgora marca pendente mesmo se a sincronização falha',
      () async {
        final c = _Cenario()..comPlanilha();
        c.conta.falhaLer = Offline('sem rede');
        await c.local.sincronizarAgora();
        expect(c.repo.lerConfig().pendente, isTrue);
        expect(c.estados.last.status, StatusSync.offline);
      },
    );

    test('sincronizarAgora sem planilha prepara antes', () async {
      final c = _Cenario();
      c.conta.achada = 'sid-achada';
      await c.local.sincronizarAgora();
      expect(c.conta.chamadas, [
        'buscar:me',
        'ler:sid-achada',
        'escrever:sid-achada',
      ]);
      expect(c.repo.lerConfig().planilhas['ana@gmail.com'], 'sid-achada');
    });

    test('config ilegível: sincronizarAgora recusa antes de qualquer chamada '
        'remota', () async {
      final c = _Cenario();
      c.repo.armazenamento.gravar('config.json', '{quebrado');
      await _espera(
        c.local.sincronizarAgora(),
        'O arquivo config.json está ilegível; nada foi alterado.',
      );
      expect(c.conta.chamadas, isEmpty);
      expect(c.repo.armazenamento.ler('config.json'), '{quebrado');
    });
  });

  group('agendar e tick', () {
    test('agendar marca pendente mesmo sem conta conectada', () async {
      final c = _Cenario(email: null);
      c.local.agendar();
      expect(c.repo.lerConfig().pendente, isTrue);
      await _pausa();
      expect(c.conta.chamadas, isEmpty);
      expect(c.estados, isEmpty);
    });

    test(
      'agendar com conta: pendente e uma sincronização depois do atraso',
      () async {
        final c = _Cenario()..comPlanilha();
        c.local.agendar();
        c.local.agendar();
        await _pausa(1);
        expect(c.estados.last.status, StatusSync.pendente);
        await _pausa();
        expect(c.conta.chamadas, ['ler:sid1', 'escrever:sid1']);
        expect(c.estados.last.status, StatusSync.ok);
        expect(c.repo.lerConfig().pendente, isFalse);
      },
    );

    test('tick sincroniza o que está pendente', () async {
      final c = _Cenario()..comPlanilha();
      final cfg = c.repo.lerConfig()..pendente = true;
      c.repo.gravarConfig(cfg, carimbar: false);
      await c.local.tick();
      expect(c.conta.chamadas, ['ler:sid1', 'escrever:sid1']);
    });

    test(
      'tick com token reconecta e o fim da reconexão não deixa ocupado',
      () async {
        final c = _Cenario(email: null);
        c.conta.token = true;
        c.conta.achada = 'sid1';
        await c.local.tick();
        expect(c.estados.last.status, StatusSync.ok);
        expect(c.estados.last.ocupado, isFalse);
      },
    );
  });

  group('amigos', () {
    test('adicionarAmigo sem conta', () async {
      final c = _Cenario(email: null);
      await _espera(
        c.local.adicionarAmigo('bia@gmail.com'),
        'Conecte sua conta Google para adicionar amigos.',
      );
    });

    test('adicionarAmigo sem planilha', () async {
      final c = _Cenario();
      await _espera(
        c.local.adicionarAmigo('bia@gmail.com'),
        'Aguarde a criação da sua planilha no Google Drive e tente novamente.',
      );
      expect(c.conta.chamadas, isEmpty);
    });

    test('adicionarAmigo compartilha e grava com desde = hoje', () async {
      final c = _Cenario()..comPlanilha();
      await c.local.adicionarAmigo('  Bia@Gmail.com ');
      expect(c.conta.chamadas, ['compartilhar:sid1:bia@gmail.com']);
      final a = c.repo.lerConfig().amigos.single;
      expect(a.email, 'bia@gmail.com');
      expect(a.desde, ambiente.hoje());
      expect(a.mod, greaterThan(0));
      expect(c.repo.lerConfig().pendente, isTrue);
      expect((await c.local.amigos()).single.email, 'bia@gmail.com');
    });

    test(
      'adicionar amigo aparece no seletor (emite EventoDadosMudaram)',
      () async {
        final c = _Cenario()..comPlanilha();
        c.eventos.clear();
        await c.local.adicionarAmigo('bia@gmail.com');
        expect(c.eventos.whereType<EventoDadosMudaram>(), hasLength(1));
      },
    );

    test('adicionarAmigo que falha não emite EventoDadosMudaram', () async {
      final c = _Cenario()..comPlanilha();
      c.eventos.clear();
      await _espera(c.local.adicionarAmigo('bia'), 'E-mail inválido.');
      expect(c.eventos.whereType<EventoDadosMudaram>(), isEmpty);
    });

    test('remover amigo some do seletor (emite EventoDadosMudaram)', () async {
      final c = _Cenario()..comPlanilha();
      await c.local.adicionarAmigo('bia@gmail.com');
      c.eventos.clear();
      await c.local.removerAmigo('bia@gmail.com');
      expect(c.eventos.whereType<EventoDadosMudaram>(), hasLength(1));
    });

    test('adicionarAmigo: e-mail inválido, o próprio e repetido', () async {
      final c = _Cenario()..comPlanilha();
      await _espera(c.local.adicionarAmigo('bia'), 'E-mail inválido.');
      await _espera(
        c.local.adicionarAmigo('ana@gmail.com'),
        'Esse é o seu próprio e-mail.',
      );
      await c.local.adicionarAmigo('bia@gmail.com');
      await _espera(
        c.local.adicionarAmigo('bia@gmail.com'),
        'Esse amigo já foi adicionado.',
      );
      expect(c.conta.chamadas, hasLength(1));
    });

    test('adicionarAmigo: falha ao compartilhar não grava nada', () async {
      final c = _Cenario()..comPlanilha();
      c.conta.falhaCompartilhar = Offline('Sem conexão com a internet.');
      await _espera(
        c.local.adicionarAmigo('bia@gmail.com'),
        'Sem conexão com a internet.',
      );
      expect(c.repo.lerConfig().amigos, isEmpty);
    });

    test(
      'config ilegível: adicionarAmigo recusa antes de compartilhar',
      () async {
        final c = _Cenario();
        c.repo.armazenamento.gravar('config.json', '{quebrado');
        await _espera(
          c.local.adicionarAmigo('bia@gmail.com'),
          'O arquivo config.json está ilegível; nada foi alterado.',
        );
        expect(c.conta.chamadas, isEmpty);
      },
    );

    test(
      'removerAmigo: descompartilha e exclui da config com carimbo',
      () async {
        final c = _Cenario()..comPlanilha();
        await c.local.adicionarAmigo('bia@gmail.com');
        c.conta.chamadas.clear();
        await c.local.removerAmigo('bia@gmail.com');
        expect(c.conta.chamadas, ['descompartilhar:sid1:bia@gmail.com']);
        final cfg = c.repo.lerConfig();
        expect(cfg.amigos, isEmpty);
        expect(cfg.excluidos.keys, contains('amigos:bia@gmail.com'));
      },
    );

    test('removerAmigo sem conta/planilha remove só da config', () async {
      final c = _Cenario(email: null);
      final cfg = c.repo.lerConfig()
        ..amigos.add(Amigo(email: 'bia@gmail.com', desde: '2026-10-01'));
      c.repo.gravarConfig(cfg);
      await c.local.removerAmigo('bia@gmail.com');
      expect(c.repo.lerConfig().amigos, isEmpty);
      expect(c.conta.chamadas, isEmpty);

      // conectado, mas ainda sem planilha
      final d = _Cenario();
      final cfg2 = d.repo.lerConfig()
        ..amigos.add(Amigo(email: 'bia@gmail.com', desde: '2026-10-01'));
      d.repo.gravarConfig(cfg2);
      await d.local.removerAmigo('bia@gmail.com');
      expect(d.repo.lerConfig().amigos, isEmpty);
      expect(d.conta.chamadas, isEmpty);
    });

    test(
      'config ilegível: removerAmigo recusa antes de descompartilhar',
      () async {
        final c = _Cenario()..comPlanilha();
        c.repo.armazenamento.gravar('config.json', '{quebrado');
        await _espera(
          c.local.removerAmigo('bia@gmail.com'),
          'O arquivo config.json está ilegível; nada foi alterado.',
        );
        expect(c.conta.chamadas, isEmpty);
      },
    );

    test('carregarAmigo: vale o último pedido', () async {
      final c = _Cenario()..comPlanilha();
      c.planilhaDaBia();
      final segura = Completer<void>();
      var n = 0;
      c.conta.aoLer = () async {
        if (n++ == 0) await segura.future;
      };
      final primeiro = c.local.carregarAmigo('bia@gmail.com');
      final erro = expectLater(primeiro, throwsA(isA<ErroGoogle>()));
      await _pausa(5);
      await c.local.carregarAmigo('caio@gmail.com');
      segura.complete();
      await erro;
      expect(c.local.amigoCarregado!.email, 'caio@gmail.com');
    });

    test('encerrar cancela o agendamento pendente', () async {
      final c = _Cenario()..comPlanilha();
      c.local.agendar();
      await _pausa(1);
      c.local.encerrar();
      await _pausa();
      expect(c.conta.chamadas, isEmpty);
    });

    test('removerAmigo do amigo carregado volta para os meus dados', () async {
      final c = _Cenario()..comPlanilha();
      c.planilhaDaBia();
      await c.local.adicionarAmigo('bia@gmail.com');
      await c.local.carregarAmigo('bia@gmail.com');
      await c.local.removerAmigo('bia@gmail.com');
      expect(c.local.amigo, isNull);
    });

    test('removerAmigo durante a carga derruba o pedido em voo', () async {
      final c = _Cenario()..comPlanilha();
      c.planilhaDaBia();
      await c.local.adicionarAmigo('bia@gmail.com');
      final segura = Completer<void>();
      c.conta.aoLer = () => segura.future;
      final carga = c.local.carregarAmigo('bia@gmail.com');
      final erro = expectLater(carga, throwsA(isA<PedidoSuperado>()));
      await _pausa(5);
      c.eventos.clear();
      await c.local.removerAmigo('bia@gmail.com');
      expect(c.eventos.whereType<EventoDadosMudaram>(), isNotEmpty);
      segura.complete();
      await erro;
      expect(c.local.amigo, isNull);
    });

    test(
      'removerAmigo da carga em voo não limpa o amigo já carregado',
      () async {
        final c = _Cenario()..comPlanilha();
        c.planilhaDaBia();
        await c.local.adicionarAmigo('bia@gmail.com');
        await c.local.adicionarAmigo('caio@gmail.com');
        await c.local.carregarAmigo('bia@gmail.com');
        final segura = Completer<void>();
        c.conta.aoLer = () => segura.future;
        final carga = c.local.carregarAmigo('caio@gmail.com');
        final erro = expectLater(carga, throwsA(isA<PedidoSuperado>()));
        await _pausa(5);
        c.eventos.clear();
        await c.local.removerAmigo('caio@gmail.com');
        expect(c.eventos.whereType<EventoDadosMudaram>(), isNotEmpty);
        segura.complete();
        await erro;
        expect(c.local.amigoCarregado!.email, 'bia@gmail.com');
      },
    );

    test('carregarAmigo devolve meses e primeiro mês aberto', () async {
      final c = _Cenario()..comPlanilha();
      c.planilhaDaBia();
      final r = await c.local.carregarAmigo('bia@gmail.com');
      expect(r.email, 'bia@gmail.com');
      expect(r.meses, ['2026-09', '2026-10']);
      expect(r.mesInicial, '2026-10');
      expect(c.local.amigo!.meses.keys, containsAll(['2026-09', '2026-10']));
      expect(c.local.amigoCarregado!.email, 'bia@gmail.com');
    });

    test('carregarAmigo sem mês aberto usa o maior', () async {
      final c = _Cenario()..comPlanilha();
      c.planilhaDaBia(fechadoOut: true);
      final r = await c.local.carregarAmigo('bia@gmail.com');
      expect(r.mesInicial, '2026-10');
      c.planilhaDaBia(fechadoSep: false, fechadoOut: false);
      expect(
        (await c.local.carregarAmigo('bia@gmail.com')).mesInicial,
        '2026-09',
      );
    });

    test('carregarAmigo sem meses usa o mês de hoje', () async {
      final c = _Cenario()..comPlanilha();
      c.conta.planilhaAmigo = 'sid-bia';
      final r = await c.local.carregarAmigo('bia@gmail.com');
      expect(r.meses, isEmpty);
      expect(r.mesInicial, ambiente.hoje().substring(0, 7));
    });

    test('amigo não compartilhado → mensagem do Python', () async {
      final c = _Cenario()..comPlanilha();
      await _espera(
        c.local.carregarAmigo('bia@gmail.com'),
        'bia@gmail.com ainda não compartilhou a planilha com você. '
        'Peça para ele adicionar ana@gmail.com em Amigos.',
      );
      expect(c.local.amigo, isNull);
    });

    test('erro do lerAmigo é repassado com o texto', () async {
      final c = _Cenario()..comPlanilha();
      c.conta.planilhaAmigo = 'sid-bia';
      c.conta.falhaLer = ErroGoogle('Falha no Google.');
      await _espera(c.local.carregarAmigo('bia@gmail.com'), 'Falha no Google.');
    });

    test('carregarAmigo sem conta', () async {
      final c = _Cenario(email: null);
      await _espera(
        c.local.carregarAmigo('bia@gmail.com'),
        'Conecte sua conta Google para ver os dados dos amigos.',
      );
    });

    test('sair durante o carregamento do amigo descarta o resultado', () async {
      final c = _Cenario()..comPlanilha();
      c.planilhaDaBia();
      final f = c.local.carregarAmigo('bia@gmail.com');
      final erro = expectLater(f, throwsA(isA<ErroGoogle>()));
      await c.local.sair();
      await erro;
      expect(c.local.amigo, isNull);
    });

    test('esquecerAmigo limpa os dados carregados', () async {
      final c = _Cenario()..comPlanilha();
      c.planilhaDaBia();
      await c.local.carregarAmigo('bia@gmail.com');
      await c.local.esquecerAmigo();
      expect(c.local.amigo, isNull);
    });
  });
}
