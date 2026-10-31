import 'package:calculadoradarf/nucleo/datas.dart';
import 'package:calculadoradarf/nucleo/modelos/barras.dart';

/// `barras_planas` de tests/test_sugestoes.py: [n] pregões consecutivos
/// terminando em [fim] (sem se preocupar com fins de semana).
List<BarraDiaria> barrasPlanas({
  int n = 30,
  double alta = 11.0,
  double baixa = 9.0,
  double fech = 10.0,
  String fim = '2026-10-28',
}) => [
  for (var i = 0; i < n; i++)
    BarraDiaria(
      data: somarDias(fim, -(n - 1 - i)),
      abre: fech,
      alta: alta,
      baixa: baixa,
      fech: fech,
    ),
];
