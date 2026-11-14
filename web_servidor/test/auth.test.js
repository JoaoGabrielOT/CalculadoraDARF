import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { cifrar, decifrar } from '../api/_lib/cifra.js';
import { criar as criarInicio } from '../api/auth/inicio.js';
import { criar as criarRetorno } from '../api/auth/retorno.js';
import { criar as criarToken } from '../api/auth/token.js';
import { criar as criarSair } from '../api/auth/sair.js';
import { env as envBase, fetchFalso, pedido, ORIGEM } from './auxiliar.js';

// Valores falsos: nenhum segredo real em teste.
const CHAVE = Buffer.alloc(32, 7).toString('base64');
const env = {
  ...envBase,
  GOOGLE_CLIENT_ID: 'id-falso.apps.googleusercontent.com',
  GOOGLE_CLIENT_SECRET: 'segredo-falso',
  CHAVE_PACOTE: CHAVE,
  URL_RETORNO: 'https://calculadora-darf.vercel.app/api/auth/retorno',
};
const AGORA = 1_700_000_000_000;
const agora = () => AGORA;
const RENDER = 'https://calculadora-darf.onrender.com';
const COOKIE = '__Host-darf_oauth';

const dep = (fetch = fetchFalso(200, '{}'), e = env, a = agora) => ({ fetch, env: e, agora: a });

function cookieDe(o = { s: 'estado-1', v: 'verificador-1', o: ORIGEM, e: AGORA + 600_000 }) {
  return `${COOKIE}=${cifrar(o, CHAVE)}`;
}

function retorno(consulta, { cookie = cookieDe(), fetch, a } = {}) {
  const { GET } = criarRetorno(dep(fetch, env, a));
  return GET(pedido(`/api/auth/retorno?${consulta}`, { origem: null, cabecalhos: cookie ? { cookie } : {} }));
}

function cookieApagado(r) {
  const c = r.headers.getSetCookie().find((x) => x.startsWith(`${COOKIE}=`));
  assert.ok(c, 'apaga o cookie');
  assert.match(c, /Max-Age=0/);
}

function cabecalhosDeRetorno(r) {
  assert.equal(r.headers.get('cache-control'), 'no-store');
  assert.equal(r.headers.get('referrer-policy'), 'no-referrer');
  cookieApagado(r);
}

const json = (o) => JSON.stringify(o);

// ---------- inicio ----------

test('inicio com volta fora da lista -> 400', async () => {
  const { GET } = criarInicio(dep());
  const r = await GET(pedido('/api/auth/inicio?volta=https://evil.example', { origem: null }));
  assert.equal(r.status, 400);
  assert.equal(r.headers.get('set-cookie'), null);
});

test('inicio sem volta -> 400', async () => {
  const { GET } = criarInicio(dep());
  const r = await GET(pedido('/api/auth/inicio', { origem: null }));
  assert.equal(r.status, 400);
});

