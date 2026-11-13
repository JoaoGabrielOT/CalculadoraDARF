import { criarRota, depPadrao, json } from '../_lib/http.js';
import { filtrarParametros, repassar } from '../_lib/repasse.js';

export function criar(dep) {
  return criarRota(
    {
      limite: 120,
      cache: 'public, s-maxage=300, stale-while-revalidate=600',
      metodos: {
        GET: async (request, url, cache) => {
          const consulta = filtrarParametros(url.searchParams, ['q', 'hl', 'gl', 'ceid']);
          if ((consulta.get('q') ?? '').length > 300) return json(400, { erro: 'consulta' });
          return repassar(`https://news.google.com/rss/search?${consulta}`, { fetch: dep.fetch, cache });
        },
      },
    },
    dep,
  );
}

export const { GET, POST, OPTIONS } = criar(depPadrao);
