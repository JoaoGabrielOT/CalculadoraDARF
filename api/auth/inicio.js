import { createHash, randomBytes } from 'node:crypto';
import { criarRota, depPadrao, json, permitida } from '../_lib/http.js';
import { cifrar } from '../_lib/cifra.js';
import { COOKIE, NONCE, config, origensDeVolta } from '../_lib/oauth.js';

// Os mesmos de escoposGoogle (app/lib/integracoes/google/constantes.dart).
const ESCOPOS = [
  'https://www.googleapis.com/auth/drive.file',
  'https://www.googleapis.com/auth/drive.metadata.readonly',
  'https://www.googleapis.com/auth/spreadsheets.readonly',
];

export function criar(dep) {
  return criarRota(
    {
      limite: 30,
      // Navegação de página inteira: sem Origin.
      exigirOrigem: false,
      metodos: {
        GET: async (request, url) => {
          const cfg = config(dep.env);
          if (!cfg) return json(500, { erro: 'configuracao' });
          const volta = url.searchParams.get('volta') ?? '';
          if (!permitida(volta, origensDeVolta(dep.env))) return json(400, { erro: 'volta' });
          const nonce = url.searchParams.get('n') ?? '';
          if (!NONCE.test(nonce)) return json(400, { erro: 'nonce' });

          const state = randomBytes(16).toString('base64url');
          const verificador = randomBytes(32).toString('base64url');
          const desafio = createHash('sha256').update(verificador).digest('base64url');
          const destino = new URL('https://accounts.google.com/o/oauth2/v2/auth');
          destino.search = new URLSearchParams({
            client_id: cfg.clientId,
            redirect_uri: cfg.retorno,
            response_type: 'code',
            scope: ESCOPOS.join(' '),
            access_type: 'offline',
            prompt: 'consent',
            code_challenge: desafio,
            code_challenge_method: 'S256',
            state,
          }).toString();
          const cookie = cifrar(
            { k: 'cookie', s: state, v: verificador, o: volta, e: dep.agora() + 600_000, n: nonce },
            cfg.chave,
          );
          return new Response(null, {
            status: 302,
            headers: {
              location: destino.toString(),
              'set-cookie': `${COOKIE}=${cookie}; HttpOnly; Secure; SameSite=Lax; Path=/; Max-Age=600`,
              'cache-control': 'no-store',
              'referrer-policy': 'no-referrer',
            },
          });
        },
      },
    },
    dep,
  );
}

export const { GET, POST, OPTIONS } = criar(depPadrao);
