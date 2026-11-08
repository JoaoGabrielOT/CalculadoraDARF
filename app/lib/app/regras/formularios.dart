// Validação dos formulários de compra, venda e saldo e textos do resumo da
// ordem (sem Flutter nem IO). As mensagens são as do Python.

import '../../nucleo/nucleo.dart';
import '../servicos/api.dart';

/// Resultado de validar um formulário: o valor pronto ou a mensagem de erro.
sealed class Validacao<T> {
  const Validacao();
}

class Valido<T> extends Validacao<T> {
  const Valido(this.valor);

  final T valor;
}

class Invalido extends Validacao<Never> {
  const Invalido(this.mensagem);

  final String mensagem;
}

/// Compra digitada (calculadora_darf.py:288-311). [data] e [hoje] em ISO;
/// [editando] é a compra que está sendo editada, quando houver.
Validacao<NovaCompra> validarCompra({
  required String ticker,
  required String? data,
  required String qtd,
  required String preco,
  required String hoje,
  Lote? editando,
}) {
  final t = ticker.trim().toUpperCase();
  if (t.isEmpty) return const Invalido('Informe o ticker.');
  if (data == null || data.isEmpty) {
    return const Invalido('Selecione a data da compra.');
  }
  if (data.compareTo(hoje) > 0) {
    return const Invalido('A data da compra não pode ser futura.');
  }
  final int q;
  try {
    q = parseQtd(qtd);
  } on FormatException {
    return const Invalido('Quantidade inválida.');
  }
  final double p;
  try {
    p = parseNum(preco);
  } on FormatException {
    return const Invalido('Preço inválido.');
  }
  if (editando != null) {
    final msg = erroEdicaoLote(
      editando,
      Lote(
        id: editando.id,
        ticker: t,
        tipo: tipoPorTicker(t),
        dataCompra: data,
        qtd: q,
        preco: p,
      ),
    );
    if (msg != null) return Invalido(msg);
  }
  return Valido(NovaCompra(ticker: t, dataCompra: data, qtd: q, preco: p));
}

/// Venda digitada (calculadora_darf.py:505-533). [inicioMes] é o primeiro dia
/// do mês aberto; [permitida] diz se a data cabe no mês aberto ou em mês
/// anterior que aceita venda retroativa; [reservado] é a quantidade da compra
/// presa em metas. Ao editar, data de mês anterior é inválida
/// (calculadora_darf.py:435-444); só uma venda nova pode ser retroativa.
Validacao<NovaVenda> validarVenda({
  required Lote? lote,
  required String? data,
  required String qtd,
  required String preco,
  required String inicioMes,
  required bool permitida,
  required int reservado,
  required bool editando,
}) {
  if (lote == null) {
    return const Invalido('Escolha o ticker e a compra que foi vendida.');
  }
  if (data == null || data.isEmpty) {
    return const Invalido('Selecione a data da venda.');
  }
  if (!permitida ||
      (editando && data.compareTo(inicioMes) < 0) ||
      data.compareTo(lote.dataCompra) < 0) {
    return const Invalido('Data da venda inválida para essa compra.');
  }
  final int q;
  try {
    q = parseQtd(qtd);
  } on FormatException {
    return const Invalido('Quantidade inválida.');
  }
  final disp = restante(lote);
  if (q > disp) return Invalido('Quantidade maior que a disponível ($disp).');
  final double p;
  try {
    p = parseNum(preco);
  } on FormatException {
    return const Invalido('Preço inválido.');
  }
  if (data.compareTo(inicioMes) < 0) {
    if (lote.vendas.isNotEmpty) {
      return const Invalido(
        'Essa compra já tem venda neste mês. Para registrar uma venda de mês '
        'anterior, exclua a venda deste mês, registre a antiga e depois '
        'registre de novo a deste mês.',
      );
    }
    final livre = disp - reservado;
    if (q > livre) {
      return Invalido(
        'Há metas de venda ativas nessa compra. Quantidade livre: '
        '${livre > 0 ? livre : 0}. Cancele ou ajuste a meta antes.',
      );
    }
  }
  return Valido(NovaVenda(loteId: lote.id, data: data, qtd: q, preco: p));
}

