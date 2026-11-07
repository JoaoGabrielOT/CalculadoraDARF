import 'dart:async';

import 'package:calculadoradarf/app/estado/estado_app.dart';
import 'package:calculadoradarf/app/servicos/api.dart';
import 'package:calculadoradarf/app/servicos/eventos.dart';
import 'package:calculadoradarf/nucleo/nucleo.dart';
import 'package:flutter_test/flutter_test.dart';

import '../apoio/plataforma_falsa.dart';
import '../apoio/servicos_falsos.dart';

Future<void> _soltar() => Future<void>.delayed(Duration.zero);

VisaoNoticias _visao({int naoLidas = 0, bool rodando = false}) => VisaoNoticias(
  itens: const [],
  detalhes: const {},
  naoLidas: naoLidas,
  hora: 0,
  lidasAte: 0,
  erros: const {},
  rodando: rodando,
  radar: const [],
);

Future<(EstadoApp, ServicosFalsos, PlataformaFalsa)> _criar({
  bool windows = true,
  bool notificar = true,
}) async {
  final s = ServicosFalsos()
    ..estadoInicial = EstadoInicial(
      mesInicial: '2026-10',
      mesesComDados: const ['2026-10'],
      preferencias: Preferencias(notificarNoticias: notificar),
    );
  final p = PlataformaFalsa(windows: windows);
  final e = EstadoApp(s, p);
  addTearDown(e.dispose);
  await e.iniciar();
  return (e, s, p);
}

void main() {
  group('notificações das notícias', () {
    test('EventoNoticias com notificar e chave ligada chama notificar uma '
        'vez por texto', () async {
      final (_, s, p) = await _criar();
      s.eventosFalsos.add(
        EventoNoticias(_visao(naoLidas: 2), const [
          ('PETR4 · Proventos', 'Texto 1 (Fonte)', 'https://exemplo.com/1'),
          ('VALE3 · Resultado', 'Texto 2', 'https://exemplo.com/2'),
        ]),
      );
      await _soltar();
      expect(p.notificacoes, hasLength(2));
      expect(p.notificacoes[0].titulo, 'PETR4 · Proventos');
      expect(p.notificacoes[0].corpo, 'Texto 1 (Fonte)');
      expect(p.notificacoes[0].link, 'https://exemplo.com/1');
      expect(p.notificacoes[1].link, 'https://exemplo.com/2');
    });

    test('os ids das notificações são sequenciais e não se repetem', () async {
      final (_, s, p) = await _criar();
      s.eventosFalsos.add(
        EventoNoticias(_visao(), const [('A', 'a', 'l1'), ('B', 'b', 'l2')]),
      );
      await _soltar();
      s.eventosFalsos.add(EventoNoticias(_visao(), const [('C', 'c', 'l1')]));
      await _soltar();
      final ids = [for (final n in p.notificacoes) n.id];
      expect(ids, hasLength(3));
      expect(ids[1], ids[0] + 1);
      expect(ids[2], ids[1] + 1);
    });

    test('com a chave desligada não chama notificar', () async {
      final (_, s, p) = await _criar(notificar: false);
      s.eventosFalsos.add(EventoNoticias(_visao(), const [('A', 'a', 'l1')]));
      await _soltar();
      expect(p.notificacoes, isEmpty);
    });

    test('tocar na notificação abre o link', () async {
      final (_, _, p) = await _criar();
      p.tocar('https://exemplo.com/n1');
      await _soltar();
      expect(p.urlsAbertas.single.toString(), 'https://exemplo.com/n1');
    });

    test('ao abrir com a chave ligada no Android pede a permissão', () async {
      final (_, _, p) = await _criar(windows: false);
      expect(p.pedidosPermissao, 1);
    });

    test('no Windows ou com a chave desligada não pede ao abrir', () async {
      final (_, _, pw) = await _criar();
      expect(pw.pedidosPermissao, 0);
      final (_, _, pd) = await _criar(windows: false, notificar: false);
      expect(pd.pedidosPermissao, 0);
    });

    test('ligar a chave pede a permissão no Android', () async {
      final (e, _, p) = await _criar(windows: false, notificar: false);
      await e.definirNotificar(true);
      expect(p.pedidosPermissao, 1);
      await e.definirNotificar(false);
      expect(p.pedidosPermissao, 1);
    });
  });

  group('busca de notícias pelo estado', () {
    test('atualizarNoticias marca a busca em curso e guarda o erro', () async {
      final (e, s, _) = await _criar();
      final espera = Completer<VisaoNoticias>();
      s.atualizarNoticiasFn = (_) => espera.future;
      final f = e.atualizarNoticias(forcar: true);
      expect(e.buscandoNoticias, isTrue);
      espera.completeError(ErroValidacao('sem rede'));
      await f;
      expect(e.buscandoNoticias, isFalse);
      expect(e.erroNoticias, 'Não foi possível buscar notícias: sem rede');
      s.atualizarNoticiasFn = null;
      await e.atualizarNoticias();
      expect(e.erroNoticias, isNull);
      expect(s.chamadas, contains('atualizarNoticias(true)'));
    });

    test('o erro do Python é cortado em 120 caracteres', () async {
      final (e, s, _) = await _criar();
      s.erros['atualizarNoticias'] = ErroValidacao('x' * 200);
      await e.atualizarNoticias();
      expect(e.erroNoticias, 'Não foi possível buscar notícias: ${'x' * 120}');
    });

    test('radarMudou(buscar) busca; sem buscar só avisa a tela', () async {
      final (e, s, _) = await _criar();
      final v0 = e.versaoNoticias;
      e.radarMudou(buscar: false);
      expect(e.versaoNoticias, greaterThan(v0));
      expect(
        s.chamadas.where((c) => c.startsWith('atualizarNoticias')),
        isEmpty,
      );
      e.radarMudou(buscar: true);
      await _soltar();
      expect(s.chamadas, contains('atualizarNoticias(false)'));
    });

    test('EventoNoticias sobe a versão das notícias', () async {
      final (e, s, _) = await _criar();
      final v0 = e.versaoNoticias;
      s.eventosFalsos.add(EventoNoticias(_visao(), const []));
      await _soltar();
      expect(e.versaoNoticias, greaterThan(v0));
    });

    test('marcarNoticiasLidas zera o selo', () async {
      final (e, s, _) = await _criar();
      s.eventosFalsos.add(EventoNoticias(_visao(naoLidas: 3), const []));
      await _soltar();
      expect(e.naoLidas, 3);
      await e.marcarNoticiasLidas();
      expect(e.naoLidas, 0);
      expect(s.chamadas, contains('marcarNoticiasLidas()'));
    });

    test('limparFiltroNoticias apaga o filtro vindo do gráfico', () async {
      final (e, _, _) = await _criar();
      e.verNoticias('WEGE3');
      expect(e.filtroNoticias, 'WEGE3');
      expect(e.aba, Aba.noticias);
      e.limparFiltroNoticias();
      expect(e.filtroNoticias, isNull);
    });
  });
}
