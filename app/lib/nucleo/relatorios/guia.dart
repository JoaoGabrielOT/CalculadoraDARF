// Regras puras do guia dos especialistas (campos opcionais do relatório).

import 'relatorio.dart';

/// A frase sem o trecho final " Motivo: …" quando ele só repete [motivo]
/// (sem diferenciar caixa, espaços nas pontas nem ponto final).
String fraseSemMotivo(String frase, String? motivo) {
  if (motivo == null) return frase;
  final alvo = _semPonto(motivo);
  if (alvo.isEmpty) return frase;
  const marca = 'Motivo: ';
  if (frase.startsWith(marca)) {
    return _semPonto(frase.substring(marca.length)) == alvo ? '' : frase;
  }
  final i = frase.lastIndexOf(' $marca');
  if (i < 0) return frase;
  final resto = frase.substring(i + marca.length + 1);
  return _semPonto(resto) == alvo ? frase.substring(0, i).trimRight() : frase;
}

String _semPonto(String s) {
  var t = s.trim().toLowerCase();
  if (t.endsWith('.')) t = t.substring(0, t.length - 1).trimRight();
  return t;
}

/// Algum ativo traz `guiaLeigo`, `alvoMedio` ou item com `fraseGuia`/`motivo`.
bool temGuia(Relatorio r) => r.ativos.any(
  (a) =>
      a.especialistas.guiaLeigo != null ||
      a.especialistas.alvoMedio != null ||
      a.especialistas.itens.any((i) => i.fraseGuia != null || i.motivo != null),
);
