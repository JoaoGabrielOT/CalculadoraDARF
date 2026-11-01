// Decodificação do link do Google Notícias (noticias.py:21-23, 340-360): o RSS
// só traz um redirecionamento; o endereço real vem de um `batchexecute`.
// Funções puras; os pedidos ficam em `servico.dart`.

import 'dart:convert';

const urlDecodificar =
    'https://news.google.com/_/DotsSplashUi/data/batchexecute';

/// User-Agent das buscas de notícias e dos logos.
const uaNoticias = 'Mozilla/5.0 (CalculadoraDARF)';

/// Cabeçalhos de páginas e imagens (copiados do Python).
const uaNavegador = {
  'User-Agent':
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/130.0 Safari/537.36',
  'Accept-Language': 'pt-BR,pt;q=0.9',
};

final _artigo = RegExp(r'/articles/([^?/#]+)');
final _sg = RegExp(r'data-n-a-sg="([^"]+)"');
final _ts = RegExp(r'data-n-a-ts="([^"]+)"');

/// Id do artigo no link do Google Notícias; `null` se o link é de outro site.
String? idArtigo(String link) {
  final m = _artigo.firstMatch(link);
  if (m == null || !link.contains('news.google.com')) return null;
  return m.group(1);
}

/// `data-n-a-sg` e `data-n-a-ts` da página do artigo; `null` se faltar algum.
({String sg, String ts})? assinaturaArtigo(String pagina) {
  final sg = _sg.firstMatch(pagina);
  final ts = _ts.firstMatch(pagina);
  if (sg == null || ts == null) return null;
  return (sg: sg.group(1)!, ts: ts.group(1)!);
}

/// `json.dumps(texto)` do Python (`ensure_ascii=True`).
String _jsonAscii(String texto) {
  const curtos = {
    0x22: r'\"',
    0x5c: r'\\',
    0x0a: r'\n',
    0x0d: r'\r',
    0x09: r'\t',
    0x08: r'\b',
    0x0c: r'\f',
  };
  final saida = StringBuffer('"');
  for (final u in texto.codeUnits) {
    final curto = curtos[u];
    if (curto != null) {
      saida.write(curto);
    } else if (u < 0x20 || u > 0x7e) {
      saida.write('\\u${u.toRadixString(16).padLeft(4, '0')}');
    } else {
      saida.writeCharCode(u);
    }
  }
  return (saida..write('"')).toString();
}

/// Valor do campo `f.req`: o `json.dumps([[["Fbv4je", interno]]])` do Python.
String corpoDecodificacao(String gid, String ts, String sg) {
  final interno =
      '["garturlreq",[["X","X",["X","X"],null,null,1,1,"US:en",null,1,null,'
      'null,null,null,null,0,1],"X","X",1,[1,1,1],1,1,null,0,0,null,0],'
      '"$gid",$ts,"$sg"]';
  return '[[["Fbv4je", ${_jsonAscii(interno)}]]]';
}

/// Endereço da matéria na resposta do `batchexecute`; `null` se não for um
/// endereço http. Resposta fora do formato lança [FormatException].
String? urlDaRespostaBatch(String texto) {
  final partes = texto.split('\n\n');
  if (partes.length < 2) throw const FormatException('list index out of range');
  final externo = jsonDecode(partes[1]);
  // O Python descarta os dois últimos elementos e usa o primeiro.
  if (externo is! List || externo.length < 3) {
    throw const FormatException('resposta fora do formato');
  }
  final primeiro = externo.first;
  if (primeiro is! List || primeiro.length < 3 || primeiro[2] is! String) {
    throw const FormatException('resposta fora do formato');
  }
  final interno = jsonDecode(primeiro[2] as String);
  if (interno is! List || interno.length < 2) {
    throw const FormatException('resposta fora do formato');
  }
  final url = interno[1];
  return url is String && url.startsWith('http') ? url : null;
}