test('inicio válido -> 302 para o Google com PKCE e cookie', async () => {
  const { GET } = criarInicio(dep());
  const r = await GET(pedido(`/api/auth/inicio?volta=${encodeURIComponent(RENDER)}`, { origem: null }));
  assert.equal(r.status, 302);
  const loc = new URL(r.headers.get('location'));
  assert.equal(loc.origin + loc.pathname, 'https://accounts.google.com/o/oauth2/v2/auth');
  const p = loc.searchParams;
  assert.equal(p.get('client_id'), env.GOOGLE_CLIENT_ID);
  assert.equal(p.get('redirect_uri'), env.URL_RETORNO);
  assert.equal(p.get('response_type'), 'code');
  assert.equal(
    p.get('scope'),
    'https://www.googleapis.com/auth/drive.file https://www.googleapis.com/auth/drive.metadata.readonly https://www.googleapis.com/auth/spreadsheets.readonly',
  );
  assert.equal(p.get('access_type'), 'offline');
  assert.equal(p.get('prompt'), 'consent');
  assert.equal(p.get('code_challenge_method'), 'S256');
  assert.equal(p.has('client_secret'), false);
  assert.equal(r.headers.get('location').includes('segredo-falso'), false);
  const state = p.get('state');
  assert.match(state, /^[A-Za-z0-9_-]{22}$/);

  const c = r.headers.get('set-cookie');
  assert.match(c, new RegExp(`^${COOKIE}=v1\\.`));
  for (const attr of ['HttpOnly', 'Secure', 'SameSite=Lax', 'Path=/', 'Max-Age=600']) {
    assert.ok(c.split('; ').includes(attr), attr);
  }
  const conteudo = decifrar(c.split(';')[0].slice(COOKIE.length + 1), CHAVE);
  assert.equal(conteudo.s, state);
  assert.equal(conteudo.o, RENDER);
  assert.equal(conteudo.e, AGORA + 600_000);
  const desafio = createHash('sha256').update(conteudo.v).digest('base64url');
  assert.equal(p.get('code_challenge'), desafio);
});

test('inicio aceita localhost com porta', async () => {
  const { GET } = criarInicio(dep());
  const r = await GET(pedido('/api/auth/inicio?volta=http://localhost:5000', { origem: null }));
  assert.equal(r.status, 302);
});

test('inicio gera state novo a cada chamada', async () => {
  const { GET } = criarInicio(dep());
  const st = async () =>
    new URL((await GET(pedido(`/api/auth/inicio?volta=${ORIGEM}`, { origem: null }))).headers.get('location'))
      .searchParams.get('state');
  assert.notEqual(await st(), await st());
});

test('inicio: limite de 30 por minuto', async () => {
  const { GET } = criarInicio(dep());
  for (let i = 0; i < 30; i++) {
    assert.equal((await GET(pedido(`/api/auth/inicio?volta=${ORIGEM}`, { origem: null }))).status, 302);
  }
  assert.equal((await GET(pedido(`/api/auth/inicio?volta=${ORIGEM}`, { origem: null }))).status, 429);
});

// ---------- retorno ----------

test('retorno sem cookie -> 400 HTML', async () => {
  const r = await retorno('code=c&state=estado-1', { cookie: null });
  assert.equal(r.status, 400);
  assert.match(r.headers.get('content-type'), /^text\/html/);
  assert.match(await r.text(), /Login não concluído\. Volte para a Calculadora DARF e tente de novo\./);
  cabecalhosDeRetorno(r);
});

test('retorno com cookie ilegível -> 400 HTML', async () => {
  const r = await retorno('code=c&state=estado-1', { cookie: `${COOKIE}=v1.lixo` });
  assert.equal(r.status, 400);
  assert.match(await r.text(), /Login não concluído/);
});

test('retorno com cookie cuja origem saiu da lista -> 400 HTML', async () => {
  const cookie = cookieDe({ s: 'estado-1', v: 'v', o: 'https://evil.example', e: AGORA + 600_000 });
  const r = await retorno('code=c&state=estado-1', { cookie });
  assert.equal(r.status, 400);
});

test('retorno funciona sem Origin (navegação vinda do Google)', async () => {
  const f = fetchFalso(200, json({ access_token: 'at', refresh_token: 'rt-1' }));
  const r = await retorno('code=c&state=estado-1', { fetch: f });
  assert.equal(r.status, 302);
});

test('retorno com state diferente -> volta com auth_erro=estado', async () => {
  const f = fetchFalso(200, '{}');
  const cookie = cookieDe({ s: 'estado-1', v: 'v', o: RENDER, e: AGORA + 600_000 });
  const r = await retorno('code=c&state=estado-2', { cookie, fetch: f });
  assert.equal(r.status, 302);
  assert.equal(r.headers.get('location'), 'https://calculadora-darf.onrender.com/#auth_erro=estado');
  assert.equal(f.chamadas.length, 0);
  cabecalhosDeRetorno(r);
});

