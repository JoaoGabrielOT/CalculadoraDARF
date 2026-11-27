// Escolha do relatório a exibir: data pelo nome do arquivo, "hoje" em
// Brasília, ordenação (mais recente primeiro) e data por extenso.

import '../compat/ordenacao.dart';
import '../datas.dart';
import 'relatorio.dart';

final _nomeRelatorio = RegExp(
  r'^relatorio-abertura-(\d{4}-\d{2}-\d{2})\.json$',
);

/// Data (`AAAA-MM-DD`) embutida no nome do arquivo; `null` se o nome não
/// segue o padrão ou a data não existe no calendário.
String? dataDoNome(String nome) {
  final iso = _nomeRelatorio.firstMatch(nome)?.group(1);
  return iso == null || _dataReal(iso) == null ? null : iso;
}

DateTime? _dataReal(String iso) {
  final p = iso.split('-').map(int.parse).toList();
  final d = DateTime.utc(p[0], p[1], p[2]);
  return d.year == p[0] && d.month == p[1] && d.day == p[2] ? d : null;
}

/// Dia atual em Brasília (UTC−3 fixo, como no resto do app).
String hojeBrasilia(DataHora agora) => agora.noFuso(fusoBrasilia).data;

class ResumoRelatorio {
  const ResumoRelatorio({
    required this.nome,
    required this.data,
    this.termometro,
  });
  final String nome;
  final String data;
  final Termometro? termometro;
}

/// Data decrescente; empate por nome decrescente.
List<ResumoRelatorio> ordenarRelatorios(Iterable<ResumoRelatorio> itens) =>
    ordenadoCom(itens, (a, b) {
      final c = compararTexto(b.data, a.data);
      return c != 0 ? c : compararTexto(b.nome, a.nome);
    });

/// O relatório de [hoje], se existir; senão o mais recente. [ordenados] vem
/// de [ordenarRelatorios].
({ResumoRelatorio? escolhido, bool ehHoje}) escolherRelatorio(
  List<ResumoRelatorio> ordenados,
  String hoje,
) {
  for (final r in ordenados) {
    if (r.data == hoje) return (escolhido: r, ehHoje: true);
  }
  return (escolhido: ordenados.isEmpty ? null : ordenados.first, ehHoje: false);
}

const _dias = [
  'segunda-feira',
  'terça-feira',
  'quarta-feira',
  'quinta-feira',
  'sexta-feira',
  'sábado',
  'domingo',
];

const _meses = [
  'janeiro',
  'fevereiro',
  'março',
  'abril',
  'maio',
  'junho',
  'julho',
  'agosto',
  'setembro',
  'outubro',
  'novembro',
  'dezembro',
];

final _iso = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// `'2026-11-26'` -> `'Quinta-feira, 26 de novembro de 2026'`; data inválida
/// volta como veio (a tela nunca trava por ela).
String dataPorExtenso(String iso) {
  final d = _iso.hasMatch(iso) ? _dataReal(iso) : null;
  if (d == null) return iso;
  final texto =
      '${_dias[d.weekday - 1]}, ${d.day} de ${_meses[d.month - 1]} de ${d.year}';
  return texto[0].toUpperCase() + texto.substring(1);
}
