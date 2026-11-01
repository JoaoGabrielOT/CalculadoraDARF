// HTML das notícias: html.unescape do Python 3.12 e prévia Open Graph
// (noticias.py:363-381).

import '../../nucleo/compat/regex_python.dart';
import 'entidades_html5.dart';

export 'entidades_html5.dart';

// html/__init__.py (Python 3.12): referências numéricas que o HTML5 remapeia.
const _remapeados = <int, String>{
  0x00: '\u{fffd}',
  0x0d: '\r',
  0x80: '\u{20ac}',
  0x81: '\u{81}',
  0x82: '\u{201a}',
  0x83: '\u{192}',
  0x84: '\u{201e}',
  0x85: '\u{2026}',
  0x86: '\u{2020}',
  0x87: '\u{2021}',
  0x88: '\u{2c6}',
  0x89: '\u{2030}',
  0x8a: '\u{160}',
  0x8b: '\u{2039}',
  0x8c: '\u{152}',
  0x8d: '\u{8d}',
  0x8e: '\u{17d}',
  0x8f: '\u{8f}',
  0x90: '\u{90}',
  0x91: '\u{2018}',
  0x92: '\u{2019}',
  0x93: '\u{201c}',
  0x94: '\u{201d}',
  0x95: '\u{2022}',
  0x96: '\u{2013}',
  0x97: '\u{2014}',
  0x98: '\u{2dc}',
  0x99: '\u{2122}',
  0x9a: '\u{161}',
  0x9b: '\u{203a}',
  0x9c: '\u{153}',
  0x9d: '\u{9d}',
  0x9e: '\u{17e}',
  0x9f: '\u{178}',
};

/// `_invalid_codepoints`: viram texto vazio.
bool _pontoInvalido(int n) =>
    (n >= 0x1 && n <= 0x8) ||
    n == 0xb ||
    (n >= 0xe && n <= 0x1f) ||
    (n >= 0x7f && n <= 0x9f) ||
    (n >= 0xfdd0 && n <= 0xfdef) ||
    ((n & 0xfffe) == 0xfffe && n <= 0x10ffff);

final _referencia = RegExp(
  r'&(#[0-9]+;?|#[xX][0-9a-fA-F]+;?|[^\t\n\f <&#;]{1,32};?)',
  unicode: true,
);
final _limiteUnicode = BigInt.from(0x10ffff);

String _trocarReferencia(Match m) {
  final s = m.group(1)!;
  if (s.startsWith('#')) {
    final hex = s[1] == 'x' || s[1] == 'X';
    final corpo = hex ? s.substring(2) : s.substring(1);
    final digitos = corpo.endsWith(';')
        ? corpo.substring(0, corpo.length - 1)
        : corpo;
    final num = BigInt.parse(digitos, radix: hex ? 16 : 10);
    if (num > _limiteUnicode) return '\u{fffd}';
    final n = num.toInt();
    final remapeado = _remapeados[n];
    if (remapeado != null) return remapeado;
    if (n >= 0xd800 && n <= 0xdfff) return '\u{fffd}';
    if (_pontoInvalido(n)) return '';
    return String.fromCharCode(n);
  }
  final direto = entidadesHtml5[s];
  if (direto != null) return direto;
  // A entidade mais longa que casa com um prefixo (como o padrão HTML5).
  final pontos = s.runes.toList();
  for (var x = pontos.length - 1; x > 1; x--) {
    final prefixo = entidadesHtml5[String.fromCharCodes(pontos.take(x))];
    if (prefixo != null) {
      return prefixo + String.fromCharCodes(pontos.skip(x));
    }
  }
  return '&$s';
}

/// `html.unescape` do Python 3.12.
String unescapeHtml(String s) =>
    s.contains('&') ? s.replaceAllMapped(_referencia, _trocarReferencia) : s;

final _tagMeta = erPython(r'<meta\b[^>]*>', ignorarCaixa: true);
final _atributo = erPython(r'''([\w:-]+)\s*=\s*(["'])(?:([^"]*)"|([^']*)')''');
final _espacos = erPython(r'\s+');
final _bordas = RegExp('^[$espacoPython]+|[$espacoPython]+\$', unicode: true);

/// `str.strip()` do Python (espaços Unicode).
String _aparar(String s) => s.replaceAll(_bordas, '');

String _prefixo(String s, int n) {
  final r = s.runes;
  return r.length <= n ? s : String.fromCharCodes(r.take(n));
}

/// `_meta`: valor do primeiro nome de [nomes] presente nas tags `<meta>`.
String metaDe(String html, List<String> nomes) {
  final metas = <String, String>{};
  for (final tag in _tagMeta.allMatches(html)) {
    final attrs = <String, String>{};
    for (final a in _atributo.allMatches(tag.group(0)!)) {
      final valor = a.group(2) == '"' ? a.group(3) : a.group(4);
      attrs[a.group(1)!.toLowerCase()] = valor ?? '';
    }
    final property = attrs['property'] ?? '';
    final chave = (property.isNotEmpty ? property : attrs['name'] ?? '')
        .toLowerCase();
    final content = attrs['content'] ?? '';
    if (chave.isNotEmpty &&
        !metas.containsKey(chave) &&
        _aparar(content).isNotEmpty) {
      metas[chave] = _aparar(unescapeHtml(content));
    }
  }
  for (final n in nomes) {
    final valor = metas[n];
    if (valor != null) return valor;
  }
  return '';
}

/// `urljoin(base, ref)`; referência que o `Uri` não aceita fica como está
/// se começar com http, senão vazia.
String juntarUrl(String base, String ref) {
  try {
    return Uri.parse(base).resolve(ref).toString();
  } on FormatException {
    return ref.startsWith('http') ? ref : '';
  }
}

/// Imagem e resumo que o próprio site publica para prévias (Open Graph e
/// Twitter), lidos só até o primeiro `</head>`.
({String img, String resumo}) lerPrevia(String html, String url) {
  final cabeca = html.split('</head>').first;
  final img = metaDe(cabeca, const [
    'og:image:secure_url',
    'og:image',
    'twitter:image',
    'twitter:image:src',
  ]);
  var desc = metaDe(cabeca, const [
    'og:description',
    'twitter:description',
    'description',
  ]);
  desc = _aparar(desc.replaceAll(_espacos, ' '));
  return (
    img: img.isEmpty ? '' : juntarUrl(url, img),
    resumo: _prefixo(desc, 600),
  );
}