test('retorno sem state -> auth_erro=estado', async () => {
  const r = await retorno('code=c');
  assert.equal(r.headers.get('location'), `${ORIGEM}/#auth_erro=estado`);
});

test('retorno com cookie vencido -> auth_erro=estado', async () => {
  const f = fetchFalso(200, json({ refresh_token: 'rt-1' }));
  const r = await retorno('code=c&state=estado-1', { fetch: f, a: () => AGORA + 11 * 60_000 });
  assert.equal(r.headers.get('location'), `${ORIGEM}/#auth_erro=estado`);
  assert.equal(f.chamadas.length, 0);
});

test('retorno com error=access_denied -> auth_erro=acesso_negado', async () => {
  const r = await retorno('error=access_denied&state=estado-1');
  assert.equal(r.headers.get('location'), `${ORIGEM}/#auth_erro=acesso_negado`);
  cabecalhosDeRetorno(r);
});

test('retorno com outro error -> auth_erro=falhou', async () => {
  const r = await retorno('error=server_error&state=estado-1');
  assert.equal(r.headers.get('location'), `${ORIGEM}/#auth_erro=falhou`);
});

test('retorno com sucesso troca o código e devolve o pacote no fragmento', async () => {
  const f = fetchFalso(200, json({ access_token: 'at', refresh_token: 'rt-1', expires_in: 3599 }));
  const r = await retorno('code=codigo-1&state=estado-1', { fetch: f });
  assert.equal(r.status, 302);
  assert.equal(f.chamadas.length, 1);
  const ch = f.chamadas[0];
  assert.equal(ch.url, 'https://oauth2.googleapis.com/token');
  assert.equal(ch.method, 'POST');
  const corpo = new URLSearchParams(ch.body);
  assert.equal(corpo.get('code'), 'codigo-1');
  assert.equal(corpo.get('client_id'), env.GOOGLE_CLIENT_ID);
  assert.equal(corpo.get('client_secret'), 'segredo-falso');
  assert.equal(corpo.get('redirect_uri'), env.URL_RETORNO);
  assert.equal(corpo.get('grant_type'), 'authorization_code');
  assert.equal(corpo.get('code_verifier'), 'verificador-1');

  const loc = r.headers.get('location');
  assert.ok(loc.startsWith('https://calculadora-darf.vercel.app/#auth=v1.'), loc);
  assert.equal(new URL(loc).search, '');
  const pacote = decifrar(loc.slice(loc.indexOf('#auth=') + 6), CHAVE);
  assert.equal(pacote.r, 'rt-1');
  assert.equal(pacote.t, AGORA);
  assert.equal(loc.includes('segredo-falso'), false);
  cabecalhosDeRetorno(r);
});

test('retorno sem refresh_token na troca -> auth_erro=falhou', async () => {
  const f = fetchFalso(200, json({ access_token: 'at' }));
  const r = await retorno('code=c&state=estado-1', { fetch: f });
  assert.equal(r.headers.get('location'), `${ORIGEM}/#auth_erro=falhou`);
});

test('retorno com Google 400 ou rede fora -> auth_erro=falhou', async () => {
  let r = await retorno('code=c&state=estado-1', { fetch: fetchFalso(400, json({ error: 'invalid_grant' })) });
  assert.equal(r.headers.get('location'), `${ORIGEM}/#auth_erro=falhou`);
  r = await retorno('code=c&state=estado-1', {
    fetch: async () => {
      throw new Error('rede');
    },
  });
  assert.equal(r.headers.get('location'), `${ORIGEM}/#auth_erro=falhou`);
});

test('retorno sem code -> auth_erro=falhou', async () => {
  const f = fetchFalso(200, json({ refresh_token: 'rt-1' }));
  const r = await retorno('state=estado-1', { fetch: f });
  assert.equal(r.headers.get('location'), `${ORIGEM}/#auth_erro=falhou`);
  assert.equal(f.chamadas.length, 0);
});

