import { criarRota, depPadrao, json } from '../_lib/http.js';
import { cifrar, decifrar } from '../_lib/cifra.js';
import { URL_TOKEN, config, lerPacote, postarGoogle } from '../_lib/oauth.js';

const SEM_CACHE = { 'cache-control': 'no-store' };

export function criar(dep) {
  return criarRota(
    {
      limite: 30,
      metodos: {
        POST: async (request) => {
          const cfg = config(dep.env);
          if (!cfg) return json(500, { erro: 'configuracao' }, SEM_CACHE);

          let refresh;
          try {
            const sessao = decifrar(await lerPacote(request), cfg.chave);
            refresh = sessao?.k === 'sessao' ? sessao.r : null;
          } catch {
            refresh = null;
          }
          if (typeof refresh !== 'string' || !refresh) return json(401, { erro: 'sessao' }, SEM_CACHE);

          let resposta;
          try {
            resposta = await postarGoogle(dep.fetch, URL_TOKEN, {
              client_id: cfg.clientId,
              client_secret: cfg.segredo,
              refresh_token: refresh,
              grant_type: 'refresh_token',
            });
          } catch {
            return json(503, { erro: 'indisponivel' }, SEM_CACHE);
          }
          const { status, dados } = resposta;
          if (status === 400 || status === 401) return json(401, { erro: 'sessao' }, SEM_CACHE);
          if (status !== 200 || typeof dados?.access_token !== 'string') {
            return json(503, { erro: 'indisponivel' }, SEM_CACHE);
          }
          const saida = { access_token: dados.access_token, expires_in: dados.expires_in };
          if (typeof dados.refresh_token === 'string' && dados.refresh_token) {
            saida.pacote = cifrar({ k: 'sessao', r: dados.refresh_token, t: dep.agora() }, cfg.chave);
          }
          return json(200, saida, SEM_CACHE);
        },
      },
    },
    dep,
  );
}

export const { GET, POST, OPTIONS } = criar(depPadrao);
