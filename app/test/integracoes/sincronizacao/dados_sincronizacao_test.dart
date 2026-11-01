import 'package:calculadoradarf/integracoes/integracoes.dart';
import 'package:calculadoradarf/nucleo/nucleo.dart';
import 'package:flutter_test/flutter_test.dart';

class _ArmazenamentoQueFalha extends ArmazenamentoMemoria {
  @override
  String? ler(String nome) {
    if (nome == 'config.json') {
      throw const FormatException('bytes UTF-8 inválidos');
    }
    return super.ler(nome);
  }
}

Future<void> _recusa(Future<Object?> f) => expectLater(
  f,
  throwsA(
    isA<ErroValidacao>().having(
      (e) => e.mensagem,
      'mensagem',
      'O arquivo config.json está ilegível; nada foi alterado.',
    ),
  ),
);

void main() {
  for (final texto in ['{', '[]', 'null', '123']) {
    test(
      'config "$texto" recusa definirPlanilha, definirPendente e mesclar',
      () async {
        final disco = ArmazenamentoMemoria()..gravar('config.json', texto);
        final d = DadosSincronizacaoLocal(Repositorio(disco));
        await _recusa(d.definirPlanilha('a@x.com', 'sid'));
        await _recusa(d.definirPendente(true));
        await _recusa(d.mesclar({}));
        expect(disco.ler('config.json'), texto);
      },
    );
  }

  test('leitura que lança FormatException (bytes inválidos) recusa', () async {
    final repo = Repositorio(_ArmazenamentoQueFalha());
    await _recusa(DadosSincronizacaoLocal(repo).definirPendente(true));
    expect(() => repo.lerConfigParaGravar(), throwsA(isA<ErroValidacao>()));
  });

  test('config legível ou ausente é lida normalmente', () async {
    final d = DadosSincronizacaoLocal(Repositorio(ArmazenamentoMemoria()));
    await d.definirPendente(true);
    expect(await d.pendente(), isTrue);
  });
}
