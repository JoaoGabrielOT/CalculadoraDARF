import 'package:calculadoradarf/app/servicos/api.dart';
import 'package:calculadoradarf/app/servicos/eventos.dart';
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
      await expectLater(f.conta(), throwsA(isA<UnimplementedError>()));
      expect(f.chamadas, ['conta()']);
    },
  );
}