// ---------- token ----------

const pacoteOk = () => cifrar({ r: 'rt-1', t: AGORA }, CHAVE);
const postar = (rota, corpo, opcoes = {}) =>
  rota.POST(pedido('/api/auth/token', { metodo: 'POST', corpo, tipo: 'application/json', ...opcoes }));

test('token com pacote válido -> 200 com access_token', async () => {
  const f = fetchFalso(200, json({ access_token: 'at', expires_in: 3599, scope: 'x', token_type: 'Bearer' }));
  const r = await postar(criarToken(dep(f)), json({ pacote: pacoteOk() }));
  assert.equal(r.status, 200);
  assert.deepEqual(await r.json(), { access_token: 'at', expires_in: 3599 });
  assert.equal(r.headers.get('cache-control'), 'no-store');
  assert.equal(r.headers.get('access-control-allow-origin'), ORIGEM);
  const ch = f.chamadas[0];
  assert.equal(ch.url, 'https://oauth2.googleapis.com/token');
  const corpo = new URLSearchParams(ch.body);
  assert.equal(corpo.get('grant_type'), 'refresh_token');
  assert.equal(corpo.get('refresh_token'), 'rt-1');
  assert.equal(corpo.get('client_id'), env.GOOGLE_CLIENT_ID);
  assert.equal(corpo.get('client_secret'), 'segredo-falso');
});

test('token: Google devolve refresh_token novo -> pacote novo', async () => {
  const f = fetchFalso(200, json({ access_token: 'at', expires_in: 3599, refresh_token: 'rt-2' }));
  const r = await postar(criarToken(dep(f)), json({ pacote: pacoteOk() }));
  const dados = await r.json();
  assert.equal(dados.access_token, 'at');
  assert.equal(decifrar(dados.pacote, CHAVE).r, 'rt-2');
  assert.equal(JSON.stringify(dados).includes('rt-2'), false);
});

test('token: Google 400 invalid_grant ou 401 -> 401 sessao', async () => {
  for (const status of [400, 401]) {
    const f = fetchFalso(status, json({ error: 'invalid_grant', error_description: 'detalhe' }));
    const r = await postar(criarToken(dep(f)), json({ pacote: pacoteOk() }));
    assert.equal(r.status, 401);
    assert.deepEqual(await r.json(), { erro: 'sessao' });
    assert.equal(r.headers.get('cache-control'), 'no-store');
  }
});

test('token: Google 503, 429 ou rede -> 503 indisponivel', async () => {
  for (const f of [
    fetchFalso(503, ''),
    fetchFalso(429, ''),
    async () => {
      throw new Error('rede');
    },
  ]) {
    const r = await postar(criarToken(dep(f)), json({ pacote: pacoteOk() }));
    assert.equal(r.status, 503);
    assert.deepEqual(await r.json(), { erro: 'indisponivel' });
  }
});

test('token: pacote adulterado, ausente ou corpo inválido -> 401 sem chamar o Google', async () => {
  const p = pacoteOk();
  const adulterado = p.slice(0, 10) + (p[10] === 'A' ? 'B' : 'A') + p.slice(11);
  for (const corpo of [json({ pacote: adulterado }), json({}), 'não json', json({ pacote: 5 })]) {
    const f = fetchFalso(200, json({ access_token: 'at' }));
    const r = await postar(criarToken(dep(f)), corpo);
    assert.equal(r.status, 401, corpo);
    assert.deepEqual(await r.json(), { erro: 'sessao' });
    assert.equal(f.chamadas.length, 0);
  }
});

test('token: origem estranha -> 403', async () => {
  const f = fetchFalso(200, '{}');
  const r = await postar(criarToken(dep(f)), json({ pacote: pacoteOk() }), { origem: 'https://evil.example' });
  assert.equal(r.status, 403);
  assert.equal(f.chamadas.length, 0);
});

