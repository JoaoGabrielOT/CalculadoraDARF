import { createHash, timingSafeEqual } from 'node:crypto';
import { criarRota, depPadrao, json, permitida } from '../_lib/http.js';
import { cifrar, decifrar } from '../_lib/cifra.js';
import { COOKIE, NONCE, URL_TOKEN, config, origensDeVolta, postarGoogle } from '../_lib/oauth.js';

const PAGINA_ERRO =
  '<!doctype html><html lang="pt-BR"><head><meta charset="utf-8"><title>Calculadora DARF</title></head>' +
  '<body><p>Login não concluído. Volte para a Calculadora DARF e tente de novo.</p></body></html>';

const COMUNS = {
  'set-cookie': `${COOKIE}=; HttpOnly; Secure; SameSite=Lax; Path=/; Max-Age=0`,
  'cache-control': 'no-store',
  'referrer-policy': 'no-referrer',
  // a página de erro é HTML: não pode ir para dentro de um frame
  'content-security-policy': "frame-ancestors 'none'",
  'x-frame-options': 'DENY',
};

function lerCookie(request) {
  for (const parte of (request.headers.get('cookie') ?? '').split(';')) {
    const i = parte.indexOf('=');
    if (i > 0 && parte.slice(0, i).trim() === COOKIE) return parte.slice(i + 1).trim();
  }
  return null;
}

/** Compara em tempo constante, inclusive quando os tamanhos diferem. */
function iguais(a, b) {
  const ha = createHash('sha256').update(String(a)).digest();
  const hb = createHash('sha256').update(String(b)).digest();
  return timingSafeEqual(ha, hb) && typeof a === 'string' && a.length > 0;
}

const voltar = (sessao, fragmento) =>
  new Response(null, {
    status: 302,
    headers: { location: `${sessao.o}/#${fragmento}&n=${sessao.n}`, ...COMUNS },
  });

const cookieValido = (sessao, env) =>
  sessao?.k === 'cookie' &&
  typeof sessao.o === 'string' &&
  permitida(sessao.o, origensDeVolta(env)) &&
  typeof sessao.n === 'string' &&
  NONCE.test(sessao.n);

export function criar(dep) {
  return criarRota(
    {
      limite: 30,
      // Navegação vinda do Google: sem Origin. A proteção é o state e o cookie de PKCE.
      exigirOrigem: false,
      metodos: {
        GET: async (request, url) => {
          const cfg = config(dep.env);
          if (!cfg) return json(500, { erro: 'configuracao' }, COMUNS);

          let sessao;
          try {
            sessao = decifrar(lerCookie(request), cfg.chave);
          } catch {
            sessao = null;
          }
          if (!cookieValido(sessao, dep.env)) {
            return new Response(PAGINA_ERRO, {
              status: 400,
              headers: { 'content-type': 'text/html; charset=utf-8', ...COMUNS },
            });
          }

          const p = url.searchParams;
          const vencido = !(typeof sessao.e === 'number' && dep.agora() <= sessao.e);
          if (!iguais(sessao.s, p.get('state') ?? '') || vencido) return voltar(sessao, 'auth_erro=estado');
          const erro = p.get('error');
          if (erro) return voltar(sessao, erro === 'access_denied' ? 'auth_erro=acesso_negado' : 'auth_erro=falhou');
          const codigo = p.get('code');
          if (!codigo) return voltar(sessao, 'auth_erro=falhou');

          let refresh = null;
          try {
            const { status, dados } = await postarGoogle(dep.fetch, URL_TOKEN, {
              code: codigo,
              client_id: cfg.clientId,
              client_secret: cfg.segredo,
              redirect_uri: cfg.retorno,
              grant_type: 'authorization_code',
              code_verifier: sessao.v,
            });
            if (status === 200 && typeof dados?.refresh_token === 'string') refresh = dados.refresh_token;
          } catch {
            // rede fora: cai em falhou
          }
          if (!refresh) return voltar(sessao, 'auth_erro=falhou');
          // No fragmento: não vai ao servidor nem aparece em log de acesso.
          return voltar(sessao, `auth=${cifrar({ k: 'sessao', r: refresh, t: dep.agora() }, cfg.chave)}`);
        },
      },
    },
    dep,
  );
}

export const { GET, POST, OPTIONS } = criar(depPadrao);
