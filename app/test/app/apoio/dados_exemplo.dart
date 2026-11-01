// Dados fixos dos testes de tela e dos goldens: meses, radar, notícias e
// metas. "Hoje" dos testes é 2026-10-28 (`Ambiente.fixo`).

import 'package:calculadoradarf/app/servicos/api.dart';
import 'package:calculadoradarf/nucleo/nucleo.dart';

const hojeExemplo = '2026-10-28';

/// Mês aberto com uma compra sem venda, uma com venda parcial e um BDR.
Mes mesAbertoExemplo() => Mes(
  mes: '2026-10',
  lotes: [
    Lote(
      id: 'L1',
      ticker: 'PETR4',
      tipo: 'Ação',
      dataCompra: '2026-10-05',
      qtd: 100,
      preco: 32.5,
      vendas: [Venda(id: 'V1', data: '2026-10-20', qtd: 40, preco: 35)],
    ),
    Lote(
      id: 'L2',
      ticker: 'VALE3',
      tipo: 'Ação',
      dataCompra: '2026-10-08',
      qtd: 200,
      preco: 60.1,
    ),
    Lote(
      id: 'L3',
      ticker: 'AAPL34',
      tipo: 'BDR',
      dataCompra: '2026-10-12',
      qtd: 50,
      preco: 55,
    ),
  ],
);

/// Mês fechado, sem compras em aberto.
Mes mesFechadoExemplo() => Mes(
  mes: '2026-09',
  fechado: true,
  lotes: [
    Lote(
      id: 'F1',
      ticker: 'ITUB4',
      tipo: 'Ação',
      dataCompra: '2026-09-02',
      qtd: 100,
      preco: 30,
      vendas: [Venda(id: 'FV1', data: '2026-09-18', qtd: 100, preco: 32)],
    ),
  ],
);

VisaoMes visaoExemplo(Mes d, {String? amigo, String? erroLeitura}) => VisaoMes(
  mes: d.mes,
  dados: d,
  apuracao: apurar(d),
  amigo: amigo,
  erroLeitura: erroLeitura,
);

VisaoCaixa caixaExemplo({double saldo = 5000}) {
  final cfg = Config(
    caixa: Caixa(saldo: saldo, data: '2026-10-01'),
  );
  final meses = {'2026-09': mesFechadoExemplo(), '2026-10': mesAbertoExemplo()};
  final resumo = resumoCaixa(cfg, meses, hoje: hojeExemplo);
  return VisaoCaixa(
    resumo: resumo,
    projecao: projecaoCaixa(resumo, hoje: hojeExemplo),
    agenda: agendaCaixa(resumo, hoje: hojeExemplo),
    hoje: hojeExemplo,
  );
}

List<ItemRadar> radarExemplo() => [
  ItemRadar(ticker: 'PETR4', nome: 'Petrobras PN', desde: '2026-09-01', pos: 0),
  ItemRadar(ticker: 'WEGE3', nome: 'WEG ON', desde: '2026-09-03', pos: 1),
  ItemRadar(ticker: 'MXRF11', nome: 'Maxi Renda', desde: '2026-09-10', pos: 2),
];

List<Noticia> noticiasExemplo() => [
  Noticia(
    id: 'n1',
    titulo: 'Petrobras anuncia dividendos acima do esperado',
    link: 'https://exemplo.com/n1',
    fonte: 'Fonte A',
    fonteUrl: 'https://fontea.example.com',
    data: 1761600000,
    tickers: ['PETR4'],
    temas: ['Dividendos'],
  ),
  Noticia(
    id: 'n2',
    titulo: 'Vale reduz projeção de produção de minério',
    link: 'https://exemplo.com/n2',
    fonte: 'Fonte B',
    fonteUrl: 'https://fonteb.example.com',
    data: 1761590000,
    tickers: ['VALE3'],
    temas: [],
  ),
  Noticia(
    id: 'n3',
    titulo: 'Copom mantém a Selic',
    link: 'https://exemplo.com/n3',
    fonte: 'Fonte A',
    fonteUrl: 'https://fontea.example.com',
    data: 1761580000,
    tickers: [],
    temas: ['Macro'],
  ),
];

List<Meta> metasExemplo() => [
  Meta(
    id: 'M1',
    ticker: 'PETR4',
    tipo: 'Ação',
    loteId: 'L1',
    qtd: 60,
    precoAlvo: 40,
    criadaEm: '2026-10-21T11:00:00-03:00',
    status: 'ativa',
  ),
  Meta(
    id: 'M2',
    ticker: 'VALE3',
    tipo: 'Ação',
    loteId: 'L2',
    qtd: 100,
    gatilho: 'stop',
    stopInicial: 55,
    stopAtual: 55,
    movel: true,
    niveis: [],
    criadaEm: '2026-10-22T11:00:00-03:00',
    status: 'ativa',
  ),
];
