// Relevância e textos das notícias (noticias.py:17-130, 178-195, 460-470).

// ignore_for_file: implementation_imports
import 'package:unorm_dart/src/uchar.dart' show UChar;
import 'package:unorm_dart/unorm_dart.dart' show nfkd;

import '../ambiente.dart';
import '../apuracao.dart';
import '../compat/numeros.dart';
import '../compat/regex_python.dart';
import '../datas.dart';
import 'estado.dart';

// noticias.py:17-20
const urlRss =
    'https://news.google.com/rss/search?q={q}&hl=pt-BR&gl=BR&ceid=BR:pt-419';
const urlLogoPng =
    'https://raw.githubusercontent.com/thefintz/icones-b3/main/icones/{t}.png';
const urlLogoSvg = 'https://icons.brapi.dev/icons/{t}.svg';
const urlFaviconModelo = 'https://www.google.com/s2/favicons?domain={d}&sz=64';

/// (rótulo exibido, expressões já sem acento e em minúsculas); noticias.py:36-54.
const temasNoticias = <(String, List<String>)>[
  ('Fato relevante', [r'fato relevante', r'comunicado ao mercado']),
  (
    'Resultado',
    [
      r'resultado',
      r'balanco',
      r'lucro',
      r'prejuizo',
      r'ebitda',
      r'receita liquida',
      r'guidance',
      r'\d\s?t\d{2}\b',
      r'trimestre',
    ],
  ),
  (
    'Proventos',
    [
      r'dividendo',
      r'\bjcp\b',
      r'juros sobre (o )?capital',
      r'provento',
      r'data.com',
      r'bonificac',
    ],
  ),
  (
    'Recomendação',
    [
      r'recomendac',
      r'preco.alvo',
      r'rebaix',
      r'eleva .*(recomendac|preco)',
      r'downgrade',
      r'upgrade',
      r'\brating\b',
      r'compra ou venda',
      r'carteira recomendada',
    ],
  ),
  (
    'Fusão/aquisição',
    [
      r'aquisic',
      r'adquir',
      r'fusao',
      r'incorporac',
      r'\bopa\b',
      r'desinvestimento',
      r'venda de (ativo|participac|subsidiaria|refinaria)',
    ],
  ),
  (
    'Oferta/recompra',
    [
      r'recompra',
      r'follow.on',
      r'oferta (publica|subsequente|de acoes)',
      r'\bipo\b',
      r'emissao de (acoes|debentures)',
    ],
  ),
  ('Desdobramento', [r'desdobramento', r'grupamento', r'\bsplit\b', r'inplit']),
  (
    'Governança',
    [
      r'\bceo\b',
      r'presidente',
      r'renuncia',
      r'conselho de administracao',
      r'diretor financeiro',
      r'assembleia',
    ],
  ),
  (
    'Jurídico',
    [
      r'\bcvm\b',
      r'investigac',
      r'\bmulta\b',
      r'recuperacao judicial',
      r'falencia',
      r'\bprocesso\b',
      r'operacao da policia',
    ],
  ),
  (
    'Forte oscilação',
    [
      r'dispara',
      r'desaba',
      r'despenca',
      r'derrete',
      r'salta',
      r'\bdisparam',
      r'tomb[ao]',
      r'maior (alta|queda)',
      r'circuit breaker',
      r'recorde',
    ],
  ),
];

/// Sufixos de razão social ignorados na busca (noticias.py:56-58).
const sufixosNome =
    r'\b(inc|corp|corporation|company|co|ltd|limited|plc|holdings?|group|'
    r's\.?a|sa|nv|ag|se|pfd|on|pn|unt|common stock|class [a-c]|adr|bdr|drn)'
    r'\b\.?';

/// Páginas de cotação sem notícia de fato (noticias.py:92).
const ruido =
    r'cotacao e indicadores|resultados, dividendos, cotacao|^\S+ \(\w+\) - trademap';

final _temas = [
  for (final (rotulo, padroes) in temasNoticias)
    (rotulo, [for (final p in padroes) erPython(p)]),
];
final _sufixosNome = erPython(sufixosNome, ignorarCaixa: true);
final _ruido = erPython(ruido);
final _divisaoNome = erPython(r'\s[-–(]|,');
final _naoNome = erPython(r"[^\w&' .]");
final _espacos = erPython(r'\s+');
final _naoPalavras = erPython(r'\W+');
final _digitoAteFim = erPython(r'\d.*$');
final _palavraSo = RegExp('^[$palavraPython]\$', unicode: true);

