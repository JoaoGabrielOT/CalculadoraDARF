// Paleta fixa do Relatório de Abertura (a mesma do e-mail): não muda com o
// tema do app. Mais os textos curtos e as peças (selo, variação, link, caixa)
// que a vista, o cartão do ativo e a lista compartilham.

import 'package:flutter/material.dart';

import '../../../nucleo/relatorios/relatorio.dart';
import '../../componentes/cartao.dart' hide Selo;
import '../../componentes/controles.dart' show Selo;
import '../../tema/cores_app.dart';

abstract final class PaletaRelatorio {
  static const positivaTexto = Color(0xFF1B7F3B);
  static const positivaFundo = Color(0xFFE6F4EA);
  static const negativaTexto = Color(0xFFB3261E);
  static const negativaFundo = Color(0xFFFCE8E6);
  static const mistaTexto = Color(0xFFB06000);
  static const mistaFundo = Color(0xFFFEF7E0);
  static const neutraTexto = Color(0xFF5F6368);
  static const neutraFundo = Color(0xFFF1F3F4);

  /// Caixa azul clara (explicação e educação de risco).
  static const azulFundo = Color(0xFFE8F0FE);
  static const azulTexto = Color(0xFF174EA6);

  /// Faixas âmbar de `avisosTopo` e `alertas`.
  static const ambarFundo = Color(0xFFFEF7E0);

  /// Caixa do `aviso` final.
  static const avisoFundo = Color(0xFFFFF4E5);

  /// Texto sobre as caixas de fundo fixo (âmbar e aviso): escuro em qualquer
  /// tema, para não sumir no fundo claro quando o tema é escuro.
  static const textoCaixa = Color(0xFF202124);

  /// Verde da ★ e do realce dos destaques: no tema escuro, um verde claro que
  /// não se perde no fundo.
  static Color verdeDestaque(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF81C995)
      : positivaTexto;

  /// Fundo da linha em destaque: um pouco mais forte no tema escuro.
  static Color fundoDestaque(BuildContext context) => verdeDestaque(context)
      .withValues(
        alpha: Theme.of(context).brightness == Brightness.dark ? 0.2 : 0.12,
      );

  static (Color texto, Color fundo) coresLeitura(Leitura l) => switch (l) {
    Leitura.positiva => (positivaTexto, positivaFundo),
    Leitura.mista => (mistaTexto, mistaFundo),
    Leitura.neutra => (neutraTexto, neutraFundo),
    Leitura.negativa => (negativaTexto, negativaFundo),
  };

  static (Color texto, Color fundo) coresDirecao(Direcao d) => switch (d) {
    Direcao.alta => coresLeitura(Leitura.positiva),
    Direcao.queda => coresLeitura(Leitura.negativa),
    Direcao.neutra => coresLeitura(Leitura.neutra),
  };
}

String rotuloLeitura(Leitura l) => switch (l) {
  Leitura.positiva => 'Positiva',
  Leitura.mista => 'Mista',
  Leitura.neutra => 'Neutra',
  Leitura.negativa => 'Negativa',
};

/// "7 positivas", "1 mista"…, na ordem do termômetro.
String contagemLeitura(Leitura l, int n) =>
    '$n ${rotuloLeitura(l).toLowerCase()}${n == 1 ? '' : 's'}';

String textoTermometro(Termometro t) =>
    [for (final l in Leitura.values) contagemLeitura(l, t.de(l))].join(' · ');

/// Só `http`/`https` com host viram link; o resto aparece como texto.
Uri? linkSeguro(String? url) {
  final u = Uri.tryParse(url?.trim() ?? '');
  if (u == null || !(u.isScheme('http') || u.isScheme('https'))) return null;
  return u.host.isEmpty ? null : u;
}

/// `AAAA-MM-DD` → `DD/MM/AAAA`, `AAAA-MM` → `MM/AAAA`; outro texto fica como
/// veio.
String dataCurta(String s) {
  final m = RegExp(r'^(\d{4})-(\d{2})(?:-(\d{2}))?$').firstMatch(s.trim());
  if (m == null) return s;
  return m[3] == null ? '${m[2]}/${m[1]}' : '${m[3]}/${m[2]}/${m[1]}';
}

/// Junta as partes presentes com " · ".
String juntar(Iterable<String?> partes) => [
  for (final p in partes)
    if (p != null && p.trim().isNotEmpty) p,
].join(' · ');

