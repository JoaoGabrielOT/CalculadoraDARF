import 'ambiente.dart';
import 'armazenamento.dart';
import 'compat/json_python.dart';
import 'compat/ordenacao.dart';
import 'modelos/com_mod.dart';
import 'modelos/config.dart';
import 'modelos/lote.dart';
import 'modelos/mes.dart';

const _arquivoConfig = 'config.json';

/// Mudanças que não contam como edição do registro (`SEM_CARIMBO`,
/// nucleo.py:190).
const _semCarimbo = {
  'metas': {'niveis', 'stop_atual'},
};

/// `????-??.json` do `glob`.
final _nomeMes = RegExp(r'^.{4}-.{2}\.json$', dotAll: true);

/// Meses e configuração gravados em [armazenamento], com o mesmo layout e o
/// mesmo carimbo de alterações (`mod`, `excluidos`) do Python (nucleo.py).
class Repositorio {
  Repositorio(this.armazenamento);

  final Armazenamento armazenamento;

  String _nomeArquivo(String mes) => '$mes.json';

  Map<String, Object?>? _lerObjeto(String nome) {
    final texto = armazenamento.ler(nome);
    if (texto == null) return null;
    final json = jsonPythonDecode(texto);
    return json is Map ? lerMapa(json) : null;
  }

  bool existeMes(String mes) => armazenamento.existe(_nomeArquivo(mes));

  /// nucleo.py:125-131.
  Mes carregar(String mes) {
    final json = _lerObjeto(_nomeArquivo(mes));
    return json == null ? mesVazio(mes) : Mes.fromJson(json);
  }

  /// Grava o mês. Com [carimbar], marca a hora de alteração do que mudou e
  /// registra o que foi excluído (nucleo.py:138-167).
  void salvar(Mes d, {bool carimbar = true}) {
    if (carimbar) {
      final t = ambiente.agora();
      final bruto = _lerObjeto(_nomeArquivo(d.mes));
      final antigo = bruto == null ? null : Mes.fromJson(bruto);
      if (bruto == null ||
          bruto['fechado'] != d.fechado ||
          bruto['darf_anterior'] != d.darfAnterior) {
        d.mod = t;
      }
      final lotesAnt = {for (final l in antigo?.lotes ?? <Lote>[]) l.id: l};
      final vendasAnt = {
        for (final l in lotesAnt.values)
          for (final v in l.vendas) v.id: v,
      };
      final ids = <String>{};
      for (final l in d.lotes) {
        ids.add(l.id);
        final o = lotesAnt[l.id];
        if (o == null || !mesmosCampos(o.toJson(), l.toJson())) l.mod = t;
        for (final v in l.vendas) {
          ids.add(v.id);
          final ov = vendasAnt[v.id];
          if (ov == null || !mesmosCampos(ov.toJson(), v.toJson())) v.mod = t;
        }
      }
      for (final i in [...lotesAnt.keys, ...vendasAnt.keys]) {
        if (!ids.contains(i)) d.excluidos[i] = t;
      }
    }
    armazenamento.gravar(_nomeArquivo(d.mes), jsonPython(d.toJson()));
  }

  /// Meses gravados (`????-??.json`), em ordem (nucleo.py:170-171).
  List<String> listarMeses() => ordenadoPor([
    for (final nome in armazenamento.listar())
      if (_nomeMes.hasMatch(nome)) nome.substring(0, nome.length - 5),
  ], (m) => [m]);

  /// Primeiro mês aberto; sem nenhum, o mês de hoje (nucleo.py:174-176).
  String mesInicial() {
    for (final m in listarMeses()) {
      if (!carregar(m).fechado) return m;
    }
    return ambiente.hoje().substring(0, 7);
  }

  /// `{mês: Mes}` na ordem de [listarMeses] (metas.py:116-117).
  Map<String, Mes> carregarMeses() => {
    for (final m in listarMeses()) m: carregar(m),
  };

  /// JSON inválido ou ausente vira a configuração padrão (nucleo.py:183-190).
  Config lerConfig() {
    Map<String, Object?>? json;
    try {
      json = _lerObjeto(_arquivoConfig);
    } on FormatException {
      json = null;
    }
    return Config.fromJson(json ?? {});
  }

  /// Grava a configuração. Com [carimbar], marca a hora de alteração dos
  /// amigos, do radar e das metas e registra as exclusões em
  /// `excluidos["<lista>:<chave>"]`. A subida do stop móvel (`niveis` e
  /// `stop_atual`) não carimba (nucleo.py:193-226).
  void gravarConfig(Config cfg, {bool carimbar = true}) {
    if (carimbar) {
      final t = ambiente.agora();
      Config antigo;
      try {
        antigo = Config.fromJson(_lerObjeto(_arquivoConfig) ?? {});
      } on FormatException {
        antigo = Config();
      }
      void carimbarLista<T extends ComMod>(
        String nome,
        List<T> atuais,
        List<T> anteriores,
        String Function(T) chave,
        Map<String, Object?> Function(T) json,
        void Function(T, double) definirMod,
      ) {
        final ignorar = _semCarimbo[nome] ?? const <String>{};
        final ant = {for (final x in anteriores) chave(x): x};
        final presentes = <String>{};
        for (final x in atuais) {
          presentes.add(chave(x));
          final o = ant[chave(x)];
          if (o == null || !mesmosCampos(json(o), json(x), ignorar: ignorar)) {
            definirMod(x, t);
          }
        }
        for (final k in ant.keys) {
          if (!presentes.contains(k)) cfg.excluidos['$nome:$k'] = t;
        }
      }

      carimbarLista<Amigo>(
        'amigos',
        cfg.amigos,
        antigo.amigos,
        (x) => x.email,
        (x) => x.toJson(),
        (x, t) => x.mod = t,
      );
      carimbarLista<ItemRadar>(
        'radar',
        cfg.radar,
        antigo.radar,
        (x) => x.ticker,
        (x) => x.toJson(),
        (x, t) => x.mod = t,
      );
      carimbarLista(
        'metas',
        cfg.metas,
        antigo.metas,
        (x) => x.id,
        (x) => x.toJson(),
        (x, t) => x.mod = t,
      );
    }
    armazenamento.gravar(_arquivoConfig, jsonPython(cfg.toJson()));
  }
}
