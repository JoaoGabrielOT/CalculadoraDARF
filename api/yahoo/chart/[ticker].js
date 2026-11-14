import { criarRota, depPadrao, json } from '../../_lib/http.js';
import { filtrarParametros, repassar } from '../../_lib/repasse.js';

const PARAMETROS = ['range', 'interval', 'period1', 'period2', 'includePrePost'];

export function criar(dep) {
  return criarRota(
    {
      limite: 240,
      cache: 'public, s-maxage=30, stale-while-revalidate=60',
      metodos: {
        GET: async (request, url, cache) => {
          let ticker = '';
          try {
            ticker = decodeURIComponent(/\/chart\/([^/]*)$/.exec(url.pathname)?.[1] ?? '');
          } catch {
            // ticker malformado: cai na validação abaixo
          }
          if (!/^[A-Z0-9]{1,12}\.SA$/.test(ticker)) return json(400, { erro: 'ticker' });
          const consulta = filtrarParametros(url.searchParams, PARAMETROS).toString();
          const destino = `https://query1.finance.yahoo.com/v8/finance/chart/${ticker}${consulta ? `?${consulta}` : ''}`;
          return repassar(destino, { fetch: dep.fetch, cache });
        },
      },
    },
    dep,
  );
}

export const { GET, POST, OPTIONS } = criar(depPadrao);
