import { criarRota, depPadrao, json } from '../_lib/http.js';
import { repassar } from '../_lib/repasse.js';

const MAX_BYTES = 4096;
const FORM = 'application/x-www-form-urlencoded';

export function criar(dep) {
  return criarRota(
    {
      limite: 120,
      metodos: {
        POST: async (request) => {
          const tipo = request.headers.get('content-type') ?? '';
          if (!tipo.toLowerCase().startsWith(FORM)) return json(400, { erro: 'tipo' });
          if (Number(request.headers.get('content-length') ?? 0) > MAX_BYTES) {
            return json(400, { erro: 'corpo' });
          }
          const corpo = await request.text();
          if (!corpo.startsWith('f.req=') || Buffer.byteLength(corpo) > MAX_BYTES) {
            return json(400, { erro: 'corpo' });
          }
          return repassar('https://news.google.com/_/DotsSplashUi/data/batchexecute', {
            fetch: dep.fetch,
            metodo: 'POST',
            corpo,
            tipo: FORM,
          });
        },
      },
    },
    dep,
  );
}

export const { GET, POST, OPTIONS } = criar(depPadrao);