/// Venda por quantidade: [selecao] nulo é o modo automático; no manual é a
/// quantidade por compra (id -> quantidade, zeros ficam de fora do pedido).
/// [elegiveis] são as compras do ticker já existentes na data da venda. Só
/// a venda no mês aberto usa esse fluxo (a retroativa segue com uma compra).
Validacao<NovaVendaQtd> validarVendaQtd({
  required String ticker,
  required String? data,
  required String qtd,
  required String preco,
  required String inicioMes,
  required bool permitida,
  required List<Lote> elegiveis,
  required String grupo,
  Map<String, int>? selecao,
}) {
  final t = ticker.trim().toUpperCase();
  if (t.isEmpty) {
    return const Invalido('Escolha o ticker e a compra que foi vendida.');
  }
  if (data == null || data.isEmpty) {
    return const Invalido('Selecione a data da venda.');
  }
  if (elegiveis.isEmpty) {
    return const Invalido('Escolha o ticker e a compra que foi vendida.');
  }
  if (!permitida || data.compareTo(inicioMes) < 0) {
    return const Invalido('Data da venda inválida para essa compra.');
  }
  final int q;
  try {
    q = parseQtd(qtd);
  } on FormatException {
    return const Invalido('Quantidade inválida.');
  }
  final double p;
  try {
    p = parseNum(preco);
  } on FormatException {
    return const Invalido('Preço inválido.');
  }
  List<(String, int)>? pares;
  if (selecao == null) {
    try {
      alocarAutomatico(elegiveis, q, data);
    } on ErroValidacao catch (e) {
      return Invalido(e.mensagem);
    }
  } else {
    // na ordem das compras, para o pedido não depender da ordem dos toques
    final itens = <ItemAlocacao>[
      for (final l in elegiveis)
        if ((selecao[l.id] ?? 0) > 0) ItemAlocacao(l, selecao[l.id]!),
    ];
    if (selecao.entries.any(
      (e) => e.value > 0 && !elegiveis.any((l) => l.id == e.key),
    )) {
      return const Invalido('Compra fora das disponíveis nessa data.');
    }
    final erro = validarManual(elegiveis, itens, q, data);
    if (erro != null) return Invalido(erro);
    pares = [for (final i in itens) (i.lote.id, i.qtd)];
  }
  return Valido(
    NovaVendaQtd(
      ticker: t,
      data: data,
      qtd: q,
      preco: p,
      grupo: grupo,
      selecao: pares,
    ),
  );
}

/// Resumo financeiro da venda em várias compras: soma de `resumoOrdem` por
/// linha da prévia (preço de compra e day trade de cada compra). O IRRF segue
/// o Caixa: soma do dia por categoria (day trade com ganhos e perdas
/// abatidos) e o limite de R$ 1 vale uma vez por categoria, não por linha.
/// Nulo sem linhas.
ResumoOrdem? resumoVendaPrevia(PreviaVenda p, double preco, String data) {
  if (p.linhas.isEmpty) return null;
  var bruto = 0.0, taxas = 0.0, liquido = 0.0;
  var irrfSwingBruto = 0.0, resultadoDt = 0.0;
  var dayTrade = false;
  String? liquidacao;
  for (final l in p.linhas) {
    final r = resumoOrdem(
      'venda',
      l.item.qtd,
      preco,
      data,
      precoCompra: l.item.lote.preco,
      dayTrade: l.item.travado,
    );
    bruto += r.bruto;
    taxas += r.taxas;
    // valores antes do limite de R$ 1, que se aplica à soma
    liquido += r.liquido + r.irrf;
    if (r.dayTrade) {
      resultadoDt += r.liquido + r.irrf;
    } else {
      irrfSwingBruto += r.bruto * irrfSwing;
    }
    dayTrade = dayTrade || r.dayTrade;
    liquidacao ??= r.liquidacao;
  }
  final irrfSt = irrfSwingBruto > 1 ? irrfSwingBruto : 0.0;
  final irrfDt = resultadoDt * irrfDaytrade > 1
      ? resultadoDt * irrfDaytrade
      : 0.0;
  return ResumoOrdem(
    bruto: bruto,
    taxas: taxas,
    irrf: irrfSt + irrfDt,
    liquido: liquido - irrfSt - irrfDt,
    dayTrade: dayTrade,
    liquidacao: liquidacao!,
  );
}

