import 'package:collection/collection.dart';

/// Registro com carimbo de modificação (`mod`, epoch em segundos) usado na
/// mesclagem entre aparelhos.
abstract interface class ComMod {
  double get mod;
}

/// `_campos` de nucleo.py:134-135 aplicado aos dois lados: compara sem `mod`,
/// sem `vendas` e sem as chaves de [ignorar].
bool mesmosCampos(
  Map<String, Object?> a,
  Map<String, Object?> b, {
  Set<String> ignorar = const {},
}) {
  Map<String, Object?> campos(Map<String, Object?> x) => {
    for (final e in x.entries)
      if (e.key != 'mod' && e.key != 'vendas' && !ignorar.contains(e.key))
        e.key: e.value,
  };
  return const DeepCollectionEquality().equals(campos(a), campos(b));
}

// Leitura tolerante dos JSON gravados pelo Python: chave ausente ou de outro
// tipo assume o padrão; `int` e `double` valem um pelo outro.

double lerDouble(Object? v, [double padrao = 0.0]) =>
    v is num ? v.toDouble() : padrao;

double? lerDoubleOuNulo(Object? v) => v is num ? v.toDouble() : null;

/// Inteiro; `100.0` vale 100, mas `100.5` é dado corrompido (`FormatException`).
int lerInt(Object? v, [int padrao = 0]) {
  if (v is int) return v;
  if (v is double) {
    if (v.isFinite && v == v.truncate()) return v.truncate();
    throw FormatException('inteiro esperado, recebido $v');
  }
  return padrao;
}

int? lerIntOuNulo(Object? v) => v == null ? null : lerInt(v);

String lerTexto(Object? v, [String padrao = '']) => v is String ? v : padrao;

String? lerTextoOuNulo(Object? v) => v is String ? v : null;

bool lerBool(Object? v, [bool padrao = false]) => v is bool ? v : padrao;

bool? lerBoolOuNulo(Object? v) => v is bool ? v : null;

/// Objeto JSON como mapa novo (cópia profunda); vazio se não for objeto.
Map<String, Object?> lerMapa(Object? v) =>
    v is Map ? copiaProfunda(v)! as Map<String, Object?> : <String, Object?>{};

Map<String, Object?>? lerMapaOuNulo(Object? v) => v is Map ? lerMapa(v) : null;

Map<String, double> lerMapaDouble(Object? v) => {
  if (v is Map)
    for (final e in v.entries)
      if (e.value is num) '${e.key}': (e.value! as num).toDouble(),
};

Map<String, String> lerMapaTexto(Object? v) => {
  if (v is Map)
    for (final e in v.entries)
      if (e.value is String) '${e.key}': e.value! as String,
};

List<Map<String, Object?>> lerLista(Object? v) => [
  if (v is List)
    for (final item in v)
      if (item is Map) lerMapa(item),
];

/// Cópia profunda de JSON (mapas, listas e valores simples).
Object? copiaProfunda(Object? v) {
  if (v is Map) {
    return <String, Object?>{
      for (final e in v.entries) '${e.key}': copiaProfunda(e.value),
    };
  }
  if (v is List) return [for (final e in v) copiaProfunda(e)];
  return v;
}

/// Chaves de [natural] na ordem de [ordem] (a do arquivo lido) e, depois, as
/// que não estavam lá. O Python regrava na ordem de inserção do dicionário.
Map<String, Object?> emOrdem(
  Map<String, Object?> natural,
  List<String>? ordem,
) {
  if (ordem == null) return natural;
  return {
    for (final k in ordem)
      if (natural.containsKey(k)) k: natural[k],
    for (final e in natural.entries)
      if (!ordem.contains(e.key)) e.key: e.value,
  };
}