/// Primeiros [n] pontos de código (`s[:n]`).
String _prefixo(String s, int n) {
  final r = s.runes;
  return r.length <= n ? s : String.fromCharCodes(r.take(n));
}

/// `s.strip(" .")`.
String _aparar(String s) {
  var i = 0;
  var j = s.length;
  bool borda(String c) => c == ' ' || c == '.';
  while (i < j && borda(s[i])) {
    i++;
  }
  while (j > i && borda(s[j - 1])) {
    j--;
  }
  return s.substring(i, j);
}

/// Classe de combinação canônica (`unicodedata.combining`).
int _combinacao(int ponto) =>
    ponto < 0x300 ? 0 : UChar.fromCharCode(ponto, false)!.getCanonicalClass();

/// NFKD sem os caracteres de combinação, em minúsculas (noticias.py:63-64).
String semAcento(String? s) {
  final saida = StringBuffer();
  for (final ponto in nfkd(s ?? '').runes) {
    if (_combinacao(ponto) == 0) saida.writeCharCode(ponto);
  }
  return _minusculas(saida.toString());
}

// Caracteres ignorados ao decidir se o sigma é final (Case_Ignorable).
final _ignoravel = RegExp(
  r"^[\p{Mn}\p{Me}\p{Cf}\p{Lm}\p{Sk}'.:^`·‘’․‧"
  r'︓﹒﹕＇．：]$',
  unicode: true,
);

bool _comCaixa(int ponto) {
  final c = String.fromCharCode(ponto);
  return c.toLowerCase() != c.toUpperCase();
}

/// `str.lower()`: o `toLowerCase` do Dart não usa o sigma final (ς) que o
/// Python usa no fim de palavra.
String _minusculas(String texto) {
  if (!texto.contains('Σ')) return texto.toLowerCase();
  final pontos = texto.runes.toList();
  final saida = StringBuffer();
  for (var i = 0; i < pontos.length; i++) {
    if (pontos[i] != 0x3a3) {
      saida.write(String.fromCharCode(pontos[i]).toLowerCase());
      continue;
    }
    var j = i - 1;
    while (j >= 0 && _ignoravel.hasMatch(String.fromCharCode(pontos[j]))) {
      j--;
    }
    final depoisDeLetra = j >= 0 && _comCaixa(pontos[j]);
    var k = i + 1;
    while (k < pontos.length &&
        _ignoravel.hasMatch(String.fromCharCode(pontos[k]))) {
      k++;
    }
    final antesDeLetra = k < pontos.length && _comCaixa(pontos[k]);
    saida.write(depoisDeLetra && !antesDeLetra ? 'ς' : 'σ');
  }
  return saida.toString();
}

/// Temas importantes encontrados no título (vazio = notícia comum).
List<String> temas(String titulo) {
  final t = semAcento(titulo);
  return [
    for (final (rotulo, padroes) in _temas)
      if (padroes.any((p) => p.hasMatch(t))) rotulo,
  ];
}

/// Nome curto da empresa para a busca (ex.: 'Apple Inc.' -> 'Apple').
String nomeBusca(String? nome) {
  var n = (nome ?? '').split(_divisaoNome).first;
  n = n.replaceAll(_sufixosNome, ' ');
  n = n.replaceAll(_naoNome, ' ');
  n = _aparar(n.replaceAll(_espacos, ' '));
  return n.runes.length >= 3 ? n : '';
}

/// Ações: só o ticker; BDRs: ticker ou nome da empresa.
String consulta(String ticker, {String nome = ''}) {
  var q = '"$ticker"';
  if (tipoPorTicker(ticker) == 'BDR') {
    final n = nomeBusca(nome);
    if (n.isNotEmpty) q = '($q OR "$n" ações)';
  }
  return '$q when:7d';
}

/// Descarta páginas de cotação e, nos BDRs, matérias que não citam o ticker
/// nem a empresa no título.
bool pertinente(String titulo, String ticker, {String nome = ''}) {
  final t = semAcento(titulo);
  if (_ruido.hasMatch(t) || t.runes.length < 20) return false;
  if (tipoPorTicker(ticker) != 'BDR') return true;
  final n = semAcento(nomeBusca(nome));
  if (t.contains(ticker.toLowerCase())) return true;
  if (n.isEmpty) return false;
  // `\b` + n + `\b`: na borda de um caractere que não é de palavra, o `\b`
  // exige letra do outro lado.
  final primeiro = String.fromCharCode(n.runes.first);
  final ultimo = String.fromCharCode(n.runes.last);
  final antes = _palavraSo.hasMatch(primeiro)
      ? '(?<![$palavraPython])'
      : '(?<=[$palavraPython])';
  final depois = _palavraSo.hasMatch(ultimo)
      ? '(?![$palavraPython])'
      : '(?=[$palavraPython])';
  return RegExp('$antes${RegExp.escape(n)}$depois', unicode: true).hasMatch(t);
}

