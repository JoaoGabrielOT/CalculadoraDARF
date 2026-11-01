// Cache das prévias das matérias (noticias.py:319-337): `noticias_detalhes.json`.

import '../../nucleo/armazenamento.dart';
import '../../nucleo/compat/json_python.dart';
import '../../nucleo/modelos/com_mod.dart';

const arquivoDetalhes = 'noticias_detalhes.json';

/// Prévia de uma matéria: endereço final, imagem e resumo; em falha guarda o
/// [erro] para tentar de novo depois.
class DetalheNoticia {
  DetalheNoticia({
    this.url = '',
    this.img = '',
    this.resumo = '',
    required this.hora,
    this.erro,
  });

  factory DetalheNoticia.fromJson(Map<String, Object?> json) {
    String texto(Object? v) => v is String ? v : '';
    return DetalheNoticia(
      url: texto(json['url']),
      img: texto(json['img']),
      resumo: texto(json['resumo']),
      hora: lerDouble(json['hora']),
      erro: json['erro'] is String ? json['erro'] as String : null,
    );
  }

  String url;
  String img;
  String resumo;
  double hora;
  String? erro;

  Map<String, Object?> toJson() => {
    'url': url,
    'img': img,
    'resumo': resumo,
    'hora': hora,
    if (erro != null) 'erro': erro,
  };
}

/// `ler_detalhes`: arquivo ausente ou ilegível dá `{}`.
Map<String, DetalheNoticia> lerDetalhes(Armazenamento a) {
  final texto = a.ler(arquivoDetalhes);
  if (texto == null) return {};
  try {
    final json = jsonPythonDecode(texto);
    if (json is! Map) return {};
    return {
      for (final e in json.entries)
        if (e.key is String && e.value is Map)
          e.key as String: DetalheNoticia.fromJson(lerMapa(e.value)),
    };
  } on FormatException {
    return {};
  }
}

/// `gravar_detalhes`: com [manter], guarda só esses ids.
void gravarDetalhes(
  Armazenamento a,
  Map<String, DetalheNoticia> det, {
  Set<String>? manter,
}) {
  a.gravar(
    arquivoDetalhes,
    jsonPython({
      for (final e in det.entries)
        if (manter == null || manter.contains(e.key)) e.key: e.value.toJson(),
    }),
  );
}
