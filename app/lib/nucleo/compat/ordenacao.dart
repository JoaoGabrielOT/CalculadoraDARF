// Ordenação estável como a do `sorted`/`list.sort` do Python. Único lugar do
// núcleo onde `List.sort` é permitido (o do Dart não é estável).

/// Ordena [itens] (cópia) por [comparar], mantendo a ordem original nos
/// empates.
List<T> ordenadoCom<T>(Iterable<T> itens, int Function(T a, T b) comparar) {
  final decorados = [
    for (final (i, item) in itens.indexed) (i, item),
  ];
  decorados.sort((a, b) {
    final c = comparar(a.$2, b.$2);
    return c != 0 ? c : a.$1.compareTo(b.$1);
  });
  return [for (final (_, item) in decorados) item];
}

/// Ordena [itens] por [chave] (tupla do Python: números, textos ou booleanos).
/// Com [reverso], os empates mantêm a ordem original (como `reverse=True`).
List<T> ordenadoPor<T>(
  Iterable<T> itens,
  List<Object> Function(T) chave, {
  bool reverso = false,
}) {
  final decorados = [
    for (final (i, item) in itens.indexed) (i, item, chave(item)),
  ];
  decorados.sort((a, b) {
    final c = compararChaves(a.$3, b.$3);
    if (c != 0) return reverso ? -c : c;
    return a.$1.compareTo(b.$1);
  });
  return [for (final (_, item, _) in decorados) item];
}

/// Compara duas tuplas de chave elemento a elemento; a mais curta vem antes
/// quando uma é prefixo da outra.
int compararChaves(List<Object> a, List<Object> b) {
  final n = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < n; i++) {
    final c = _compararElemento(a[i], b[i]);
    if (c != 0) return c;
  }
  return a.length.compareTo(b.length);
}

num _comoNumero(Object v) => v is bool ? (v ? 1 : 0) : v as num;

int _compararElemento(Object a, Object b) {
  if (a is String && b is String) return _compararTexto(a, b);
  if (a is String || b is String) {
    throw ArgumentError('Chaves incomparáveis: $a e $b');
  }
  final x = _comoNumero(a);
  final y = _comoNumero(b);
  return x < y ? -1 : (x > y ? 1 : 0);
}

/// Compara por ponto de código, como o `str` do Python (não por unidade
/// UTF-16, que inverte a ordem de caracteres fora do plano básico).
int _compararTexto(String a, String b) {
  final ra = a.runes.iterator;
  final rb = b.runes.iterator;
  while (true) {
    final temA = ra.moveNext();
    final temB = rb.moveNext();
    if (!temA || !temB) return temA == temB ? 0 : (temA ? 1 : -1);
    if (ra.current != rb.current) return ra.current.compareTo(rb.current);
  }
}
