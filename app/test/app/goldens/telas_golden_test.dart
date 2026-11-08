// Goldens das cinco abas nos três temas, no PC (1366×768) e no celular
// (360×800). Serviços falsos com os dados de `dados_exemplo.dart`, relógio
// fixo e logos/imagens de notícia gerados aqui como PNGs pequenos.
@Tags(['golden'])
library;

import 'dart:typed_data';

import 'package:calculadoradarf/app/app.dart';
import 'package:calculadoradarf/app/estado/estado_app.dart';
import 'package:calculadoradarf/app/servicos/api.dart';
import 'package:calculadoradarf/app/telas/casca.dart';
import 'package:calculadoradarf/app/tema/tema_visual.dart';
import 'package:calculadoradarf/integracoes/integracoes.dart';
import 'package:calculadoradarf/nucleo/nucleo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';

import '../apoio/dados_exemplo.dart';
import '../apoio/fontes.dart';
import '../apoio/montar.dart';
import '../apoio/servicos_falsos.dart';

const _agora = 1761000000.123;

const _tamanhos = {'pc': Size(1366, 768), 'celular': Size(360, 800)};

const _temas = {
  'terminal': TemaVisual.terminal,
  'claro': TemaVisual.claro,
  'moderno': TemaVisual.moderno,
};

/// PNG quadrado de uma cor só, com um círculo claro no meio (logo falsa).
Uint8List _pngLogo(int r, int g, int b) {
  final im = img.Image(width: 32, height: 32);
  img.fill(im, color: img.ColorRgb8(r, g, b));
  img.fillCircle(
    im,
    x: 16,
    y: 16,
    radius: 9,
    color: img.ColorRgb8(255, 255, 255),
  );
  return img.encodePng(im);
}

/// PNG 16:9 em degradê (foto falsa de notícia).
Uint8List _pngFoto(int r, int g, int b) {
  final im = img.Image(width: 64, height: 36);
  for (var x = 0; x < 64; x++) {
    for (var y = 0; y < 36; y++) {
      final f = (x + y) / 100;
      im.setPixelRgb(
        x,
        y,
        (r * (1 - f)).round(),
        (g * (1 - f)).round(),
        (b * (1 - f)).round(),
      );
    }
  }
  return img.encodePng(im);
}

final _logos = {
  'PETR4': _pngLogo(0, 120, 60),
  'VALE3': _pngLogo(0, 100, 140),
  'WEGE3': _pngLogo(0, 70, 160),
};

DadosAtivo _dados(String ticker, String nome, double preco, double varPct) {
  final variacao = preco * varPct / (100 + varPct);
  const media = 30.0;
  return DadosAtivo(
    ticker: ticker,
    nome: nome,
    preco: preco,
    media6m: media,
    atr: 0.9,
    atrPct: 2.5,
    risco: classificarRisco(2.5),
    variacao: variacao,
    variacaoPct: varPct,
    vsMediaPct: (preco / media - 1) * 100,
  );
}

Grafico _grafico(String ticker, List<double> valores, double referencia) =>
    Grafico(
      ticker: ticker,
      periodo: '1D',
      pontos: [
        for (var i = 0; i < valores.length; i++)
          (1761000000 + i * 600, valores[i]),
      ],
      referencia: referencia,
      desvio: -10800,
      intradiario: true,
    );

Noticia _noticia(
  String id,
  String titulo,
  double idade, {
  List<String> tickers = const [],
  List<String> temas = const [],
  String fonte = 'Fonte A',
}) => Noticia(
  id: id,
  titulo: titulo,
  link: 'https://exemplo.com/$id',
  fonte: fonte,
  fonteUrl: 'https://fonte.example.com',
  data: _agora - idade,
  tickers: tickers,
  temas: temas,
);

DetalheNoticia _detalhe(String id, {bool foto = true, String resumo = ''}) =>
    DetalheNoticia(
      url: 'https://materia.example.com/$id',
      img: foto ? 'https://img.example.com/$id.png' : '',
      resumo: resumo,
      hora: _agora,
    );

/// Outubro de `dados_exemplo` mais operações dos últimos dias, para a Caixa
/// ter liquidações pendentes (hoje é 2026-10-28).
Mes _outubro() {
  final m = mesAbertoExemplo();
  return Mes(
    mes: m.mes,
    lotes: [
      ...m.lotes,
      Lote(
        id: 'L4',
        ticker: 'WEGE3',
        tipo: 'Ação',
        dataCompra: '2026-10-26',
        qtd: 100,
        preco: 40.5,
        vendas: [Venda(id: 'V2', data: '2026-10-28', qtd: 30, preco: 41.2)],
      ),
      Lote(
        id: 'L5',
        ticker: 'ITUB4',
        tipo: 'Ação',
        dataCompra: '2026-10-27',
        qtd: 50,
        preco: 33,
      ),
    ],
  );
}

