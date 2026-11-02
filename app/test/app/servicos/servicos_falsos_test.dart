import 'package:calculadoradarf/app/servicos/api.dart';
import 'package:calculadoradarf/app/servicos/eventos.dart';
import 'package:calculadoradarf/integracoes/integracoes.dart';
import 'package:calculadoradarf/nucleo/nucleo.dart';
import 'package:flutter_test/flutter_test.dart';

import '../apoio/servicos_falsos.dart';

void main() {
  test('ServicosFalsos grava chamadas, devolve respostas e erros', () async {
    final f = ServicosFalsos();
    final e = await f.iniciar();
    expect(e.mesInicial, '2026-10');
    final v = await f.carregarMes('2026-10');
    expect(v.editavel, isTrue);
    expect((await f.carregarMes('2026-09')).editavel, isFalse);
    f.erros['registrarCompra'] = ErroValidacao('Informe o ticker.');
    await expectLater(
      f.registrarCompra(
        '2026-10',
        const NovaCompra(ticker: '', dataCompra: '', qtd: 1, preco: 1),
      ),
      throwsA(isA<ErroValidacao>()),
    );
    expect(f.chamadas, [
      'iniciar()',
      'carregarMes(2026-10, null)',
      'carregarMes(2026-09, null)',
      'registrarCompra(2026-10, )',
    ]);
  });

  test(
    'eventos falsos chegam pelo stream; método sem resposta lança',
    () async {
      final f = ServicosFalsos();
      final recebidos = <EventoServico>[];
      f.eventos.listen(recebidos.add);
      f.eventosFalsos.add(const EventoDadosMudaram());
      await Future<void>.delayed(Duration.zero);
      expect(recebidos.single, isA<EventoDadosMudaram>());
      await expectLater(f.radar(), throwsA(isA<UnimplementedError>()));
      expect(f.chamadas, ['radar()']);
    },
  );

  test('conta e amigos: respostas, chamadas e erro programável', () async {
    final f = ServicosFalsos();
    expect((await f.conta()).status, StatusSync.off);
    await f.adicionarAmigo('bia@gmail.com');
    expect((await f.amigos()).single.email, 'bia@gmail.com');
    final r = await f.carregarAmigo('bia@gmail.com');
    expect((r.email, r.mesInicial), ('bia@gmail.com', '2026-10'));
    await f.removerAmigo('bia@gmail.com');
    expect(await f.amigos(), isEmpty);
    f.erros['conectar'] = ErroValidacao('Sem credencial.');
    f.erros['sincronizarAgora'] = ErroValidacao('Falhou.');
    await expectLater(f.conectar(), throwsA(isA<ErroValidacao>()));
    await expectLater(f.sincronizarAgora(), throwsA(isA<ErroValidacao>()));
    await f.sair();
    await f.cancelarLogin();
    await f.esquecerAmigo();
    expect(f.chamadas, [
      'conta()',
      'adicionarAmigo(bia@gmail.com)',
      'amigos()',
      'carregarAmigo(bia@gmail.com)',
      'removerAmigo(bia@gmail.com)',
      'amigos()',
      'conectar()',
      'sincronizarAgora()',
      'sair()',
      'cancelarLogin()',
      'esquecerAmigo()',
    ]);
  });
}
