// Leitura do RSS do Google Notícias (noticias.py:133-175, 198-200): XML
// primeiro, expressões regulares se o XML não for bem formado, datas RFC 2822
// e URL de busca. Funções puras: rodam também em `Isolate.run`.

import 'dart:convert';

import 'package:xml/xml.dart';

import '../../nucleo/compat/regex_python.dart';
import '../../nucleo/noticias/estado.dart';
import '../../nucleo/noticias/texto.dart';
import 'html.dart';

// ---------------------------------------------------------------- URL

/// `urllib.parse.quote(s, safe=seguro)`: UTF-8 percentual, sem codificar
/// letras, dígitos, `_.-~` e os ASCII de [seguro]. (O `Uri.encodeComponent`
/// deixa `!*'()` sem codificar; o Python codifica.)
String quotePython(String s, {String seguro = '/'}) {
  final saida = StringBuffer();
  for (final b in utf8.encode(s)) {
    final c = b < 128 ? String.fromCharCode(b) : '';
    final livre =
        (b >= 0x30 && b <= 0x39) ||
        (b >= 0x41 && b <= 0x5a) ||
        (b >= 0x61 && b <= 0x7a) ||
        '_.-~'.contains(c) && c.isNotEmpty ||
        c.isNotEmpty && seguro.contains(c);
    if (livre) {
      saida.writeCharCode(b);
    } else {
      saida.write('%${b.toRadixString(16).toUpperCase().padLeft(2, '0')}');
    }
  }
  return saida.toString();
}

/// URL do RSS de busca do ativo. Montada por `Uri.parse` para não recodificar
/// o que já está em percentual.
Uri urlBusca(String ticker, {String nome = ''}) => Uri.parse(
  urlRss.replaceFirst('{q}', quotePython(consulta(ticker, nome: nome))),
);

// ---------------------------------------------------------------- datas

const _dias = {'mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'};
const _meses = [
  'jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov',
  'dec', //
  'january', 'february', 'march', 'april', 'may', 'june', 'july', 'august',
  'september', 'october', 'november', 'december',
];

// email._parseaddr._timezones
const _fusos = {
  'UT': 0,
  'UTC': 0,
  'GMT': 0,
  'Z': 0,
  'AST': -400,
  'ADT': -300,
  'EST': -500,
  'EDT': -400,
  'CST': -600,
  'CDT': -500,
  'MST': -700,
  'MDT': -600,
  'PST': -800,
  'PDT': -700,
};

final _separador = RegExp('[$espacoPython]+');
final _bordas = RegExp('^[$espacoPython]+|[$espacoPython]+\$', unicode: true);
final _inteiro = RegExp(r'^[+-]?[0-9]+(_[0-9]+)*$');
final _limiteInteiro = BigInt.from(1000000000000000);

/// `str.strip()` do Python (espaços Unicode).
String _aparar(String s) => s.replaceAll(_bordas, '');

/// `int(s)` do Python para texto ASCII (sinal, dígitos e `_` entre dígitos);
/// `null` quando o Python lançaria `ValueError`. Valores acima de 1e15 viram
/// `null` (o Python também falharia adiante, em `datetime`/`timedelta`).
int? _int(String s) {
  if (!_inteiro.hasMatch(s)) return null;
  final n = BigInt.parse(s.replaceAll('_', ''));
  return n.abs() > _limiteInteiro ? null : n.toInt();
}

bool _digito(String c) =>
    c.isNotEmpty && c.compareTo('0') >= 0 && c.compareTo('9') <= 0;

int _diasNoMes(int ano, int mes) {
  const dias = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  final bissexto = ano % 4 == 0 && (ano % 100 != 0 || ano % 400 == 0);
  return mes == 2 && bissexto ? 29 : dias[mes - 1];
}

