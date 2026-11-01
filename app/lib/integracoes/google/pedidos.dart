// Pedidos da planilha Google montados sem rede (google_sync.py:67-73, 282-441).
// Os corpos são o contrato com a planilha compartilhada com a versão Python:
// precisam ser idênticos aos que o Python monta.

import '../../nucleo/nucleo.dart';

/// `rgb(h)`: `#rrggbb` em componentes de 0 a 1.
Map<String, double> rgb(String hex) {
  final h = hex.startsWith('#') ? hex.substring(1) : hex;
  return {
    'red': int.parse(h.substring(0, 2), radix: 16) / 255,
    'green': int.parse(h.substring(2, 4), radix: 16) / 255,
    'blue': int.parse(h.substring(4, 6), radix: 16) / 255,
  };
}

/// `letra(n)`: `chr(64 + n)`.
String letra(int n) => String.fromCharCode(64 + n);

/// Consulta do Drive da planilha do [dono] (`me` ou e-mail); escapa `\` e `'`.
String consultaPlanilha(String dono) {
  final d = dono.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
  return "name = '$nomePlanilha' and "
      "mimeType = 'application/vnd.google-apps.spreadsheet' "
      "and trashed = false and '$d' in owners";
}

/// `sheets[].properties` devolvido pelo Sheets; [linhas] e [colunas] são
/// `gridProperties.rowCount` e `columnCount` (ausentes quando a API omite).
class PropriedadesAba {
  PropriedadesAba({
    required this.sheetId,
    required this.titulo,
    this.linhas,
    this.colunas,
  });

  final int sheetId;
  final String titulo;
  final int? linhas;
  final int? colunas;
}

Map<String, Object?> _gradeInicial(EsquemaAba aba) => {
  'rowCount': 1000,
  'columnCount': aba.colunas.length,
  'frozenRowCount': 1,
  'hideGridlines': true,
};

/// `criar_planilha` (google_sync.py:300-313): corpo do POST de criação.
Map<String, Object?> corpoCriacao() => {
  'properties': {
    'title': nomePlanilha,
    'locale': 'pt_BR',
    'timeZone': 'America/Sao_Paulo',
  },
  'sheets': [
    for (var i = 0; i < esquemaAbas.length; i++)
      {
        'properties': {
          'title': esquemaAbas[i].nome,
          'index': i,
          'tabColor': rgb(esquemaAbas[i].cor),
          'hidden': esquemaAbas[i].oculta,
          'gridProperties': _gradeInicial(esquemaAbas[i]),
        },
      },
  ],
};

/// `_garantir_abas` (google_sync.py:322-326): `addSheet` das abas que faltam.
Map<String, Object?> pedidoAbasFaltantes(List<String> faltando) => {
  'requests': [
    for (final nome in faltando)
      {
        'addSheet': {
          'properties': {
            'title': nome,
            'tabColor': rgb(esquemaDe(nome).cor),
            'hidden': esquemaDe(nome).oculta,
            'gridProperties': _gradeInicial(esquemaDe(nome)),
          },
        },
      },
  ],
};

