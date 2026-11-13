import test from 'node:test';
import assert from 'node:assert/strict';
import * as rss from '../api/noticias/rss.js';
import * as resolver from '../api/noticias/resolver.js';
import * as artigo from '../api/noticias/artigo/[gid].js';
import { env, fetchFalso, pedido } from './auxiliar.js';

const dep = (f) => ({ fetch: f, env, agora: () => 0 });
const FORM = 'application/x-www-form-urlencoded';

test('rss repassa só q, hl, gl, ceid', async () => {
  const f = fetchFalso(200, '<rss/>', { 'content-type': 'application/rss+xml' });
  const { GET } = rss.criar(dep(f));
  const r = await GET(pedido('/api/noticias/rss?q=PETR4&hl=pt-BR&gl=BR&ceid=BR:pt-419&x=1'));
  assert.equal(r.status, 200);
  assert.equal(
    f.chamadas[0].url,
    'https://news.google.com/rss/search?q=PETR4&hl=pt-BR&gl=BR&ceid=BR%3Apt-419',
  );
  assert.match(r.headers.get('cache-control'), /s-maxage=300/);
  assert.equal(r.headers.get('content-type'), 'application/rss+xml');
});

test('rss com q > 300 caracteres -> 400', async () => {
  const f = fetchFalso();
  const { GET } = rss.criar(dep(f));
  const r = await GET(pedido('/api/noticias/rss?q=' + 'a'.repeat(301)));
  assert.equal(r.status, 400);
  assert.equal(f.chamadas.length, 0);
});

test('resolver repassa o corpo idêntico, sem cache', async () => {
  const f = fetchFalso(200, '[]', { 'content-type': 'text/plain' });
  const { POST } = resolver.criar(dep(f));
  const corpo = 'f.req=%5B%5B%22Fbv4je%22%5D%5D';
  const r = await POST(pedido('/api/noticias/resolver', { metodo: 'POST', tipo: FORM, corpo }));
  assert.equal(r.status, 200);
  assert.equal(f.chamadas[0].url, 'https://news.google.com/_/DotsSplashUi/data/batchexecute');
  assert.equal(f.chamadas[0].method, 'POST');
  assert.equal(f.chamadas[0].body, corpo);
  assert.equal(r.headers.get('cache-control'), null);
});

test('resolver: GET -> 405', async () => {
  const f = fetchFalso();
  const rota = resolver.criar(dep(f));
  assert.equal((await rota.GET(pedido('/api/noticias/resolver'))).status, 405);
  const r = await rota.OPTIONS(pedido('/api/noticias/resolver', { metodo: 'OPTIONS' }));
  assert.equal(r.status, 204);
  assert.equal(f.chamadas.length, 0);
});

test('resolver: tipo errado, corpo sem f.req= ou > 4096 bytes -> 400', async () => {
  const f = fetchFalso();
  const { POST } = resolver.criar(dep(f));
  const p = (tipo, corpo) => POST(pedido('/api/noticias/resolver', { metodo: 'POST', tipo, corpo }));
  assert.equal((await p('application/json', 'f.req=x')).status, 400);
  assert.equal((await p(FORM, 'outro=x')).status, 400);
  assert.equal((await p(FORM, 'f.req=' + 'a'.repeat(4091))).status, 400);
  assert.equal(f.chamadas.length, 0);
  assert.equal((await p(FORM, 'f.req=' + 'a'.repeat(4090))).status, 200);
  assert.equal(f.chamadas.length, 1);
});

test('artigo: gid inválido -> 400; válido vai ao Google News', async () => {
  const f = fetchFalso(200, '<html/>', { 'content-type': 'text/html' });
  const { GET } = artigo.criar(dep(f));
  assert.equal((await GET(pedido('/api/noticias/artigo/curto'))).status, 400);
  assert.equal((await GET(pedido('/api/noticias/artigo/' + 'a'.repeat(601)))).status, 400);
  assert.equal((await GET(pedido('/api/noticias/artigo/abc%2F..%2Fdef12345'))).status, 400);
  assert.equal(f.chamadas.length, 0);
  const gid = 'CBMiAbc_def-1234567';
  const r = await GET(pedido(`/api/noticias/artigo/${gid}`));
  assert.equal(r.status, 200);
  assert.equal(f.chamadas[0].url, `https://news.google.com/rss/articles/${gid}`);
  assert.match(r.headers.get('cache-control'), /s-maxage=300/);
});
