import 'package:calculadoradarf/app/app.dart';
import 'package:calculadoradarf/app/servicos/api.dart';
import 'package:calculadoradarf/app/web/entrada_web.dart';
import 'package:calculadoradarf/nucleo/nucleo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../apoio/plataforma_falsa.dart';
import '../apoio/servicos_falsos.dart';

const _textoOutraAba =
    'A Calculadora DARF já está aberta em outra aba ou janela deste navegador. '
    'Feche a outra e toque em "Tentar de novo".';
final _pacote = 'v1.${'a' * 40}';

void main() {
  late ArmazenamentoMemoria a;
  late int limpezas;
  late List<(String, String)> avisos;
  ServicosApp? s;

  setUp(() {
    a = ArmazenamentoMemoria();
    limpezas = 0;
    avisos = [];
    s = null;
  });

  tearDown(() async => s?.encerrar());

  Future<ServicosApp> preparar(
    String endereco, {
    String? nonce = 'n1',
    bool trava = true,
    bool armazenamento = true,
  }) async {
    return s = await prepararServicosWeb(
      endereco: Uri.parse(endereco),
      nonceEsperado: nonce,
      armazenamentoNavegador: armazenamento ? a : null,
      travarAba: () async => trava,
      limparEndereco: () => limpezas++,
      irPara: (_) async {},
      abrirUrl: (_) async => true,
      avisar: (t, x) => avisos.add((t, x)),
      cliente: MockClient((_) async => http.Response('', 503)),
      timers: false,
    );
  }

  test(
    'outra aba com a trava: ErroOutraAba sem tocar no armazenamento',
    () async {
      await expectLater(
        preparar('https://calculadora-darf.vercel.app/', trava: false),
        throwsA(isA<ErroOutraAba>()),
      );
      expect(a.listar(), isEmpty);
      expect(const ErroOutraAba().toString(), _textoOutraAba);
    },
  );

  test('outra aba com retorno de login: endereço limpo mesmo assim', () async {
    await expectLater(
      preparar(
        'https://calculadora-darf.vercel.app/#auth=$_pacote&n=n1',
        trava: false,
      ),
      throwsA(isA<ErroOutraAba>()),
    );
    expect(limpezas, 1);
    expect(a.ler('token.json'), isNull);
  });

  test('retorno com pacote: grava o token.json e limpa o endereço', () async {
    await preparar('https://calculadora-darf.vercel.app/#auth=$_pacote&n=n1');
    expect(a.ler('token.json'), contains(_pacote));
    expect(limpezas, 1);
    expect(avisos, isEmpty);
  });

  test('pacote com n errado não é gravado e avisa a falha', () async {
    await preparar(
      'https://calculadora-darf.vercel.app/#auth=$_pacote&n=outro',
    );
    expect(a.ler('token.json'), isNull);
    expect(limpezas, 1);
    expect(avisos, [('Login não concluído', 'O login não foi concluído.')]);
  });

  test('pacote sem nonce guardado não é gravado', () async {
    await preparar(
      'https://calculadora-darf.vercel.app/#auth=$_pacote&n=n1',
      nonce: null,
    );
    expect(a.ler('token.json'), isNull);
    expect(avisos, [('Login não concluído', 'O login não foi concluído.')]);
  });

  test('auth_erro=acesso_negado: avisa o cancelamento, sem token', () async {
    await preparar(
      'https://calculadora-darf.vercel.app/#auth_erro=acesso_negado&n=n1',
    );
    expect(avisos, [('Login não concluído', 'O login foi cancelado.')]);
    expect(limpezas, 1);
    expect(a.ler('token.json'), isNull);
  });

  test('auth_erro com código estranho usa só o texto genérico', () async {
    await preparar(
      'https://calculadora-darf.vercel.app/#auth_erro=%3Cscript%3E&n=n1',
    );
    expect(avisos, [('Login não concluído', 'O login não foi concluído.')]);
    expect(limpezas, 1);
  });

  test('armazenamento bloqueado: sobe em memória e avisa', () async {
    final serv = await preparar(
      'https://calculadora-darf.vercel.app/',
      armazenamento: false,
    );
    await serv.iniciar();
    expect(avisos, [
      (
        'Dados do navegador bloqueados',
        'O navegador não permite que o app guarde dados neste site. O app '
            'funciona, mas será preciso entrar de novo a cada visita.',
      ),
    ]);
    expect(a.listar(), isEmpty);
  });

  test('sem fragmento: não limpa o endereço', () async {
    await preparar('https://calculadora-darf.vercel.app/');
    expect(limpezas, 0);
    expect(avisos, isEmpty);
  });

  test('fragmento que não é de login: não limpa o endereço', () async {
    await preparar('https://calculadora-darf.vercel.app/#outra=1');
    expect(limpezas, 0);
  });

  test(
    'armazenamento bloqueado e auth_erro: os dois avisos, em ordem',
    () async {
      await preparar(
        'https://calculadora-darf.vercel.app/#auth_erro=acesso_negado&n=n1',
        armazenamento: false,
      );
      expect(avisos.map((a) => a.$1), [
        'Dados do navegador bloqueados',
        'Login não concluído',
      ]);
    },
  );

  testWidgets('todos os avisos iniciais da Web chegam à interface, em ordem', (
    t,
  ) async {
    t.view.physicalSize = const Size(1366, 768);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    late final EntradaWeb e;
    e = EntradaWeb(
      plataforma: PlataformaFalsa(web: true),
      criarServicos: (_) async {
        e.avisosIniciais
          ..add(('Dados do navegador bloqueados', 'texto 1'))
          ..add(('Login não concluído', 'O login foi cancelado.'));
        return ServicosFalsos();
      },
    );
    await iniciarApp(entrada: () => e);
    await t.pump(const Duration(seconds: 1));
    await t.pump();
    expect(find.text('Dados do navegador bloqueados'), findsOneWidget);
    await t.tap(find.text('OK'));
    await t.pump(const Duration(seconds: 1));
    await t.pump();
    expect(find.text('Login não concluído'), findsOneWidget);
    expect(find.text('O login foi cancelado.'), findsOneWidget);
  });

  testWidgets('ErroOutraAba na partida mostra o texto e Tentar de novo', (
    t,
  ) async {
    t.view.physicalSize = const Size(1366, 768);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await iniciarApp(
      criarServicos: (_) async => throw const ErroOutraAba(),
      plataforma: PlataformaFalsa(web: true),
    );
    await t.pump();
    expect(find.textContaining(_textoOutraAba), findsOneWidget);
    expect(find.text('Tentar de novo'), findsOneWidget);
  });
}
