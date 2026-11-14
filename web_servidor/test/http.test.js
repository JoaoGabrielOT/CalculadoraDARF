import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { origensPermitidas, origemDoPedido } from '../api/_lib/http.js';
import { criar } from '../api/yahoo/chart/[ticker].js';
import { env, fetchFalso, pedido } from './auxiliar.js';

const URL_OK = '/api/yahoo/chart/PETR4.SA?range=5d';
const nova = (agora = () => 0) => criar({ fetch: fetchFalso(200, '{}'), env, agora });

test('origensPermitidas junta o env com localhost', () => {
  assert.deepEqual(origensPermitidas(env), [
    'https://calculadora-darf.vercel.app',
    'https://calculadora-darf.onrender.com',
    'http://localhost:*',
    'http://127.0.0.1:*',
  ]);
  assert.deepEqual(origensPermitidas({}), ['http://localhost:*', 'http://127.0.0.1:*']);
});

test('origemDoPedido usa Origin e senão a origem do Referer', () => {
  assert.equal(origemDoPedido(pedido('/x', { origem: 'https://a.b' })), 'https://a.b');
  assert.equal(
    origemDoPedido(pedido('/x', { origem: null, cabecalhos: { referer: 'https://a.b/p?q=1' } })),
    'https://a.b',
  );
  assert.equal(origemDoPedido(pedido('/x', { origem: null })), null);
});

test('sem Origin e sem Referer -> 403', async () => {
  const r = await nova().GET(pedido(URL_OK, { origem: null }));
  assert.equal(r.status, 403);
  assert.deepEqual(await r.json(), { erro: 'origem' });
});

test('origem estranha -> 403', async () => {
  const r = await nova().GET(pedido(URL_OK, { origem: 'https://evil.example' }));
  assert.equal(r.status, 403);
});

test('Referer permitido é aceito', async () => {
  const r = await nova().GET(
    pedido(URL_OK, { origem: null, cabecalhos: { referer: 'https://calculadora-darf.vercel.app/' } }),
  );
  assert.equal(r.status, 200);
});

test('localhost com qualquer porta é aceito e ecoa a origem', async () => {
  const r = await nova().GET(pedido(URL_OK, { origem: 'http://localhost:5173' }));
  assert.equal(r.status, 200);
  assert.equal(r.headers.get('access-control-allow-origin'), 'http://localhost:5173');
  assert.equal(r.headers.get('access-control-expose-headers'), 'x-url-final, content-type');
  assert.equal(r.headers.get('vary'), 'Origin');
});

test('OPTIONS de origem permitida -> 204 com cabeçalhos CORS', async () => {
  const r = await nova().OPTIONS(pedido(URL_OK, { metodo: 'OPTIONS' }));
  assert.equal(r.status, 204);
  assert.equal(r.headers.get('access-control-allow-origin'), 'https://calculadora-darf.vercel.app');
  assert.equal(r.headers.get('access-control-allow-methods'), 'GET, POST, OPTIONS');
  assert.equal(r.headers.get('access-control-allow-headers'), 'content-type, accept-language');
  assert.equal(r.headers.get('access-control-max-age'), '600');
});

test('OPTIONS de origem estranha -> 403', async () => {
  const r = await nova().OPTIONS(pedido(URL_OK, { metodo: 'OPTIONS', origem: 'https://evil.example' }));
  assert.equal(r.status, 403);
});

test('241º pedido do mesmo IP em 60 s -> 429; zera 61 s depois', async () => {
  let t = 0;
  const { GET } = nova(() => t);
  for (let i = 0; i < 240; i++) {
    assert.equal((await GET(pedido(URL_OK))).status, 200, `pedido ${i + 1}`);
  }
  const r = await GET(pedido(URL_OK));
  assert.equal(r.status, 429);
  assert.equal(r.headers.get('retry-after'), '30');
  assert.deepEqual(await r.json(), { erro: 'limite' });
  assert.equal((await GET(pedido(URL_OK, { ip: '2.2.2.2' }))).status, 200);
  t = 61_000;
  assert.equal((await GET(pedido(URL_OK))).status, 200);
});

test('exceção interna vira 502 sem detalhes', async () => {
  const { GET } = criar({
    fetch: async () => {
      throw new Error('segredo');
    },
    env,
    agora: () => 0,
  });
  const r = await GET(pedido(URL_OK));
  assert.equal(r.status, 502);
  assert.equal(await r.text(), '{"erro":"indisponivel"}');
});

test('Vary: Origin em toda resposta (sem Origin, 403, 405, 429)', async () => {
  const { GET, POST } = nova();
  assert.equal((await GET(pedido(URL_OK, { origem: null, cabecalhos: { referer: 'https://calculadora-darf.vercel.app/' } }))).headers.get('vary'), 'Origin');
  assert.equal((await GET(pedido(URL_OK, { origem: null }))).headers.get('vary'), 'Origin');
  assert.equal((await POST(pedido(URL_OK, { metodo: 'POST' }))).status, 405);
  assert.equal((await POST(pedido(URL_OK, { metodo: 'POST' }))).headers.get('vary'), 'Origin');
  const lim = nova();
  let ultima;
  for (let i = 0; i < 241; i++) ultima = await lim.GET(pedido(URL_OK));
  assert.equal(ultima.status, 429);
  assert.equal(ultima.headers.get('vary'), 'Origin');
});

test('vercel.json: o site fora de frames, sem trocar o CSP das funções em /api', () => {
  const vercel = JSON.parse(readFileSync(new URL('../vercel.json', import.meta.url), 'utf8'));
  const valor = (regra, k) => regra.headers.find((h) => h.key === k)?.value;
  const casa = (regra, caminho) => new RegExp(`^${regra.source}$`).test(caminho);
  const comCsp = vercel.headers.filter((r) => valor(r, 'Content-Security-Policy') !== undefined);
  assert.equal(comCsp.length, 1);
  const site = comCsp[0];
  assert.equal(valor(site, 'Content-Security-Policy'), "frame-ancestors 'none'");
  assert.equal(valor(site, 'X-Frame-Options'), 'DENY');
  for (const c of ['/', '/index.html', '/main.dart.js', '/assets/x.png']) assert.ok(casa(site, c), c);
  for (const c of ['/api/yahoo/chart/PETR4.SA', '/api/auth/retorno', '/api/previas/pagina']) {
    assert.equal(casa(site, c), false, c);
  }
  // fora do CSP, só valores iguais aos das funções valem para /api
  const todas = vercel.headers.find((r) => r.source === '/(.*)');
  assert.deepEqual(todas.headers, [{ key: 'X-Content-Type-Options', value: 'nosniff' }]);
});