/// `email.utils.parsedate_to_datetime(texto).timestamp()`: `null` quando o
/// Python lança (`TypeError`/`ValueError`). Sem fuso, ou com `-0000`, vale a
/// hora local do aparelho, como no Python. Limites: dígitos só ASCII (o
/// `int()` do Python aceita outros dígitos Unicode) e fuso numérico gigante
/// vira `null` (o Python lança `OverflowError`).
double? lerDataRfc2822(String texto) {
  if (texto.isEmpty) return null;
  final dados = texto.split(_separador).where((p) => p.isNotEmpty).toList();
  if (dados.isEmpty) return null;
  // O espaço depois da vírgula do dia da semana é opcional.
  if (dados[0].endsWith(',') || _dias.contains(dados[0].toLowerCase())) {
    dados.removeAt(0);
  } else {
    final i = dados[0].lastIndexOf(',');
    if (i >= 0) dados[0] = dados[0].substring(i + 1);
  }
  var partes = dados;
  if (partes.length == 3) {
    final stuff = partes[0].split('-');
    if (stuff.length == 3) partes = [...stuff, ...partes.skip(1)];
  }
  if (partes.length == 4) {
    final s = partes[3];
    var i = s.indexOf('+');
    if (i == -1) i = s.indexOf('-');
    partes = i > 0
        ? [...partes.take(3), s.substring(0, i), s.substring(i)]
        : [...partes, ''];
  }
  if (partes.length < 5) return null;
  var dd = partes[0];
  var mm = partes[1];
  var yy = partes[2];
  var tm = partes[3];
  var tz = partes[4];
  if (dd.isEmpty || mm.isEmpty || yy.isEmpty) return null;
  mm = mm.toLowerCase();
  if (!_meses.contains(mm)) {
    final antigoDd = dd;
    dd = mm;
    mm = antigoDd.toLowerCase();
    if (!_meses.contains(mm)) return null;
  }
  var mes = _meses.indexOf(mm) + 1;
  if (mes > 12) mes -= 12;
  if (dd.endsWith(',')) dd = dd.substring(0, dd.length - 1);
  if (yy.indexOf(':') > 0) {
    final antigoYy = yy;
    yy = tm;
    tm = antigoYy;
  }
  if (yy.endsWith(',')) {
    yy = yy.substring(0, yy.length - 1);
    if (yy.isEmpty) return null;
  }
  if (!_digito(yy[0])) {
    final antigoYy = yy;
    yy = tz;
    tz = antigoYy;
  }
  if (tm.endsWith(',')) tm = tm.substring(0, tm.length - 1);
  String thh;
  String tmm;
  String tss;
  final hm = tm.split(':');
  if (hm.length == 2) {
    thh = hm[0];
    tmm = hm[1];
    tss = '0';
  } else if (hm.length == 3) {
    thh = hm[0];
    tmm = hm[1];
    tss = hm[2];
  } else if (hm.length == 1 && tm.contains('.')) {
    final p = tm.split('.');
    if (p.length == 2) {
      thh = p[0];
      tmm = p[1];
      tss = '0';
    } else if (p.length == 3) {
      thh = p[0];
      tmm = p[1];
      tss = p[2];
    } else {
      return null;
    }
  } else {
    return null;
  }
  var ano = _int(yy);
  final dia = _int(dd);
  final hora = _int(thh);
  final minuto = _int(tmm);
  final segundo = _int(tss);
  if (ano == null ||
      dia == null ||
      hora == null ||
      minuto == null ||
      segundo == null) {
    return null;
  }
  // Ano de dois dígitos: de 69 a 99 é 19xx, de 00 a 68 é 20xx.
  if (ano < 100) ano += ano > 68 ? 1900 : 2000;

  int? deslocamento;
  tz = tz.toUpperCase();
  if (_fusos.containsKey(tz)) {
    deslocamento = _fusos[tz];
  } else {
    deslocamento = _int(tz);
    if (deslocamento == 0 && tz.startsWith('-')) deslocamento = null;
  }
  if (deslocamento != null && deslocamento != 0) {
    final sinal = deslocamento < 0 ? -1 : 1;
    final abs = deslocamento.abs();
    deslocamento = sinal * ((abs ~/ 100) * 3600 + (abs % 100) * 60);
  }

  // Validações do `datetime(...)` e do `timezone(timedelta(...))`.
  if (ano < 1 || ano > 9999 || mes < 1 || mes > 12) return null;
  if (dia < 1 || dia > _diasNoMes(ano, mes)) return null;
  if (hora < 0 || hora > 23 || minuto < 0 || minuto > 59) return null;
  if (segundo < 0 || segundo > 59) return null;
  if (deslocamento != null && deslocamento.abs() >= 86400) return null;

  if (deslocamento == null) {
    return DateTime(
          ano,
          mes,
          dia,
          hora,
          minuto,
          segundo,
        ).millisecondsSinceEpoch /
        1000;
  }
  final utc = DateTime.utc(ano, mes, dia, hora, minuto, segundo);
  return utc.millisecondsSinceEpoch / 1000 - deslocamento;
}

// ---------------------------------------------------------------- RSS

/// (título, link, guid, pubDate, fonte, url da fonte) de cada `<item>`.
typedef _Bruto = (String, String, String, String, String, String);

XmlElement? _filho(XmlElement e, String nome) {
  for (final f in e.childElements) {
    if (_ehNome(f, nome)) return f;
  }
  return null;
}

