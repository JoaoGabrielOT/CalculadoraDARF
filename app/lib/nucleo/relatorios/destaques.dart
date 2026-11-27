// Regras puras de destaque do Relatório de Abertura: consenso das casas,
// placar e ordem de exibição (leitura, depois destaques).

import '../compat/ordenacao.dart';
import 'relatorio.dart';

enum Consenso { compra, neutra, venda, dividido, semDados }

final _letra = RegExp(r'\p{L}', unicode: true);

// Termos de recomendação; o booleano dispensa a fronteira de palavra. `neutr`
// é prefixo sem fronteira de propósito (cobre neutra e neutro); "top picks" é
// termo próprio porque o `s` final seria letra depois de "top pick".
const _compra = [
  ('compra', false),
  ('comprar', false),
  ('outperform', false),
  ('overweight', false),
  ('buy', false),
  ('top pick', false),
  ('top picks', false),
  ('acima da média', false),
];
const _venda = [
  ('venda', false),
  ('vender', false),
  ('underperform', false),
  ('underweight', false),
  ('sell', false),
];
const _neutra = [
  ('neutr', true),
  ('manter', false),
  ('manutenção', false),
  ('market perform', false),
  ('hold', false),
  ('in line', false),
];

bool _comeca(String t, List<(String, bool)> termos) {
  for (final (termo, prefixo) in termos) {
    if (!t.startsWith(termo)) continue;
    if (prefixo || t.length == termo.length) return true;
    if (!_letra.hasMatch(t[termo.length])) return true;
  }
  return false;
}

final _formatoPlacar = RegExp(
  r'(?<!\d)(\d{1,6})\s*compra\D+?(\d{1,6})\s*(?:manuten|neutr)\S*\D+?'
  r'(\d{1,6})\s*venda',
);

const _votoCompra = Placar(compra: 1, neutra: 0, venda: 0);
const _votoNeutra = Placar(compra: 0, neutra: 1, venda: 0);
const _votoVenda = Placar(compra: 0, neutra: 0, venda: 1);

/// Placar de um texto: um voto, ou o "N compra / M manutenção / K venda"
/// inteiro; null quando o texto não conta.
Placar? _placarDoTexto(String? recomendacao) {
  if (recomendacao == null) return null;
  final t = recomendacao.trim().toLowerCase();
  final f = _formatoPlacar.firstMatch(t);
  if (f != null) {
    final c = int.tryParse(f[1]!),
        n = int.tryParse(f[2]!),
        v = int.tryParse(f[3]!);
    return c == null || n == null || v == null
        ? null
        : Placar(compra: c, neutra: n, venda: v);
  }
  if (_comeca(t, _compra)) return _votoCompra;
  if (_comeca(t, _venda)) return _votoVenda;
  if (_comeca(t, _neutra)) return _votoNeutra;
  return null;
}

Placar? _placarDoItem(ItemEspecialista i) {
  final c = i.classificacao;
  if (c == null) return _placarDoTexto(i.recomendacao);
  return switch (c) {
    'compra' => _votoCompra,
    'neutra' => _votoNeutra,
    'venda' => _votoVenda,
    _ => null,
  };
}

/// O placar do JSON; senão, o contado pelos itens.
Placar placarDe(Especialistas e) {
  final p = e.placar;
  if (p != null) return p;
  var compra = 0, neutra = 0, venda = 0;
  for (final i in e.itens) {
    final v = _placarDoItem(i);
    if (v == null) continue;
    compra += v.compra;
    neutra += v.neutra;
    venda += v.venda;
  }
  return Placar(compra: compra, neutra: neutra, venda: venda);
}

Consenso _consensoDoPlacar(Placar p) {
  if (p.total == 0) return Consenso.semDados;
  final valores = [p.compra, p.neutra, p.venda];
  final maior = valores.reduce((a, b) => a > b ? a : b);
  if (valores.where((v) => v == maior).length > 1) return Consenso.dividido;
  if (p.compra == maior) return Consenso.compra;
  return p.venda == maior ? Consenso.venda : Consenso.neutra;
}

Consenso consensoDe(Especialistas e) {
  final dado = switch (e.consenso) {
    'compra' => Consenso.compra,
    'neutra' => Consenso.neutra,
    'venda' => Consenso.venda,
    'dividido' => Consenso.dividido,
    'sem_dados' => Consenso.semDados,
    _ => null,
  };
  return dado ?? _consensoDoPlacar(placarDe(e));
}

/// Leitura positiva e consenso de compra.
bool emDestaque(AtivoRelatorio a) =>
    a.leitura == Leitura.positiva &&
    consensoDe(a.especialistas) == Consenso.compra;

/// Leitura na ordem do enum; entre os destaques, maior fração de compra e
/// depois mais casas; o resto mantém a ordem recebida.
List<AtivoRelatorio> ordenarParaExibicao(List<AtivoRelatorio> ativos) {
  // Calculado uma vez por ativo, fora do comparador.
  final info = {
    for (final a in ativos) a: (emDestaque(a), placarDe(a.especialistas)),
  };
  return ordenadoCom(ativos, (a, b) {
    final l = a.leitura.index.compareTo(b.leitura.index);
    if (l != 0) return l;
    final (da, pa) = info[a]!;
    final (db, pb) = info[b]!;
    if (da != db) return da ? -1 : 1;
    if (!da) return 0;
    // Fração compra/total (total 0 vale 0), comparada sem divisão.
    final (na, ta) = pa.total == 0 ? (0, 1) : (pa.compra, pa.total);
    final (nb, tb) = pb.total == 0 ? (0, 1) : (pb.compra, pb.total);
    final f = (nb * ta).compareTo(na * tb);
    return f != 0 ? f : pb.total.compareTo(pa.total);
  });
}
