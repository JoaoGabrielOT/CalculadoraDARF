// Tradução de expressões do `re` do Python 3 para o `RegExp` do Dart.

// `\w`, `\d` e `\s` do `re` do Python 3 (Unicode) e `\b` ao lado deles. O
// `RegExp` do Dart só tem `\b` ASCII, então o `\b` vira uma asserção sobre
// este mesmo conjunto de letras.
const palavraPython = r'\p{L}\p{N}_';
const espacoPython =
    r'\t\n\x0b\x0c\r\x1c-\x1f \x85\xa0  -    '
    r' 　';

/// Traduz uma expressão do `re` do Python para o `RegExp` do Dart
/// (`unicode: true`): `\w \W \d \s \S \b` Unicode e `.` sem casar só `\n`.
RegExp erPython(String padrao, {bool ignorarCaixa = false}) {
  final s = StringBuffer();
  var dentro = false;
  for (var i = 0; i < padrao.length; i++) {
    final c = padrao[i];
    if (c == r'\') {
      final n = padrao[++i];
      switch (n) {
        case 'b':
          // Fronteira de palavra completa (letra de um lado e não de outro),
          // sem depender do que vem antes no padrão.
          s.write(
            '(?:(?<=[$palavraPython])(?![$palavraPython])'
            '|(?<![$palavraPython])(?=[$palavraPython]))',
          );
        case 'd':
          s.write(r'\p{Nd}');
        case 's':
          s.write(dentro ? espacoPython : '[$espacoPython]');
        case 'S':
          s.write('[^$espacoPython]');
        case 'w':
          s.write(dentro ? palavraPython : '[$palavraPython]');
        case 'W':
          s.write('[^$palavraPython]');
        default:
          s.write('\\$n');
      }
      continue;
    }
    if (c == '[') dentro = true;
    if (c == ']') dentro = false;
    s.write(c == '.' && !dentro ? r'[^\n]' : c);
  }
  return RegExp(s.toString(), unicode: true, caseSensitive: !ignorarCaixa);
}