/// "R$ 3,45 · 25/11/2026"; sem preço, "—".
String textoPreco(Preco? p) =>
    juntar([p?.texto ?? '—', if (p?.data case final d?) dataCurta(d)]);

/// "TTWO (Nasdaq): US$ 216,54 · 18/11/2026".
String textoPrecoExterior(PrecoExterior p) {
  final nome = [?p.ticker, if (p.bolsa case final b?) '($b)'].join(' ');
  final valor = juntar([
    p.texto ?? '—',
    if (p.data case final d?) dataCurta(d),
  ]);
  return nome.isEmpty ? valor : '$nome: $valor';
}

/// "▲ +4,51%" na alta, "▼ -1,78%" na queda, sem seta na neutra.
String textoVariacao(String variacao, Direcao d) => switch (d) {
  Direcao.alta => '▲ $variacao',
  Direcao.queda => '▼ $variacao',
  Direcao.neutra => variacao,
};

/// Selo chapado da leitura na cor da paleta (por padrão, o rótulo).
class SeloLeitura extends StatelessWidget {
  const SeloLeitura(this.leitura, {super.key, this.texto});

  final Leitura leitura;
  final String? texto;

  @override
  Widget build(BuildContext context) {
    // no tema escuro, o texto escuro da paleta some no fundo: valem as cores
    // do tema para alta, aviso, queda e neutro
    final c = CoresApp.de(context);
    final cor = Theme.of(context).brightness == Brightness.dark
        ? switch (leitura) {
            Leitura.positiva => c.alta,
            Leitura.mista => c.aviso,
            Leitura.neutra => c.textoSuave,
            Leitura.negativa => c.queda,
          }
        : PaletaRelatorio.coresLeitura(leitura).$1;
    return Selo(texto: texto ?? rotuloLeitura(leitura), cor: cor);
  }
}

/// Selo "★ Destaque" (leitura positiva com especialistas indicando compra).
class SeloDestaque extends StatelessWidget {
  const SeloDestaque({super.key});

  @override
  Widget build(BuildContext context) =>
      const SeloLeitura(Leitura.positiva, texto: '★ Destaque');
}

/// "2 compra", "1 neutra", "0 venda" em verde, cinza e vermelho da paleta.
class SelosPlacar extends StatelessWidget {
  const SelosPlacar(this.placar, {super.key});

  final Placar placar;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 6,
    runSpacing: 4,
    children: [
      SeloLeitura(Leitura.positiva, texto: '${placar.compra} compra'),
      SeloLeitura(Leitura.neutra, texto: '${placar.neutra} neutra'),
      SeloLeitura(Leitura.negativa, texto: '${placar.venda} venda'),
    ],
  );
}

/// Variação em pílula com a cor e a seta da direção.
class PilulaDirecao extends StatelessWidget {
  const PilulaDirecao(this.variacao, this.direcao, {super.key});

  final String variacao;
  final Direcao direcao;

  @override
  Widget build(BuildContext context) {
    final (cor, fundo) = PaletaRelatorio.coresDirecao(direcao);
    return Pilula(
      texto: textoVariacao(variacao, direcao),
      fundo: fundo,
      cor: cor,
    );
  }
}

/// Texto que abre [url] no navegador quando ela passa por [linkSeguro];
/// senão, só texto.
class LinkRelatorio extends StatelessWidget {
  const LinkRelatorio({
    super.key,
    required this.texto,
    required this.url,
    required this.aoAbrir,
  });

  final String texto;
  final String? url;
  final void Function(Uri) aoAbrir;

  @override
  Widget build(BuildContext context) {
    final uri = linkSeguro(url);
    if (uri == null) return Text(texto, style: const TextStyle(fontSize: 13));
    // Cor do texto do tema com sublinhado: legível nos três temas.
    final c = CoresApp.de(context);
    return Semantics(
      link: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => aoAbrir(uri),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              texto,
              style: TextStyle(
                fontSize: 13,
                color: c.texto,
                decoration: TextDecoration.underline,
                decorationColor: c.textoSuave,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Caixa de fundo fixo da paleta (âmbar, azul, aviso), com a [key] na própria
/// caixa.
Widget caixaRelatorio({
  Key? key,
  required Color fundo,
  required Widget child,
}) => DecoratedBox(
  key: key,
  decoration: BoxDecoration(
    color: fundo,
    borderRadius: BorderRadius.circular(8),
  ),
  child: Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    child: child,
  ),
);