/// Regra do modo automático (spec 6.2).
const textoRegraAutomatico =
    'Primeiro as compras de hoje (day trade, regra da Receita). Depois as de '
    'menor custo por ação, incluindo as taxas de compra; em empate, a mais '
    'antiga.';

/// Aviso fixo do painel fiscal x gerencial (spec 6.2).
const textoEscolhaDasCompras =
    'A escolha das compras organiza o seu controle, mas não muda o imposto: a '
    'Receita usa o custo médio. Vender agora as compras mais baratas aumenta '
    'o resultado desta venda e reduz o das próximas; o resultado da posição '
    'inteira não muda.';

/// Contador do modo manual.
String textoSelecionado(int escolhido, int total) =>
    'Selecionado $escolhido de $total';

String textoResultadoGerencial(double v) =>
    'Resultado pelas compras escolhidas (gerencial): ${brl(v)}';

/// [custoMedio] falso nos meses anteriores ao corte (custo por compra).
String textoResultadoFiscal(double v, {bool custoMedio = true}) =>
    'Resultado fiscal da operação (${custoMedio ? 'custo médio' : 'por compra'}): '
    '${brl(v)}';

String textoDayTradeComum(int dt, int comum) =>
    'Day trade: $dt ações; comum: $comum ações';

/// Saldo, aporte ou retirada digitados (calculadora_darf.py:570-580).
Validacao<(ModoSaldo, double)> validarSaldo(ModoSaldo modo, String valor) {
  final double v;
  try {
    v = parseValor(valor);
  } on FormatException {
    return const Invalido('Valor inválido.');
  }
  if (modo != ModoSaldo.definir && v <= 0) {
    return const Invalido('Informe um valor maior que zero.');
  }
  return Valido((modo, v));
}

/// Tipo deduzido do ticker, a partir de 5 caracteres (calculadora_darf.py:274).
String? textoTipo(String ticker) {
  final t = ticker.trim().toUpperCase();
  if (t.runes.length < 5) return null;
  return 'Tipo: ${tipoPorTicker(t)} (identificado pelo ticker)';
}

/// Texto do impacto quando faltam quantidade, preço ou data (py:202).
const textoResumoVazio = 'Preencha quantidade, preço e data.';

/// Nota do resumo da compra (py:270).
const notaResumoCompra =
    'Se vender no mesmo dia (day trade), a B3 liquida só o resultado do dia.';

/// Nota do resumo da venda (py:454-455).
String notaResumoVenda(bool dayTrade) => dayTrade
    ? 'Day trade (compra e venda no mesmo dia): a B3 liquida só o resultado, '
          'já com o IRRF de 1% sobre o lucro.'
    : 'Swing trade: crédito do valor da venda menos as taxas da B3.';

/// Textos do resumo financeiro da ordem (py:206-214); nulo quando os campos
/// estão incompletos. [debito] pinta o impacto de vermelho.
({
  String bruto,
  String taxas,
  String irrf,
  String impacto,
  bool debito,
  String liquidacao,
})?
textosResumo(ResumoOrdem? r) {
  if (r == null) return null;
  final debito = r.liquido < 0;
  return (
    bruto: brl(r.bruto),
    taxas: brl(r.taxas),
    irrf: r.irrf != 0 ? brl(r.irrf) : 'R\$ 0,00',
    impacto: debito
        ? 'Será debitado da conta: ${brl(-r.liquido)}'
        : 'Será creditado na conta: ${brl(r.liquido)}',
    debito: debito,
    liquidacao: '📅 Liquidação financeira: ${fmtLiquidacao(r.liquidacao)}',
  );
}