/// `_formatar` (google_sync.py:336-392): pedidos de formatação, na ordem de
/// [ids] (`título -> sheetId`).
List<Map<String, Object?>> pedidosFormatacao(Map<String, int> ids) {
  final cabecalho = rgb('#1f2937');
  final reqs = <Map<String, Object?>>[];
  for (final entrada in ids.entries) {
    final g = entrada.value;
    final aba = esquemaDe(entrada.key);
    final n = aba.colunas.length;
    reqs.add({
      'updateCells': {
        'range': {
          'sheetId': g,
          'startRowIndex': 0,
          'endRowIndex': 1,
          'startColumnIndex': 0,
          'endColumnIndex': n,
        },
        'rows': [
          {
            'values': [for (final c in aba.colunas) celula(c.titulo)],
          },
        ],
        'fields': 'userEnteredValue',
      },
    });
    reqs.add({
      'repeatCell': {
        'range': {'sheetId': g, 'startRowIndex': 0, 'endRowIndex': 1},
        'cell': {
          'userEnteredFormat': {
            'backgroundColor': cabecalho,
            'horizontalAlignment': 'CENTER',
            'verticalAlignment': 'MIDDLE',
            'wrapStrategy': 'WRAP',
            'textFormat': {
              'foregroundColor': rgb('#ffffff'),
              'bold': true,
              'fontSize': 10,
            },
          },
        },
        'fields':
            'userEnteredFormat(backgroundColor,horizontalAlignment,'
            'verticalAlignment,wrapStrategy,textFormat)',
      },
    });
    reqs.add({
      'updateDimensionProperties': {
        'range': {
          'sheetId': g,
          'dimension': 'ROWS',
          'startIndex': 0,
          'endIndex': 1,
        },
        'properties': {'pixelSize': 38},
        'fields': 'pixelSize',
      },
    });
    reqs.add({
      'updateDimensionProperties': {
        'range': {'sheetId': g, 'dimension': 'ROWS', 'startIndex': 1},
        'properties': {'pixelSize': 26},
        'fields': 'pixelSize',
      },
    });
    reqs.add({
      'addBanding': {
        'bandedRange': {
          'range': {
            'sheetId': g,
            'startRowIndex': 0,
            'startColumnIndex': 0,
            'endColumnIndex': n,
          },
          'rowProperties': {
            'headerColor': cabecalho,
            'firstBandColor': rgb('#ffffff'),
            'secondBandColor': rgb('#f3f6f9'),
          },
        },
      },
    });
    for (var j = 0; j < n; j++) {
      final coluna = aba.colunas[j];
      final tipo = coluna.tipo;
      final col = {
        'sheetId': g,
        'startRowIndex': 1,
        'startColumnIndex': j,
        'endColumnIndex': j + 1,
      };
      reqs.add({
        'updateDimensionProperties': {
          'range': {
            'sheetId': g,
            'dimension': 'COLUMNS',
            'startIndex': j,
            'endIndex': j + 1,
          },
          'properties': {
            'pixelSize': coluna.largura,
            'hiddenByUser': tipo == 'id',
          },
          'fields': 'pixelSize,hiddenByUser',
        },
      });
      var textFormat = <String, Object?>{'fontSize': 10};
      final fmt = <String, Object?>{
        'verticalAlignment': 'MIDDLE',
        'textFormat': textFormat,
      };
      if (tipo == 'centro') {
        fmt['horizontalAlignment'] = 'CENTER';
      } else if (tipo == 'negrito') {
        textFormat['bold'] = true;
      } else if (tipo == 'data') {
        fmt['numberFormat'] = {'type': 'DATE', 'pattern': 'dd/mm/yyyy'};
        fmt['horizontalAlignment'] = 'CENTER';
      } else if (tipo == 'inteiro') {
        fmt['numberFormat'] = {'type': 'NUMBER', 'pattern': '#,##0'};
        fmt['horizontalAlignment'] = 'RIGHT';
      } else if (tipo == 'moeda' || tipo == 'resultado' || tipo == 'destaque') {
        fmt['numberFormat'] = {'type': 'CURRENCY', 'pattern': '"R\$ "#,##0.00'};
        fmt['horizontalAlignment'] = 'RIGHT';
        if (tipo == 'destaque') {
          textFormat = {
            'fontSize': 10,
            'bold': true,
            'foregroundColor': rgb('#0b8a5f'),
          };
          fmt['textFormat'] = textFormat;
        }
      }
      reqs.add({
        'repeatCell': {
          'range': col,
          'cell': {'userEnteredFormat': fmt},
          'fields':
              'userEnteredFormat(numberFormat,horizontalAlignment,'
              'verticalAlignment,textFormat)',
        },
      });
      if (tipo == 'resultado') {
        for (final (cond, cor) in [
          ('NUMBER_LESS', '#dc2626'),
          ('NUMBER_GREATER', '#0b8a5f'),
        ]) {
          reqs.add({
            'addConditionalFormatRule': {
              'index': 0,
              'rule': {
                'ranges': [col],
                'booleanRule': {
                  'condition': {
                    'type': cond,
                    'values': [
                      {'userEnteredValue': '0'},
                    ],
                  },
                  'format': {
                    'textFormat': {'foregroundColor': rgb(cor)},
                  },
                },
              },
            },
          });
        }
      }
    }
  }
  return reqs;
}