VisaoCaixa _caixa() {
  final cfg = Config(caixa: Caixa(saldo: 5000, data: '2026-10-01'));
  final meses = {'2026-09': mesFechadoExemplo(), '2026-10': _outubro()};
  final resumo = resumoCaixa(cfg, meses, hoje: hojeExemplo);
  return VisaoCaixa(
    resumo: resumo,
    projecao: projecaoCaixa(resumo, hoje: hojeExemplo),
    agenda: agendaCaixa(resumo, hoje: hojeExemplo),
    hoje: hojeExemplo,
  );
}

ServicosFalsos _servicos() {
  final s = _ServicosGolden()
    ..visoes['2026-10'] = visaoExemplo(_outubro())
    ..visaoCaixa = _caixa()
    ..precos = {
      'PETR4': 36.2,
      'VALE3': 58.4,
      'AAPL34': 57.1,
      'WEGE3': 41.07,
      'ITUB4': 33.4,
    }
    ..metasAtivasFalsas = 2
    ..estadoConta = const EstadoConta(
      email: 'investidor@gmail.com',
      temCredencial: true,
      temToken: true,
      status: StatusSync.ok,
      ultimaSync: _agora - 120,
      linkPlanilha: 'https://docs.google.com/spreadsheets/d/abc',
    )
    ..listaAmigos = [Amigo(email: 'amigo@gmail.com', desde: '2026-09-01')]
    ..cotacoesFalsas = {
      'PETR4': CotacaoOk(_dados('PETR4', 'Petrobras PN', 36.2, 1.85)),
      'WEGE3': CotacaoOk(_dados('WEGE3', 'WEG ON', 41.07, -0.92)),
      'MXRF11': CotacaoOk(_dados('MXRF11', 'Maxi Renda', 9.68, 0.31)),
    }
    ..graficosFalsos = {
      'PETR4': _grafico('PETR4', [35.5, 35.7, 35.6, 35.9, 36.0, 36.2], 35.54),
      'WEGE3': _grafico('WEGE3', [41.4, 41.3, 41.35, 41.1, 41.0, 41.07], 41.45),
      'MXRF11': _grafico('MXRF11', [9.65, 9.66, 9.64, 9.67, 9.66, 9.68], 9.65),
    }
    ..visaoNoticias = VisaoNoticias(
      itens: [
        _noticia(
          'n1',
          'Petrobras anuncia dividendos acima do esperado',
          1800,
          tickers: ['PETR4'],
          temas: ['Dividendos'],
        ),
        _noticia(
          'n2',
          'WEG amplia fábrica e reforça projeção de receita para 2027',
          5400,
          tickers: ['WEGE3'],
          fonte: 'Fonte B',
        ),
        _noticia('n3', 'Copom mantém a Selic', 9000, temas: ['Macro']),
        _noticia(
          'n4',
          'Maxi Renda divulga rendimento mensal',
          14400,
          tickers: ['MXRF11'],
          temas: ['Proventos'],
        ),
        _noticia(
          'n5',
          'Petrobras conclui venda de refinaria no Nordeste',
          30000,
          tickers: ['PETR4'],
          fonte: 'Fonte B',
        ),
      ],
      detalhes: {
        'n1': _detalhe('n1', resumo: 'Conselho aprovou pagamento extra.'),
        'n2': _detalhe('n2', resumo: 'Investimento de R\$ 1 bilhão.'),
        'n3': _detalhe('n3', foto: false),
        'n4': _detalhe('n4', resumo: 'Rendimento de R\$ 0,10 por cota.'),
        'n5': _detalhe('n5', foto: false),
      },
      naoLidas: 2,
      hora: _agora - 300,
      lidasAte: 0,
      erros: const {},
      rodando: false,
      radar: const [
        ('PETR4', 'Petrobras PN'),
        ('WEGE3', 'WEG ON'),
        ('MXRF11', 'Maxi Renda'),
      ],
      novas: const {'n1', 'n2'},
    );
  s.imagemNoticiaFn = (url) async =>
      url.contains('n1') ? _pngFoto(40, 90, 160) : _pngFoto(170, 90, 40);
  s.faviconFn = (_) async => _pngLogo(200, 60, 60);
  return s;
}

