import 'package:calculadoradarf/nucleo/nucleo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('o barril expõe um símbolo de cada área', () {
    final repo = Repositorio(ArmazenamentoMemoria()); // repositório
    final cfg = Config(); // modelos
    final mes = mesVazio('2026-10'); // modelos
    expect(repo.carregar('2026-10').mes, mes.mes);
    expect(metasAtivas(cfg), isEmpty); // metas
    expect(apurar(mes).darf, 0.0); // apuração
    expect(fmtData('2026-10-28'), '28/10/2026'); // datas
    expect(brl(1.125), isNotEmpty); // formatação
    expect(jsonPython({'a': 1}), '{"a": 1}'); // compat
    expect(ErroValidacao('x').toString(), 'x'); // erros
    expect(resumoCaixa(cfg, {}, hoje: '2026-10-28').definido, isFalse); // caixa
    expect(montarLinhas([mes], cfg)['Resumo'], isNotEmpty); // planilha
    expect(EstadoNoticias().vistos, isEmpty); // notícias
  });
}