/// `urlparse(url).netloc.lower()` sem o `www.` inicial; endereço inválido
/// resulta em vazio. Não valida o NFKC do host (noticias.py:178-182).
String dominio(String url) {
  var u = url;
  var i = 0;
  while (i < u.length && (u.codeUnitAt(i) <= 0x20)) {
    i++;
  }
  u = u.substring(i).replaceAll(RegExp('[\t\r\n]'), '');
  final doisPontos = u.indexOf(':');
  if (doisPontos > 0 && RegExp('^[A-Za-z]').hasMatch(u)) {
    if (RegExp(r'^[A-Za-z0-9+.\-]*$').hasMatch(u.substring(0, doisPontos))) {
      u = u.substring(doisPontos + 1);
    }
  }
  var netloc = '';
  if (u.startsWith('//')) {
    var fim = u.length;
    for (final c in ['/', '?', '#']) {
      final p = u.indexOf(c, 2);
      if (p >= 0 && p < fim) fim = p;
    }
    netloc = u.substring(2, fim);
    final abre = netloc.contains('[');
    final fecha = netloc.contains(']');
    if (abre != fecha) return '';
    if (abre && !_hospedeColchetesValido(netloc)) return '';
  }
  final d = netloc.toLowerCase();
  return d.startsWith('www.') ? d.substring(4) : d;
}

/// `_check_bracketed_host` do Python: IPv6 (com escopo opcional) ou IPvFuture.
bool _hospedeColchetesValido(String netloc) {
  final dentro = netloc.split('[').skip(1).join('[').split(']').first;
  if (dentro.startsWith('v')) {
    return RegExp(r'^v[a-fA-F0-9]+\..+$', dotAll: true).hasMatch(dentro);
  }
  final pct = dentro.indexOf('%');
  final endereco = pct < 0 ? dentro : dentro.substring(0, pct);
  if (pct >= 0 && (pct == dentro.length - 1 || dentro.contains('/'))) {
    return false;
  }
  try {
    Uri.parseIPv6Address(endereco);
    return true;
  } on FormatException {
    return false;
  }
}

String urlFavicon(Noticia item) {
  final d = dominio(item.fonteUrl);
  return d.isEmpty ? '' : urlFaviconModelo.replaceAll('{d}', d);
}

/// `int(s // d)` de floats positivos, com o arredondamento do `//` do Python.
int _divisaoInteira(double s, double d) {
  final resto = s % d;
  final div = (s - resto) / d;
  var piso = div.floorToDouble();
  if (div - piso > 0.5) piso += 1.0;
  return piso.toInt();
}

String tempoRelativo(double ts, {double? agora}) {
  final a = (agora == null || agora == 0) ? ambiente.agora() : agora;
  final s = a - ts < 0 ? 0.0 : a - ts;
  if (s < 3600) {
    final min = _divisaoInteira(s, 60);
    return 'há ${min < 1 ? 1 : min} min';
  }
  if (s < 86400) return 'há ${_divisaoInteira(s, 3600)} h';
  final dias = _divisaoInteira(s, 86400);
  if (dias < 7) return dias == 1 ? 'há 1 dia' : 'há $dias dias';
  // fromtimestamp: microssegundos, hora local
  final d = DateTime.fromMillisecondsSinceEpoch(
    arredondar(ts, 6).floor() * 1000,
  );
  return fmtData(isoDeDateTime(d));
}

String chaveTitulo(String titulo) =>
    _prefixo(semAcento(titulo).replaceAll(_naoPalavras, ''), 90);

String iniciais(String ticker) {
  final raiz = _prefixo(ticker.replaceFirst(_digitoAteFim, ''), 4);
  return raiz.isEmpty ? _prefixo(ticker, 4) : raiz;
}

/// PNG do ticker, PNG da raiz (4 letras) e SVG (só o Android exibe SVG).
(List<String>, String) urlsLogo(String ticker) {
  final raiz = iniciais(ticker);
  final png = [urlLogoPng.replaceAll('{t}', ticker)];
  if (raiz != ticker) png.add(urlLogoPng.replaceAll('{t}', raiz));
  return (png, urlLogoSvg.replaceAll('{t}', ticker));
}