/// Os falsos comuns mais as logos.
class _ServicosGolden extends ServicosFalsos {
  @override
  Future<ImagemBytes?> logo(String ticker) async {
    final b = _logos[ticker];
    return b == null ? null : ImagemBytes(bytes: b, svg: false);
  }
}

/// Decodifica as imagens à vista (a decodificação é assíncrona de verdade e
/// não anda no relógio falso do teste).
Future<void> _decodificarImagens(WidgetTester t) async {
  for (var i = 0; i < 2; i++) {
    await t.runAsync(() async {
      for (final e in find.byType(Image).evaluate()) {
        await precacheImage((e.widget as Image).image, e);
      }
    });
    await t.pumpAndSettle();
  }
}

/// Setembro fechado com PETR4 ainda em carteira no último dia do mês.
ServicosFalsos _servicosComPosicao() {
  final s = _servicos();
  s.visoes['2026-09'] = visaoExemplo(
    Mes(
      mes: '2026-09',
      fechado: true,
      lotes: [
        ...mesFechadoExemplo().lotes,
        Lote(
          id: 'F2',
          ticker: 'PETR4',
          tipo: 'Ação',
          dataCompra: '2026-09-10',
          qtd: 100,
          preco: 31.5,
        ),
        Lote(
          id: 'F3',
          ticker: 'VALE3',
          tipo: 'Ação',
          dataCompra: '2026-09-15',
          qtd: 50,
          preco: 59.8,
        ),
      ],
    ),
  );
  return s;
}

void main() {
  setUp(() => ambiente = Ambiente.fixo(hoje: hojeExemplo, agora: _agora));
  tearDown(() => ambiente = Ambiente.sistema());

  // Sem a fonte dos símbolos o grupo é pulado com o motivo (Linux, CI).
  group('telas', skip: motivoParaPularGoldens() ?? false, () {
    // Apuração de um mês fechado: a posição no último dia (padrão) e a
    // carteira atual (lotes do mês aberto) escolhida no seletor.
    for (final carteira in [false, true]) {
      for (final tema in _temas.entries) {
        for (final tamanho in _tamanhos.entries) {
          final nome =
              'apuracao_${carteira ? 'carteira_atual' : 'posicao_historica'}_'
              '${tema.key}_${tamanho.key}';
          testWidgets(nome, (t) async {
            debugDisableShadows = false;
            try {
              await montarApp(
                t,
                servicos: _servicosComPosicao(),
                tema: tema.value,
                tamanho: tamanho.value,
              );
              await t.pumpAndSettle();
              final estado = Provider.of<EstadoApp>(
                t.element(find.byType(Casca)),
                listen: false,
              );
              estado.irPara(Aba.apuracao);
              await t.pumpAndSettle();
              estado.trocarMes('2026-09');
              await t.pumpAndSettle();
              final seletor = find.byKey(const Key('seletor-posicao'));
              for (var i = 0; i < 30 && seletor.evaluate().isEmpty; i++) {
                await t.drag(
                  find.byType(CustomScrollView).first,
                  const Offset(0, -300),
                );
                await t.pumpAndSettle();
              }
              await t.pumpAndSettle();
              if (carteira) {
                await t.tap(find.text('Carteira atual'));
                await t.pumpAndSettle();
              }
              // no celular a lista fica abaixo dos indicadores
              await Scrollable.ensureVisible(
                t.element(seletor),
                alignment: 0.2,
              );
              await _decodificarImagens(t);
              await expectLater(
                find.byKey(chaveCaptura),
                matchesGoldenFile('arquivos/$nome.png'),
              );
            } finally {
              debugDisableShadows = true;
            }
          });
        }
      }
    }

    for (final aba in Aba.values) {
      for (final tema in _temas.entries) {
        for (final tamanho in _tamanhos.entries) {
          final nome = '${aba.name}_${tema.key}_${tamanho.key}';
          testWidgets(nome, (t) async {
            // Sombras de verdade (o padrão do teste troca por um contorno
            // preto); volta antes do fim do corpo, que confere a variável.
            debugDisableShadows = false;
            try {
              await montarApp(
                t,
                servicos: _servicos(),
                tema: tema.value,
                tamanho: tamanho.value,
              );
              await t.pumpAndSettle();
              Provider.of<EstadoApp>(
                t.element(find.byType(Casca)),
                listen: false,
              ).irPara(aba);
              await t.pumpAndSettle();
              await _decodificarImagens(t);
              await expectLater(
                find.byKey(chaveCaptura),
                matchesGoldenFile('arquivos/$nome.png'),
              );
            } finally {
              debugDisableShadows = true;
            }
          });
        }
      }
    }
  });
}