/// `escrever` (google_sync.py:395-425): pedidos que substituem o conteúdo de
/// cada aba de [dados] (exceto o cabeçalho), na ordem de [dados]. [abas] são as
/// propriedades devolvidas por `_garantir_abas`; `rowCount` ausente vale 1000 e
/// `columnCount` ausente vale a largura do esquema.
///
/// Verificação do `escrever` (plano 2): o `updateCells` das linhas não leva
/// `endRowIndex`. A documentação do Sheets diz que o `range` é "the range to
/// write data to" e que, "if the data in rows does not cover the entire
/// requested range, the fields matching those set in fields will be cleared".
/// Assim, quando a planilha encolhe, as linhas que sobram têm só os valores
/// (`userEnteredValue`) das colunas do esquema limpos: nenhuma linha é
/// apagada, as colunas à direita e a formatação ficam como estão.
List<Map<String, Object?>> pedidosEscrita(
  Map<String, PropriedadesAba> abas,
  Map<String, List<Linha>> dados,
) {
  final reqs = <Map<String, Object?>>[];
  for (final entrada in dados.entries) {
    final linhas = entrada.value;
    final p = abas[entrada.key]!;
    final g = p.sheetId;
    final colunas = esquemaDe(entrada.key).colunas;
    final n = colunas.length;
    final total = p.linhas ?? 1000;
    if (linhas.length + 1 > total) {
      reqs.add({
        'appendDimension': {
          'sheetId': g,
          'dimension': 'ROWS',
          'length': linhas.length + 1 - total + 200,
        },
      });
    }
    // planilhas de versões anteriores podem ter menos colunas
    final atuais = p.colunas ?? n;
    if (atuais < n) {
      reqs.add({
        'appendDimension': {
          'sheetId': g,
          'dimension': 'COLUMNS',
          'length': n - atuais,
        },
      });
      for (var j = atuais; j < n; j++) {
        if (colunas[j].tipo == 'id') {
          reqs.add({
            'updateDimensionProperties': {
              'range': {
                'sheetId': g,
                'dimension': 'COLUMNS',
                'startIndex': j,
                'endIndex': j + 1,
              },
              'properties': {'hiddenByUser': true},
              'fields': 'hiddenByUser',
            },
          });
        }
      }
    }
    reqs.add({
      'updateCells': {
        'range': {
          'sheetId': g,
          'startRowIndex': 0,
          'endRowIndex': 1,
          'startColumnIndex': 0,
          'endColumnIndex': n,
        },
        'rows': [
          {
            'values': [for (final c in colunas) celula(c.titulo)],
          },
        ],
        'fields': 'userEnteredValue',
      },
    });
    reqs.add({
      'updateCells': {
        'range': {
          'sheetId': g,
          'startRowIndex': 1,
          'startColumnIndex': 0,
          'endColumnIndex': n,
        },
        'rows': [
          for (final linha in linhas)
            {
              'values': [for (final v in linha) celula(v)],
            },
        ],
        'fields': 'userEnteredValue',
      },
    });
  }
  return reqs;
}

/// `ler` (google_sync.py:427-436): ranges das abas do esquema presentes em
/// [colunasPorAba], na ordem do esquema; `columnCount` ausente (nulo) vale 26.
List<String> rangesLeitura(Map<String, int?> colunasPorAba) => [
  for (final aba in esquemaAbas)
    if (colunasPorAba.containsKey(aba.nome))
      "'${aba.nome}'!A2:"
          '${letra(minPython(aba.colunas.length, colunasPorAba[aba.nome] ?? 26))}',
];
