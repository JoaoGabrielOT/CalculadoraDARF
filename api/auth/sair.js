import { criarRota, depPadrao, json } from '../_lib/http.js';
import { decifrar } from '../_lib/cifra.js';
import { URL_REVOGAR, config, lerPacote, postarGoogle } from '../_lib/oauth.js';

export function criar(dep) {
  return criarRota(
    {
      limite: 30,
      metodos: {
        POST: async (request) => {
          const cfg = config(dep.env);
          if (!cfg) return json(500, { erro: 'configuracao' });
          try {
            const sessao = decifrar(await lerPacote(request), cfg.chave);
            const refresh = sessao?.k === 'sessao' ? sessao.r : null;
            if (typeof refresh === 'string' && refresh) {
              await postarGoogle(dep.fetch, URL_REVOGAR, { token: refresh });
            }
          } catch {
            // pacote inválido ou Google fora: a pessoa sai do mesmo jeito
          }
          return new Response(null, { status: 204, headers: { 'cache-control': 'no-store' } });
        },
      },
    },
    dep,
  );
}

export const { GET, POST, OPTIONS } = criar(depPadrao);
