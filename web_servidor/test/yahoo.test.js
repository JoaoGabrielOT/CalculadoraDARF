import test from 'node:test';
import assert from 'node:assert/strict';
import { criar } from '../api/yahoo/chart/[ticker].js';
import { repassar } from '../api/_lib/repasse.js';
import { env, fetchFalso, pedido } from './auxiliar.js';

test('repassa o chart com só os parâmetros permitidos', async () => {
  const f = fetchFalso(200, '{"chart":{}}');
  const { GET } = criar({ fetch: f, env, agora: () => 0 });
  const r = await GET(pedido('/api/yahoo/chart/PETR4.SA?range=5d&interval=1d&x=1'));
  assert.equal(r.status, 200);
  assert.equal(f.chamadas[0].url, 'https://query1.finance.yahoo.com/v8/finance/chart/PETR4.SA?range=5d&interval=1d');
  assert.match(r.headers.get('cache-control'), /s-maxage=30/);
  assert.equal(r.headers.get('vary'), 'Origin');
  assert.equal(await r.text(), '{"chart":{}}');
  assert.match(f.chamadas[0].headers['User-Agent'], /^Mozilla\/5\.0 \(Windows NT 10\.0; Win64; x64\)/);
  assert.equal(f.chamadas[0].headers['Accept-Language'], 'pt-BR,pt;q=0.9');
});

test('aceita period1, period2 e includePrePost', async () => {
  const f = fetchFalso(200, '{}');
  const { GET } = criar({ fetch: f, env, agora: () => 0 });
  await GET(pedido('/api/yahoo/chart/VALE3.SA?period1=1&period2=2&includePrePost=false'));
  assert.equal(
    f.chamadas[0].url,
    'https://query1.finance.yahoo.com/v8/finance/chart/VALE3.SA?period1=1&period2=2&includePrePost=false',
  );
});

for (const t of ['..%2Fetc', 'PETR4', 'petr4.SA', 'ABCDEFGHIJKLM.SA']) {
  test(`ticker inválido ${t} -> 400 sem chamar o fetch`, async () => {
    const f = fetchFalso(200, '{}');
    const { GET } = criar({ fetch: f, env, agora: () => 0 });
    const r = await GET(pedido(`/api/yahoo/chart/${t}?range=5d`));
    assert.equal(r.status, 400);
    assert.equal(f.chamadas.length, 0);
  });
}

test('Yahoo 404 é repassado, sem cache', async () => {
  const { GET } = criar({ fetch: fetchFalso(404, '{"x":1}'), env, agora: () => 0 });
  const r = await GET(pedido('/api/yahoo/chart/XXXX3.SA'));
  assert.equal(r.status, 404);
  assert.equal(r.headers.get('cache-control'), null);
});

test('fetch que rejeita -> 502', async () => {
  const { GET } = criar({
    fetch: async () => {
      throw new Error('x');
    },
    env,
    agora: () => 0,
  });
  const r = await GET(pedido('/api/yahoo/chart/PETR4.SA'));
  assert.equal(r.status, 502);
  assert.deepEqual(await r.json(), { erro: 'indisponivel' });
});

test('fetch que passa de 8 s -> 502', async () => {
  const lento = (url, { signal }) =>
    new Promise((_, rej) => signal.addEventListener('abort', () => rej(new Error('abortado'))));
  const { GET } = criar({ fetch: lento, env, agora: () => 0 });
  const t0 = Date.now();
  const r = await GET(pedido('/api/yahoo/chart/PETR4.SA'));
  assert.equal(r.status, 502);
  assert.ok(Date.now() - t0 >= 7900);
});

test('3xx do destino não é seguido nem repassado -> 502', async () => {
  const f = fetchFalso(302, '', { location: 'https://outro.example/x' });
  const { GET } = criar({ fetch: f, env, agora: () => 0 });
  const r = await GET(pedido('/api/yahoo/chart/PETR4.SA'));
  assert.equal(r.status, 502);
  assert.deepEqual(await r.json(), { erro: 'indisponivel' });
  assert.equal(f.chamadas.length, 1);
  assert.equal(f.chamadas[0].redirect, 'manual');
});

test('repassar: toda resposta leva sandbox e nosniff (200, erro do destino e 502)', async () => {
  const falhaRede = async () => {
    throw new Error('x');
  };
  for (const f of [fetchFalso(200, '<html></html>'), fetchFalso(404, '{}'), fetchFalso(302, ''), falhaRede]) {
    const r = await repassar('https://exemplo.invalid/', { fetch: f });
    assert.equal(r.headers.get('content-security-policy'), "sandbox; default-src 'none'");
    assert.equal(r.headers.get('x-content-type-options'), 'nosniff');
  }
});
