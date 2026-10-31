// Preço-alvo e projeção de venda (metas.py:42-111).

import '../apuracao.dart';
import '../compat/numeros.dart';
import '../constantes.dart';
import '../erros.dart';
import '../modelos/lote.dart';
import '../modelos/meta.dart';

/// `math.ceil(round(v * 100, 6)) / 100`: arredonda para cima no centavo (o
/// preço sugerido nunca fica abaixo do necessário). O `+ 0.0` troca o -0.0 de
/// `ceilToDouble` pelo 0 inteiro do Python.
double tetoCentavo(double v) =>
    arredondar(v * 100, 6).ceilToDouble() / 100 + 0.0;

/// `math.floor(round(v * 100, 6)) / 100`: arredonda para baixo no centavo (o
/// stop sugerido nunca fica acima do calculado).
double pisoCentavo(double v) =>
    arredondar(v * 100, 6).floorToDouble() / 100 + 0.0;

/// `"alvo"` (venda quando a máxima chega ao preço-alvo) ou `"stop"` (venda
/// quando a mínima chega ao stop). Metas gravadas antes do stop são alvos.
String gatilho(Meta m) {
  final g = m.gatilho;
  return g == null || g.isEmpty ? 'alvo' : g;
}

double precoGatilho(Meta m) =>
    gatilho(m) == 'stop' ? m.stopAtual! : m.precoAlvo!;

/// Resultado de vender com as chaves de `calcular_venda` mais imposto, irrf
/// (retenção estimada), darf estimado, custos (taxas B3 + corretagem) e lucro
/// após imposto.
class Projecao extends ResultadoVenda {
  Projecao({
    required ResultadoVenda c,
    required this.imposto,
    required this.irrf,
    required this.darfEstimado,
    required this.custos,
    required this.lucroAposImposto,
  }) : super(
         dt: c.dt,
         compra: c.compra,
         venda: c.venda,
         taxas: c.taxas,
         corretagem: c.corretagem,
         bruto: c.bruto,
         liquido: c.liquido,
       );

  final double imposto;
  final double irrf;
  final double darfEstimado;
  final double custos;
  final double lucroAposImposto;

  @override
  Map<String, Object?> toJson() => {
    ...super.toJson(),
    'imposto': imposto,
    'irrf': irrf,
    'darf_estimado': darfEstimado,
    'custos': custos,
    'lucro_apos_imposto': lucroAposImposto,
  };
}

/// `projetar`: resultado de vender [qtd] do lote por [preco], com as mesmas
/// contas de `calcularVenda`.
Projecao projetar(Lote lote, num qtd, double preco, {bool dayTrade = false}) {
  final c = calcularVendaQtd(lote, qtd, preco, dayTrade ? lote.dataCompra : '');
  final imposto =
      maxPython(c.liquido, 0.0) * (dayTrade ? aliqDaytrade : aliqSwing);
  var irrf = dayTrade
      ? maxPython(c.liquido, 0.0) * irrfDaytrade
      : c.venda * irrfSwing;
  if (irrf <= 1) {
    // a Receita só retém acima de R$ 1,00
    irrf = 0.0;
  }
  return Projecao(
    c: c,
    imposto: imposto,
    irrf: irrf,
    darfEstimado: maxPython(imposto - irrf, 0.0),
    custos: c.taxas + c.corretagem,
    lucroAposImposto: c.liquido - imposto,
  );
}

/// Projeção no preço sugerido (arredondado para cima no centavo), mais o
/// preço exato, o preço médio, o bruto necessário e o lucro desejado.
class PrecoAlvo extends Projecao {
  PrecoAlvo({
    required Projecao p,
    required this.preco,
    required this.precoExato,
    required this.precoMedio,
    required this.brutoNecessario,
    required this.lucroDesejado,
    required this.qtd,
    required this.dayTrade,
  }) : super(
         c: p,
         imposto: p.imposto,
         irrf: p.irrf,
         darfEstimado: p.darfEstimado,
         custos: p.custos,
         lucroAposImposto: p.lucroAposImposto,
       );

  final double preco;
  final double precoExato;
  final double precoMedio;
  final double brutoNecessario;
  final double lucroDesejado;
  final num qtd;
  final bool dayTrade;

  @override
  Map<String, Object?> toJson() => {
    ...super.toJson(),
    'preco': preco,
    'preco_exato': precoExato,
    'preco_medio': precoMedio,
    'bruto_necessario': brutoNecessario,
    'lucro_desejado': lucroDesejado,
    'qtd': qtd,
    'day_trade': dayTrade,
  };
}

/// Preço de venda por ação para sobrar [lucroLiquido] (R$) depois de taxas,
/// corretagem e imposto. [dayTrade]: venda no mesmo dia da compra.
PrecoAlvo calcularPrecoAlvo(
  Lote lote,
  num qtd,
  double lucroLiquido, {
  bool dayTrade = false,
}) {
  if (!qtd.isFinite || qtd <= 0) {
    throw ErroValidacao('Quantidade inválida.');
  }
  if (!lucroLiquido.isFinite) {
    throw ErroValidacao('Lucro desejado inválido.');
  }
  final t = dayTrade ? taxaB3Daytrade : taxaB3Swing;
  final aliq = dayTrade ? aliqDaytrade : aliqSwing;
  final bruto = lucroLiquido > 0 ? lucroLiquido / (1 - aliq) : lucroLiquido;
  final corretagem = corretagemPorOrdem * (1 + qtd / lote.qtd);
  final exato =
      (bruto + qtd * lote.preco * (1 + t) + corretagem) / (qtd * (1 - t));
  if (!exato.isFinite) {
    throw ErroValidacao('Valores grandes demais para calcular.');
  }
  if (exato <= 0) {
    throw ErroValidacao(
      'Com esse resultado o preço de venda seria zero ou negativo.',
    );
  }
  final preco = maxPython(tetoCentavo(exato), 0.01);
  return PrecoAlvo(
    p: projetar(lote, qtd, preco, dayTrade: dayTrade),
    preco: preco,
    precoExato: exato,
    precoMedio: lote.preco,
    brutoNecessario: bruto,
    lucroDesejado: lucroLiquido,
    qtd: qtd,
    dayTrade: dayTrade,
  );
}
