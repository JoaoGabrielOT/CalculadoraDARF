import { criarRota, depPadrao, json } from '../../_lib/http.js';
import { repassar } from '../../_lib/repasse.js';

export function criar(dep) {
  return criarRota(
    {
      limite: 120,
      cache: 'public, s-maxage=300, stale-while-revalidate=600',
      metodos: {
        GET: async (request, url, cache) => {
          const gid = /\/artigo\/([^/]*)$/.exec(url.pathname)?.[1] ?? '';
          if (!/^[A-Za-z0-9_-]{10,600}$/.test(gid)) return json(400, { erro: 'gid' });
          return repassar(`https://news.google.com/rss/articles/${gid}`, { fetch: dep.fetch, cache });
        },
      },
    },
    dep,
  );
}

export const { GET, POST, OPTIONS } = criar(depPadrao);
