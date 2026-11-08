// Esquema das abas da planilha Google (google_sync.py:9, 13-45). Contrato
// congelado: a versão Python grava e lê a mesma planilha.

const nomePlanilha = 'Calculadora DARF';

/// Coluna de uma aba: título, tipo de formatação e largura em pixels.
class ColunaAba {
  const ColunaAba(this.titulo, this.tipo, this.largura);

  final String titulo;
  final String tipo;
  final int largura;
}

/// Aba da planilha; [cor] é `#rrggbb`.
class EsquemaAba {
  const EsquemaAba(this.nome, this.cor, this.colunas, {this.oculta = false});

  final String nome;
  final String cor;
  final bool oculta;
  final List<ColunaAba> colunas;
}

/// As abas, na ordem em que o Python as cria.
const List<EsquemaAba> esquemaAbas = [
  EsquemaAba('Resumo', '#0e9f6e', [
    ColunaAba('Mês', 'centro', 90),
    ColunaAba('Status', 'centro', 90),
    ColunaAba('Vendas de ações (swing)', 'moeda', 180),
    ColunaAba('Isento', 'centro', 80),
    ColunaAba('Lucro bruto', 'resultado', 130),
    ColunaAba('Taxas B3', 'moeda', 110),
    ColunaAba('Imposto swing (15%)', 'moeda', 150),
    ColunaAba('Imposto day trade (20%)', 'moeda', 170),
    ColunaAba('IRRF retido', 'moeda', 120),
    ColunaAba('Lucro líquido', 'resultado', 130),
    ColunaAba('DARF meses anteriores', 'moeda', 170),
    ColunaAba('Total DARF', 'destaque', 130),
    ColunaAba('Modificado', 'id', 80),
    // só da 2.1: o marcador de método do mês (o Python lê as 13 primeiras)
    ColunaAba('Detalhes', 'id', 80),
  ]),
  EsquemaAba('Compras', '#2563eb', [
    ColunaAba('Mês', 'centro', 90),
    ColunaAba('Ticker', 'negrito', 90),
    ColunaAba('Tipo', 'centro', 70),
    ColunaAba('Data da compra', 'data', 120),
    ColunaAba('Quantidade', 'inteiro', 100),
    ColunaAba('Preço unitário', 'moeda', 120),
    ColunaAba('Total', 'moeda', 130),
    ColunaAba('Qtd vendida', 'inteiro', 100),
    ColunaAba('Qtd restante', 'inteiro', 110),
    ColunaAba('Situação', 'centro', 130),
    ColunaAba('ID', 'id', 80),
    ColunaAba('Origem', 'id', 80),
    ColunaAba('Modificado', 'id', 80),
  ]),
  EsquemaAba('Vendas', '#d97706', [
    ColunaAba('Mês', 'centro', 90),
    ColunaAba('Ticker', 'negrito', 90),
    ColunaAba('Tipo', 'centro', 70),
    ColunaAba('Data da compra', 'data', 120),
    ColunaAba('Preço compra', 'moeda', 120),
    ColunaAba('Data da venda', 'data', 120),
    ColunaAba('Quantidade', 'inteiro', 100),
    ColunaAba('Preço venda', 'moeda', 120),
    ColunaAba('Total venda', 'moeda', 130),
    ColunaAba('Operação', 'centro', 130),
    ColunaAba('Taxas B3', 'moeda', 110),
    ColunaAba('Lucro bruto', 'resultado', 130),
    ColunaAba('Lucro após taxas', 'resultado', 140),
    ColunaAba('Imposto', 'moeda', 120),
    ColunaAba('ID', 'id', 80),
    ColunaAba('ID compra', 'id', 80),
    ColunaAba('Modificado', 'id', 80),
  ]),
  EsquemaAba('Amigos', '#7c3aed', [
    ColunaAba('E-mail', 'texto', 300),
    ColunaAba('Adicionado em', 'data', 130),
    ColunaAba('Modificado', 'id', 80),
  ]),
  EsquemaAba('Radar', '#0891b2', [
    ColunaAba('Ticker', 'negrito', 100),
    ColunaAba('Empresa', 'texto', 300),
    ColunaAba('Adicionado em', 'data', 130),
    ColunaAba('Modificado', 'id', 80),
    ColunaAba('Posição', 'id', 80),
  ]),
  EsquemaAba('Caixa', '#0f766e', [
    ColunaAba('Saldo informado', 'moeda', 150),
    ColunaAba('Data do saldo', 'data', 130),
    ColunaAba('Modificado', 'id', 80),
  ]),
  EsquemaAba('Metas', '#be185d', [
    ColunaAba('ID', 'id', 80),
    ColunaAba('Ticker', 'negrito', 90),
    ColunaAba('Tipo', 'centro', 70),
    ColunaAba('ID compra', 'id', 80),
    ColunaAba('Quantidade', 'inteiro', 100),
    ColunaAba('Preço-alvo', 'moeda', 120),
    ColunaAba('Lucro desejado', 'moeda', 130),
    ColunaAba('Criada em', 'texto', 170),
    ColunaAba('Status', 'centro', 100),
    ColunaAba('Último erro', 'texto', 300),
    ColunaAba('Execução', 'id', 80),
    ColunaAba('Modificado', 'id', 80),
    ColunaAba('Gatilho', 'centro', 90),
    ColunaAba('Detalhes', 'id', 80),
  ]),
  EsquemaAba('Exclusões', '#6b7280', [
    ColunaAba('Tipo', 'texto', 100),
    ColunaAba('Mês', 'centro', 90),
    ColunaAba('ID', 'texto', 280),
    ColunaAba('Excluído em', 'texto', 140),
  ], oculta: true),
];

/// Aba pelo [nome]; `StateError` se não existir (o `KeyError` do Python).
EsquemaAba esquemaDe(String nome) =>
    esquemaAbas.firstWhere((a) => a.nome == nome);
