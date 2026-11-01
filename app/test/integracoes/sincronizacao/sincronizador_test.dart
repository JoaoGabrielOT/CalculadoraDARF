import 'package:calculadoradarf/integracoes/integracoes.dart';
import 'package:calculadoradarf/nucleo/nucleo.dart';
import 'package:flutter_test/flutter_test.dart';

class ContaGoogleFalsa implements ContaGoogle {
  ContaGoogleFalsa({this.email = 'ana@gmail.com', this.token = false});

  @override
  String? email;
  bool token;
  bool credencial = true;
  final chamadas = <String>[];
  final escritas = <Map<String, List<Linha>>>[];
  int leituras = 0;

  Object? falhaCarregar;
  Object? falhaLogin;
  Object? falhaLer;
  Object? falhaEscrever;
  Future<void> Function()? aoEscrever;
  bool existe = true;
  String? achada;
  String criada = 'sid-criada';
  String? planilhaAmigo;

  @override
  bool get temCredencial => credencial;

  @override
  bool temToken() => token;

  @override
  Future<String> carregarToken() async {
    chamadas.add('carregarToken');
    if (falhaCarregar != null) throw falhaCarregar!;
    return email = 'ana@gmail.com';
  }

  @override
  Future<String> login(AbrirUrl abrirUrl) async {
    chamadas.add('login');
    if (falhaLogin != null) throw falhaLogin!;
    return email = 'ana@gmail.com';
  }

  @override
  void sair() {
    chamadas.add('sair');
    email = null;
  }

  @override
  Future<String?> buscarPlanilha([String dono = 'me']) async {
    chamadas.add('buscar:$dono');
    return dono == 'me' ? achada : planilhaAmigo;
  }

  @override
  Future<bool> planilhaExiste(String sid) async {
    chamadas.add('existe:$sid');
    return existe;
  }

  @override
  Future<String> criarPlanilha() async {
    chamadas.add('criar');
    return criada;
  }

  @override
  Future<Map<String, List<Linha>>> ler(String sid) async {
    chamadas.add('ler:$sid');
    leituras++;
    if (falhaLer != null) throw falhaLer!;
    return normalizarLeitura({});
  }

  @override
  Future<void> escrever(String sid, Map<String, List<Linha>> dados) async {
    chamadas.add('escrever:$sid');
    if (falhaEscrever != null) throw falhaEscrever!;
    escritas.add(dados);
    await aoEscrever?.call();
  }

  @override
  Future<void> compartilhar(String sid, String email) async {}

  @override
  Future<void> descompartilhar(String sid, String email) async {}
}

class DadosComAvisos extends DadosSincronizacaoLocal {
  DadosComAvisos(super.repo, this.avisos, this.mudou);

  final List<String> avisos;
  final bool mudou;

  @override
  Future<ResultadoSincronizacao> mesclar(
    Map<String, List<Linha>> abasLidas,
  ) async {
    final r = await super.mesclar(abasLidas);
    return ResultadoSincronizacao(
      mudou: mudou,
      avisos: avisos,
      linhas: r.linhas,
    );
  }
}

class _Cenario {
  _Cenario({
    ContaGoogleFalsa? conta,
    DadosSincronizacao Function(Repositorio)? dados,
    Duration atraso = const Duration(milliseconds: 20),
  }) : conta = conta ?? ContaGoogleFalsa(),
       repo = Repositorio(ArmazenamentoMemoria()) {
    this.dados = dados?.call(repo) ?? DadosSincronizacaoLocal(repo);
    sync = Sincronizador(
      conta: this.conta,
      dados: this.dados,
      aoMudarStatus: status.add,
      aoMudarDados: () => mudancas++,
      aoAvisar: avisos.add,
      atrasoAgendamento: atraso,
    );
  }

  final ContaGoogleFalsa conta;
  final Repositorio repo;
  late final DadosSincronizacao dados;
  late final Sincronizador sync;
  final status = <StatusSync>[];
  final avisos = <String>[];
  int mudancas = 0;

