import 'package:calculadoradarf/app/regras/apresentacao.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('sinal, seta e texto com sinal', () {
    test('positivo, negativo e zero (até meio centavo é zero)', () {
      expect(sinalDe(270), Sinal.alta);
      expect(sinalDe(-0.01), Sinal.queda);
      expect(sinalDe(0.004), Sinal.neutro);
      expect(sinalDe(-0.004), Sinal.neutro);
      expect(sinalDe(null), Sinal.neutro);
    });

    test('seta só com sinal', () {
      expect(setaDe(Sinal.alta), '▲ ');
      expect(setaDe(Sinal.queda), '▼ ');
      expect(setaDe(Sinal.neutro), '');
    });

    test('R\$ com sinal explícito', () {
      expect(brlComSinal(270), '+R\$ 270,00');
      expect(brlComSinal(-1234.5), '-R\$ 1.234,50');
      expect(brlComSinal(0), 'R\$ 0,00');
    });

    test('percentual curto com uma casa e sinal', () {
      expect(pctCurto(8.6), '+8,6%');
      expect(pctCurto(-9.09), '-9,1%');
      expect(pctCurto(0), '0,0%');
      expect(pctCurto(null), '—');
    });

    test('resultado com seta, sinal e percentual', () {
      expect(textoResultado(270, 8.6), '▲ +R\$ 270,00 (+8,6%)');
      expect(textoResultado(-50, -2.5), '▼ -R\$ 50,00 (-2,5%)');
      expect(textoResultado(-50, null), '▼ -R\$ 50,00');
      expect(textoResultado(0, 0), 'R\$ 0,00 (0,0%)');
      expect(textoResultado(null, 3), '—');
    });
  });

  group('valores derivados', () {
    test('valor atual = quantidade × cotação, em centavos', () {
      expect(valorAtual(60, 36.2), 2172);
      expect(valorAtual(3, 10.005), 30.02);
      expect(valorAtual(10, null), isNull);
      expect(valorAtual(10, 0), 0);
      expect(valorAtual(0, 36.2), isNull);
    });

    test('percentual sobre o custo; custo zero ou sem dado: nulo', () {
      expect(pctSobre(270, 3000), closeTo(9, 1e-9));
      expect(pctSobre(-30, 300), closeTo(-10, 1e-9));
      expect(pctSobre(10, 0), isNull);
      expect(pctSobre(null, 100), isNull);
      expect(pctSobre(10, null), isNull);
    });

    test('variação do preço atual até um alvo ou stop', () {
      expect(variacaoPct(10, 12.5), closeTo(25, 1e-9));
      expect(variacaoPct(10, 9.09), closeTo(-9.1, 1e-9));
      expect(variacaoPct(0, 5), isNull);
      expect(variacaoPct(null, 5), isNull);
      expect(variacaoPct(10, null), isNull);
    });
  });

  group('marcador da barra stop · atual · alvo', () {
    test('proporcional entre o stop e o alvo', () {
      expect(posicaoMarcador(stop: 9, atual: 10, alvo: 13), closeTo(.25, 1e-9));
      expect(posicaoMarcador(stop: 9, atual: 9, alvo: 13), 0);
      expect(posicaoMarcador(stop: 9, atual: 13, alvo: 13), 1);
    });

    test('limitado às pontas', () {
      expect(posicaoMarcador(stop: 9, atual: 8, alvo: 13), 0);
      expect(posicaoMarcador(stop: 9, atual: 20, alvo: 13), 1);
    });

    test('sem dado ou alvo que não fica acima do stop: nulo', () {
      expect(posicaoMarcador(stop: null, atual: 10, alvo: 13), isNull);
      expect(posicaoMarcador(stop: 9, atual: null, alvo: 13), isNull);
      expect(posicaoMarcador(stop: 9, atual: 10, alvo: null), isNull);
      expect(posicaoMarcador(stop: 13, atual: 10, alvo: 13), isNull);
      expect(posicaoMarcador(stop: 14, atual: 10, alvo: 13), isNull);
    });
  });
}
