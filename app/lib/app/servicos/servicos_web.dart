// Serviços da versão Web: rodam na thread da interface (não há isolates), com
// Yahoo, notícias e imagens pelo servidor intermediário, os dados no
// armazenamento recebido e o login pelo servidor. Sem package:flutter.

import 'dart:async';

import 'package:http/http.dart' as http;

import '../../integracoes/integracoes.dart';
import '../../nucleo/nucleo.dart';
import 'api.dart';
import 'locais/noticias_local.dart';
import 'locais/relatorios_local.dart';
import 'servicos_reais.dart';

const _msgNavegador = 'Não foi possível abrir o navegador.';

/// Monta os serviços da Web. [api] é a base do servidor (`.../api`), [origem]
/// o endereço da página (a volta do login) e [irPara] sai da página rumo ao
/// login. Sem atualizador nem backup.
ServicosApp criarServicosWeb({
  required Uri api,
  required Uri origem,
  required Armazenamento armazenamento,
  required Future<void> Function(Uri url) irPara,
  required Future<bool> Function(Uri url) abrirUrl,
  http.Client? cliente,
  bool timers = true,
}) {
  final c = cliente ?? http.Client();
  final pagina = ClienteProxy(c, api: api);
  final imagem = ClienteProxy(c, api: api, livre: DestinoLivre.imagem);
  final cache = CacheBinarioMemoria();
  // o Google é acessado direto (hosts liberados pelo CORS)
  final http30 = ClienteHttp(c, tempoLimite: const Duration(seconds: 30));
  final sessao = SessaoGoogle(
    http: http30,
    armazenamento: armazenamento,
    executar: executarDireto,
    renovar: criarRenovadorWeb(http30, api),
  );
  final google = Google(
    sessao: sessao,
    planilha: PlanilhaGoogle(sessao),
    httpLogin: http30,
    fazerLogin: criarLoginWeb(
      api: api,
      origem: origem,
      irPara: irPara,
      nonces: guardaNonceDoNavegador(),
      armazenamento: armazenamento,
    ),
    aoSair: (t) {
      final pacote = t?.refreshToken;
      if (pacote != null) unawaited(revogarWeb(http30, api, pacote));
    },
  );
  final repo = Repositorio(armazenamento);
  final s = ServicosReais(
    repo: repo,
    yahoo: ServicoYahoo(
      ServicoYahoo.clientePadrao(pagina),
      executar: executarDireto,
    ),
    conta: google,
    abrirUrl: (url) async {
      if (!await abrirUrl(url)) throw ErroGoogle(_msgNavegador);
    },
    noticias: (emitirLocal) => NoticiasLocal(
      repo: repo,
      servico: ServicoNoticias(
        cliente: pagina,
        armazenamento: armazenamento,
        executar: executarDireto,
      ),
      logos: Logos(http: Logos.clientePadrao(imagem), cache: cache),
      cache: cache,
      navegador: Logos.clienteNavegador(imagem),
      emitir: emitirLocal,
    ),
    // o Drive direto com Bearer (a mesma sessão), cache descartável no
    // armazenamento do navegador
    relatorios: () => RelatoriosLocal(
      disco: armazenamento,
      fonte: DriveRelatorios(sessao),
      conta: google,
      limiteConteudo: 5,
    ),
    compartilhamento: DriveCompartilhamento(sessao),
    cliente: c,
  );
  if (timers) {
    s.timers = TimersServicos(
      sync: s.tickSync,
      metas: s.verificacaoAutomatica,
      noticias: s.tickNoticias,
      intervaloSync: intervaloSyncPadrao(windows: false),
    );
  }
  return s;
}
