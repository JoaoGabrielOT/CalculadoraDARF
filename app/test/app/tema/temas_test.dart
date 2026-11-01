import 'package:calculadoradarf/app/tema/cores_app.dart';
import 'package:calculadoradarf/app/tema/tema_visual.dart';
import 'package:calculadoradarf/app/tema/temas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cores do spec e dos mockups', () {
    final t = temaDe(TemaVisual.terminal).extension<CoresApp>()!;
    expect(t.fundo, const Color(0xFF0D1117));
    expect(t.alta, const Color(0xFF3FB950));
    expect(t.queda, const Color(0xFFF85149));
    final c = temaDe(TemaVisual.claro).extension<CoresApp>()!;
    expect(c.fundo, const Color(0xFFF6F7FB));
    expect(c.cartao, const Color(0xFFFFFFFF));
    expect(
      (c.alta, c.seloAltaFundo),
      (const Color(0xFF14833B), const Color(0xFFE3F6EA)),
    );
    expect(
      (c.queda, c.seloQuedaFundo),
      (const Color(0xFFC62828), const Color(0xFFFDE8E8)),
    );
    final m = temaDe(TemaVisual.moderno).extension<CoresApp>()!;
    expect((m.fundoGradiente as LinearGradient).colors, [
      const Color(0xFF151A2E),
      const Color(0xFF0B0E1A),
    ]);
    expect((m.destaqueGradiente as LinearGradient).colors, [
      const Color(0xFF6C5CE7),
      const Color(0xFF00B894),
    ]);
    expect(
      (m.alta, m.queda),
      (const Color(0xFF55EFC4), const Color(0xFFFF7675)),
    );
  });

  test('demais cores e medidas dos mockups', () {
    final t = temaDe(TemaVisual.terminal).extension<CoresApp>()!;
    expect(t.cartao, const Color(0xFF161B22));
    expect(t.cartaoBorda, const Color(0xFF30363D));
    expect(t.linha, const Color(0xFF21262D));
    expect(t.texto, const Color(0xFFE6EDF3));
    expect(t.textoSuave, const Color(0xFF7D8590));
    expect(t.chipAtivoBorda, const Color(0xFF2EA043));
    expect(t.chipAtivoTexto, const Color(0xFF3FB950));
    expect(t.destaque, const Color(0xFF2EA043));
    expect(t.aviso, const Color(0xFFD29922));
    expect(t.raioCartao, 6);
    expect(t.sombraCartao, isEmpty);
    expect(t.seloAltaFundo.a, 0);
    expect(t.seloQuedaFundo.a, 0);
    expect(t.densa, isTrue);
    final c = temaDe(TemaVisual.claro).extension<CoresApp>()!;
    expect(c.texto, const Color(0xFF1B1F2A));
    expect(c.chipAtivoFundo, const Color(0xFF1B1F2A));
    expect(c.chipAtivoTexto, const Color(0xFFFFFFFF));
    expect(c.raioCartao, 16);
    expect(c.sombraCartao, hasLength(1));
    expect(c.densa, isFalse);
    final m = temaDe(TemaVisual.moderno).extension<CoresApp>()!;
    expect(m.texto, const Color(0xFFF1F3FB));
    expect(m.navAtivo, const Color(0xFFA29BFE));
    expect(m.aviso, const Color(0xFFFDCB6E));
    expect(m.raioCartao, 18);
    expect(m.destaque, const Color(0xFF6C5CE7));
  });

  test('densidade compacta só no Terminal, Material 3 e Roboto', () {
    expect(temaDe(TemaVisual.terminal).visualDensity, VisualDensity.compact);
    expect(
      temaDe(TemaVisual.claro).visualDensity,
      isNot(VisualDensity.compact),
    );
    expect(temaDe(TemaVisual.moderno).useMaterial3, isTrue);
    expect(temaDe(TemaVisual.claro).textTheme.bodyMedium?.fontFamily, 'Roboto');
  });

  test('automático segue o sistema', () {
    expect(
      resolverTema(TemaVisual.automatico, Brightness.light),
      TemaVisual.claro,
    );
    expect(
      resolverTema(TemaVisual.automatico, Brightness.dark),
      TemaVisual.moderno,
    );
    expect(
      resolverTema(TemaVisual.terminal, Brightness.light),
      TemaVisual.terminal,
    );
  });

  test('chave desconhecida vira automático', () {
    expect(TemaVisual.daChave(null), TemaVisual.automatico);
    expect(TemaVisual.daChave('Dark'), TemaVisual.automatico);
    expect(TemaVisual.daChave('moderno'), TemaVisual.moderno);
    expect(TemaVisual.moderno.rotulo, 'Moderno');
    expect(TemaVisual.automatico.rotulo, 'Automático');
    expect(TemaVisual.terminal.chave, 'terminal');
  });

  testWidgets('corVariacao: alta, queda e neutro', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        theme: temaDe(TemaVisual.claro),
        home: Builder(
          builder: (c) {
            ctx = c;
            return const SizedBox();
          },
        ),
      ),
    );
    final cores = CoresApp.de(ctx);
    expect(corVariacao(ctx, 1.5), cores.alta);
    expect(corVariacao(ctx, -0.1), cores.queda);
    expect(corVariacao(ctx, 0), cores.textoSuave);
    expect(corVariacao(ctx, null), cores.textoSuave);
  });
}