  Config get cfg => repo.lerConfig();

  void comPlanilha([String sid = 'sid1']) {
    final c = repo.lerConfig();
    c.planilhas['ana@gmail.com'] = sid;
    repo.gravarConfig(c, carimbar: false);
  }

  void marcarPendente(bool v) {
    final c = repo.lerConfig();
    c.pendente = v;
    repo.gravarConfig(c, carimbar: false);
  }
}

void main() {
  setUp(() => ambiente = Ambiente.fixo(agora: 1761000000.0));
  tearDown(() => ambiente = Ambiente.sistema());

  test('ciclo completo: lê, mescla e grava as linhas montadas', () async {
    final c = _Cenario()..comPlanilha();
    c.marcarPendente(true);
    await c.sync.sincronizar();
    expect(c.conta.chamadas, ['ler:sid1', 'escrever:sid1']);
    final esperado = montarLinhas(
      c.repo.carregarMeses().values.toList(),
      c.repo.lerConfig(),
    );
    expect(c.conta.escritas.single, equals(esperado));
    expect(c.cfg.pendente, isFalse);
    expect(c.sync.status, StatusSync.ok);
    expect(c.status, [StatusSync.sync, StatusSync.ok]);
    expect(c.sync.ultimaSync, 1761000000.0);
    expect(c.sync.ultimaPuxada, 1761000000.0);
    expect(c.sync.ultimoErro, '');
    expect(c.sync.rodando, isFalse);
  });

  test('sem conta: nada acontece', () async {
    final c = _Cenario(conta: ContaGoogleFalsa(email: null));
    await c.sync.sincronizar();
    expect(c.conta.chamadas, isEmpty);
    expect(c.status, isEmpty);
  });

  test('sem planilha: procura a do usuário e cria se não houver; grava planilhas[email]', () async {
    final c = _Cenario();
    c.conta.achada = 'sid-achada';
    await c.sync.sincronizar();
    expect(c.cfg.planilhas['ana@gmail.com'], 'sid-achada');
    expect(c.conta.chamadas, [
      'buscar:me',
      'ler:sid-achada',
      'escrever:sid-achada',
    ]);

    final d = _Cenario();
    await d.sync.sincronizar();
    expect(d.conta.chamadas.take(2), ['buscar:me', 'criar']);
    expect(d.cfg.planilhas['ana@gmail.com'], 'sid-criada');
  });

  test('planilha do cfg apagada: procura de novo', () async {
    final c = _Cenario()..comPlanilha('velha');
    c.conta
      ..existe = false
      ..achada = 'nova';
    final sid = await c.sync.prepararPlanilha();
    expect(sid, 'nova');
    expect(c.conta.chamadas, ['existe:velha', 'buscar:me']);
    expect(c.cfg.planilhas['ana@gmail.com'], 'nova');
  });

  test('planilha do cfg existente é mantida', () async {
    final c = _Cenario()..comPlanilha('boa');
    expect(await c.sync.prepararPlanilha(), 'boa');
    expect(c.conta.chamadas, ['existe:boa']);
  });

  test(
    'pedido durante a sincronização refaz o ciclo antes de limpar pendente',
    () async {
      final c = _Cenario()..comPlanilha();
      c.marcarPendente(true);
      var primeira = true;
      final pendentesVistos = <bool>[];
      c.conta.aoEscrever = () async {
        pendentesVistos.add(c.cfg.pendente);
        if (primeira) {
          primeira = false;
          expect(c.sync.rodando, isTrue);
          await c.sync.sincronizar();
        }
      };
      await c.sync.sincronizar();
      expect(c.conta.leituras, 2);
      expect(c.conta.escritas, hasLength(2));
      expect(pendentesVistos, [true, true]);
      expect(c.cfg.pendente, isFalse);
      expect(c.status, [StatusSync.sync, StatusSync.ok]);
    },
  );

  test(
    'LoginNecessario: sai da conta, status off e aviso de sessão expirada',
    () async {
      final c = _Cenario()..comPlanilha();
      c.conta.falhaLer = LoginNecessario('x');
      await c.sync.sincronizar();
      expect(c.conta.chamadas, contains('sair'));
      expect(c.sync.status, StatusSync.off);
      expect(c.avisos, [
        'Sessão expirada. Conecte sua conta Google novamente.',
      ]);
      expect(c.sync.rodando, isFalse);
    },
  );

  test('Offline: status offline e pendente continua true', () async {
    final c = _Cenario()..comPlanilha();
    c.marcarPendente(true);
    c.conta.falhaEscrever = Offline('sem rede');
    await c.sync.sincronizar();
    expect(c.sync.status, StatusSync.offline);
    expect(c.cfg.pendente, isTrue);
    expect(c.avisos, isEmpty);
  });

  test('404: esquece a planilha do e-mail, status erro e ultimoErro', () async {
    final c = _Cenario()..comPlanilha();
    c.conta.falhaLer = ErroGoogle('Requested entity was not found.', 404);
    await c.sync.sincronizar();
    expect(c.cfg.planilhas, isEmpty);
    expect(c.sync.status, StatusSync.erro);
    expect(c.sync.ultimoErro, 'Requested entity was not found.');
  });

  test('outro erro: status erro, planilha mantida', () async {
    final c = _Cenario()..comPlanilha();
    c.conta.falhaLer = ErroGoogle('falhou', 500);
    await c.sync.sincronizar();
    expect(c.cfg.planilhas, isNotEmpty);
    expect(c.sync.status, StatusSync.erro);
    expect(c.sync.ultimoErro, 'falhou');
    expect(c.sync.rodando, isFalse);
  });

  test('avisos da mesclagem viram "Ajuste manual necessário: ..."', () async {
    final c = _Cenario(dados: (r) => DadosComAvisos(r, ['a', 'b'], false))
      ..comPlanilha();
    await c.sync.sincronizar();
    expect(c.avisos, [
      'Ajuste manual necessário: a',
      'Ajuste manual necessário: b',
    ]);
  });

  test('mudou chama aoMudarDados', () async {
    final c = _Cenario(dados: (r) => DadosComAvisos(r, [], true))
      ..comPlanilha();
    await c.sync.sincronizar();
    expect(c.mudancas, 1);
    final d = _Cenario(dados: (r) => DadosComAvisos(r, [], false))
      ..comPlanilha();
    await d.sync.sincronizar();
    expect(d.mudancas, 0);
  });

  test('config ilegível não é trocada pelo padrão', () async {
    final c = _Cenario()..comPlanilha();
    c.repo.armazenamento.gravar('config.json', '{quebrado');
    await c.sync.sincronizar();
    expect(c.sync.status, StatusSync.erro);
    expect(c.repo.armazenamento.ler('config.json'), '{quebrado');
  });

  test('agendar: sem conta só marca pendente; com conta uma sincronização para várias chamadas', () async {
    final s = _Cenario(conta: ContaGoogleFalsa(email: null));
    await s.sync.agendar();
    expect(s.cfg.pendente, isTrue);
    expect(s.status, isEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(s.conta.chamadas, isEmpty);

    final c = _Cenario()..comPlanilha();
    await c.sync.agendar();
    await c.sync.agendar();
    await c.sync.agendar();
    expect(c.cfg.pendente, isTrue);
    expect(c.sync.status, StatusSync.pendente);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(c.conta.escritas, hasLength(1));
    expect(c.sync.status, StatusSync.ok);
    expect(c.cfg.pendente, isFalse);
  });

  test('tick: pendente ou mais de 300 s sem puxar dispara; sem conta e com token conecta', () async {
    final c = _Cenario()..comPlanilha();
    await c.sync.sincronizar();
    c.conta.chamadas.clear();
    await c.sync.tick(); // recém puxada, sem pendente
    expect(c.conta.chamadas, isEmpty);

    c.marcarPendente(true);
    await c.sync.tick();
    expect(c.conta.chamadas, ['ler:sid1', 'escrever:sid1']);

    c.conta.chamadas.clear();
    ambiente = Ambiente.fixo(agora: 1761000000.0 + 301);
    await c.sync.tick();
    expect(c.conta.chamadas, ['ler:sid1', 'escrever:sid1']);

    final t = _Cenario(conta: ContaGoogleFalsa(email: null, token: true));
    t.conta.achada = 'p';
    await t.sync.tick();
    expect(t.conta.chamadas.first, 'carregarToken');
    expect(t.conta.email, 'ana@gmail.com');
  });

  test('tick com conta e sem planilha prepara a planilha', () async {
    final c = _Cenario();
    c.conta.achada = 'x';
    await c.sync.tick(); // ultimaPuxada = 0: atrasada
    expect(c.cfg.planilhas['ana@gmail.com'], 'x');
  });

  test(
    'conectarComToken: Offline → offline; outro erro → sair e off',
    () async {
      final a = _Cenario(conta: ContaGoogleFalsa(email: null));
      a.conta.falhaCarregar = Offline('sem rede');
      await a.sync.conectarComToken();
      expect(a.sync.status, StatusSync.offline);
      expect(a.conta.chamadas, ['carregarToken']);

      final b = _Cenario(conta: ContaGoogleFalsa(email: null));
      b.conta.falhaCarregar = LoginNecessario('x');
      await b.sync.conectarComToken();
      expect(b.sync.status, StatusSync.off);
      expect(b.conta.chamadas, ['carregarToken', 'sair']);

      final c = _Cenario(conta: ContaGoogleFalsa(email: null));
      c.conta.achada = 'p';
      await c.sync.conectarComToken();
      expect(c.sync.status, StatusSync.ok);
      expect(c.cfg.planilhas['ana@gmail.com'], 'p');
    },
  );

  test('conectar: "Conectado como x@y.com." e sincroniza; falha → off e aviso com a mensagem', () async {
    final c = _Cenario(conta: ContaGoogleFalsa(email: null));
    c.conta.achada = 'p';
    await c.sync.conectar((_) async {});
    expect(c.avisos, ['Conectado como ana@gmail.com.']);
    expect(c.status.first, StatusSync.login);
    expect(c.sync.status, StatusSync.ok);

    final d = _Cenario(conta: ContaGoogleFalsa(email: null));
    d.conta.falhaLogin = ErroGoogle('O login foi cancelado.');
    await d.sync.conectar((_) async {});
    expect(d.sync.status, StatusSync.off);
    expect(d.avisos, ['O login foi cancelado.']);

    final e = _Cenario(conta: ContaGoogleFalsa(email: null));
    e.conta.falhaLogin = ErroGoogle('');
    await e.sync.conectar((_) async {});
    expect(e.avisos, ['O login não foi concluído.']);
  });

  test('sair: sai da conta e status off', () {
    final c = _Cenario();
    c.sync.sair();
    expect(c.conta.chamadas, ['sair']);
    expect(c.sync.status, StatusSync.off);
  });

  test('lerAmigo sem planilha compartilhada → mensagem do Python', () async {
    final c = _Cenario();
    await expectLater(
      c.sync.lerAmigo('bia@gmail.com'),
      throwsA(
        isA<ErroGoogle>().having(
          (e) => e.toString(),
          'mensagem',
          'bia@gmail.com ainda não compartilhou a planilha com você. '
              'Peça para ele adicionar ana@gmail.com em Amigos.',
        ),
      ),
    );
    expect(c.conta.chamadas, ['buscar:bia@gmail.com']);
  });

  test(
    'lerAmigo com planilha: reconstrói sem tocar nos dados locais',
    () async {
      final c = _Cenario();
      c.conta.planilhaAmigo = 'sid-bia';
      final d = await c.sync.lerAmigo('bia@gmail.com');
      expect(d.meses, isEmpty);
      expect(c.conta.chamadas, ['buscar:bia@gmail.com', 'ler:sid-bia']);
      expect(c.cfg.planilhas, isEmpty);
    },
  );
}