// O ElementTree só reconhece a tag sem prefixo e sem namespace.
bool _ehNome(XmlElement e, String nome) =>
    e.name.prefix == null &&
    e.name.local == nome &&
    e.name.namespaceUri == null;

/// `Element.text`: o texto antes do primeiro elemento filho (comentários e
/// instruções de processamento não contam).
String _texto(XmlElement? e) {
  if (e == null) return '';
  final s = StringBuffer();
  for (final n in e.children) {
    if (n is XmlElement) break;
    if (n is XmlText || n is XmlCDATA) s.write(n.value);
  }
  return s.toString();
}

List<_Bruto> _itensXml(String texto) {
  // O analisador XML normaliza as quebras de linha na entrada.
  final doc = XmlDocument.parse(
    texto.replaceAll('\r\n', '\n').replaceAll('\r', '\n'),
  );
  final itens = <_Bruto>[];
  for (final it in doc.descendantElements) {
    if (!_ehNome(it, 'item')) continue;
    final f = _filho(it, 'source');
    itens.add((
      _texto(_filho(it, 'title')),
      _texto(_filho(it, 'link')),
      _texto(_filho(it, 'guid')),
      _texto(_filho(it, 'pubDate')),
      _texto(f),
      f?.getAttribute('url') ?? '',
    ));
  }
  return itens;
}

final _fronteira = erPython(r'\b').pattern;
final _blocoItem = RegExp(r'<item>([\s\S]*?)</item>');
final _fonteUrl = RegExp(r'<source[^>]*url="([^"]*)"');
final _cdata = RegExp(r'^<!\[CDATA\[|\]\]>(?=\n?$)');

String _tag(String bloco, RegExp re) {
  final m = re.firstMatch(bloco);
  return m == null ? '' : unescapeHtml(m.group(1)!.replaceAll(_cdata, ''));
}

RegExp _reTag(String nome) =>
    RegExp('<$nome$_fronteira[^>]*>([\\s\\S]*?)</$nome>', unicode: true);

final _reTitle = _reTag('title');
final _reLink = _reTag('link');
final _reGuid = _reTag('guid');
final _rePubDate = _reTag('pubDate');
final _reSource = _reTag('source');

List<_Bruto> _itensRegex(String texto) {
  return [
    for (final b in _blocoItem.allMatches(texto))
      (
        _tag(b.group(1)!, _reTitle),
        _tag(b.group(1)!, _reLink),
        _tag(b.group(1)!, _reGuid),
        _tag(b.group(1)!, _rePubDate),
        _tag(b.group(1)!, _reSource),
        unescapeHtml(_fonteUrl.firstMatch(b.group(1)!)?.group(1) ?? ''),
      ),
  ];
}

List<Noticia> _montar(
  List<_Bruto> brutos,
  String ticker,
  String nome,
  double agora,
) {
  final itens = <Noticia>[];
  for (final (t, l, guid, data, f, fonteUrl) in brutos) {
    var titulo = _aparar(t);
    final link = _aparar(l);
    final fonte = _aparar(f);
    if (titulo.isEmpty || link.isEmpty) continue;
    if (fonte.isNotEmpty && titulo.endsWith(' - $fonte')) {
      titulo = titulo
          .substring(0, titulo.length - fonte.length - 3)
          .replaceAll(RegExp('[$espacoPython]+\$', unicode: true), '');
    }
    if (!pertinente(titulo, ticker, nome: nome)) continue;
    itens.add(
      Noticia(
        id: _aparar(guid.isNotEmpty ? guid : link),
        titulo: titulo,
        link: link,
        fonte: fonte,
        fonteUrl: fonteUrl,
        data: lerDataRfc2822(data) ?? agora,
        tickers: [ticker],
        temas: temas(titulo),
      ),
    );
  }
  return itens;
}

/// Leitura simples por expressões regulares (a do Python sem `pyexpat`).
List<Noticia> lerRssRegex(
  List<int> xml,
  String ticker, {
  String nome = '',
  required double agora,
}) => _montar(
  _itensRegex(utf8.decode(xml, allowMalformed: true)),
  ticker,
  nome,
  agora,
);

/// Itens do RSS do Google Notícias. Lê o XML; se ele não for bem formado, cai
/// na leitura por expressões regulares.
List<Noticia> lerRss(
  List<int> xml,
  String ticker, {
  String nome = '',
  required double agora,
}) {
  final texto = utf8.decode(xml, allowMalformed: true);
  List<_Bruto> brutos;
  try {
    brutos = _itensXml(texto);
  } on XmlException {
    brutos = _itensRegex(texto);
  }
  return _montar(brutos, ticker, nome, agora);
}