test('token: limite de 30 por minuto', async () => {
  const rota = criarToken(dep(fetchFalso(200, json({ access_token: 'at', expires_in: 1 }))));
  for (let i = 0; i < 30; i++) assert.equal((await postar(rota, json({ pacote: pacoteOk() }))).status, 200);
  assert.equal((await postar(rota, json({ pacote: pacoteOk() }))).status, 429);
});

// ---------- sair ----------

test('sair revoga o refresh token e responde 204', async () => {
  const f = fetchFalso(200, '');
  const r = await criarSair(dep(f)).POST(
    pedido('/api/auth/sair', { metodo: 'POST', corpo: json({ pacote: pacoteOk() }), tipo: 'application/json' }),
  );
  assert.equal(r.status, 204);
  assert.equal(f.chamadas.length, 1);
  assert.equal(f.chamadas[0].url, 'https://oauth2.googleapis.com/revoke');
  assert.equal(f.chamadas[0].method, 'POST');
  assert.equal(String(f.chamadas[0].body), 'token=rt-1');
});

test('sair com pacote inválido ou Google fora -> 204', async () => {
  const f = fetchFalso(200, '');
  let r = await criarSair(dep(f)).POST(
    pedido('/api/auth/sair', { metodo: 'POST', corpo: json({ pacote: 'v1.x' }), tipo: 'application/json' }),
  );
  assert.equal(r.status, 204);
  assert.equal(f.chamadas.length, 0);
  r = await criarSair(
    dep(async () => {
      throw new Error('rede');
    }),
  ).POST(pedido('/api/auth/sair', { metodo: 'POST', corpo: json({ pacote: pacoteOk() }), tipo: 'application/json' }));
  assert.equal(r.status, 204);
});

test('sair: origem estranha -> 403', async () => {
  const r = await criarSair(dep()).POST(
    pedido('/api/auth/sair', { metodo: 'POST', corpo: json({ pacote: pacoteOk() }), origem: 'https://evil.example' }),
  );
  assert.equal(r.status, 403);
});

// ---------- configuração ----------

for (const falta of ['CHAVE_PACOTE', 'GOOGLE_CLIENT_ID', 'GOOGLE_CLIENT_SECRET', 'URL_RETORNO', 'ORIGENS_PERMITIDAS']) {
  test(`env sem ${falta} -> 500 configuracao`, async () => {
    const e = { ...env };
    delete e[falta];
    const volta = falta === 'ORIGENS_PERMITIDAS' ? 'http://localhost:5000' : ORIGEM;
    const respostas = [
      await criarInicio(dep(undefined, e)).GET(pedido(`/api/auth/inicio?volta=${volta}`, { origem: null })),
      await criarRetorno(dep(undefined, e)).GET(
        pedido('/api/auth/retorno?code=c&state=estado-1', { origem: null, cabecalhos: { cookie: cookieDe() } }),
      ),
      await postar(criarToken(dep(undefined, e)), json({ pacote: pacoteOk() }), { origem: volta }),
      await criarSair(dep(undefined, e)).POST(
        pedido('/api/auth/sair', { metodo: 'POST', corpo: json({ pacote: pacoteOk() }), origem: volta }),
      ),
    ];
    for (const r of respostas) {
      assert.equal(r.status, 500);
      assert.deepEqual(await r.json(), { erro: 'configuracao' });
    }
  });
}

test('CHAVE_PACOTE que não tem 32 bytes -> 500 configuracao', async () => {
  const e = { ...env, CHAVE_PACOTE: Buffer.alloc(16).toString('base64') };
  const r = await criarInicio(dep(undefined, e)).GET(pedido(`/api/auth/inicio?volta=${ORIGEM}`, { origem: null }));
  assert.equal(r.status, 500);
  assert.deepEqual(await r.json(), { erro: 'configuracao' });
});
