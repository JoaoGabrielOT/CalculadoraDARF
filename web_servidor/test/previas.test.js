import test from 'node:test';
import assert from 'node:assert/strict';
import { ipPublico, buscarPublico, ErroPrevia } from '../api/_lib/rede_publica.js';
import * as pagina from '../api/noticias/pagina.js';
import * as imagem from '../api/noticias/imagem.js';
import { env, pedido } from './auxiliar.js';

const MB = 1024 * 1024;

/** DNS falso: host -> lista de IPs; hosts fora do mapa resolvem para 93.184.216.34. */
function lookupFalso(mapa = {}) {
  const chamadas = [];
  const f = async (host, opcoes) => {
    chamadas.push({ host, opcoes });
    const ips = mapa[host] ?? ['93.184.216.34'];
    return ips.map((address) => ({ address, family: address.includes(':') ? 6 : 4 }));
  };
  f.chamadas = chamadas;
  return f;
}

/** fetch falso por URL: cada valor é uma função que devolve a Response. */
function fetchRotas(rotas) {
  const chamadas = [];
  const f = async (url, opcoes = {}) => {
    chamadas.push({ url: String(url), ...opcoes });
    const rota = rotas[String(url)];
    if (!rota) throw new TypeError('fetch failed');
    return rota();
  };
  f.chamadas = chamadas;
  return f;
}

const redirecionar = (location, status = 302) => () =>
  new Response(null, { status, headers: { location } });
const conteudo = (corpo, tipo) => () =>
  new Response(corpo, { status: 200, headers: tipo ? { 'content-type': tipo } : {} });

const dep = (f, lookup = lookupFalso()) => ({ fetch: f, lookup, env, agora: () => 0 });
const urlPagina = (alvo) => '/api/noticias/pagina?url=' + encodeURIComponent(alvo);
const urlImagem = (alvo) => '/api/noticias/imagem?url=' + encodeURIComponent(alvo);

test('ipPublico: faixas privadas e reservadas -> false', () => {
  const privados = [
    '0.0.0.0', '0.1.2.3', '10.0.0.1', '10.255.255.255', '100.64.0.1', '100.127.255.254',
    '127.0.0.1', '127.8.8.8', '169.254.0.1', '169.254.169.254', '172.16.0.1', '172.31.255.255',
    '192.168.0.1', '192.168.255.255', '198.18.0.1', '198.19.255.255', '224.0.0.1',
    '239.255.255.255', '240.0.0.1', '255.255.255.255',
    '::', '::1', 'fc00::1', 'fd12:3456::1', 'fe80::1', 'febf::1',
    '::ffff:10.0.0.1', '::ffff:127.0.0.1', '::ffff:169.254.169.254', '::ffff:7f00:1',
    'lixo', '', '1.2.3', '256.1.1.1',
  ];
  for (const ip of privados) assert.equal(ipPublico(ip), false, ip);
});

test('ipPublico: endereços públicos -> true', () => {
  const publicos = [
    '8.8.8.8', '1.1.1.1', '93.184.216.34', '100.63.255.255', '100.128.0.1', '172.15.0.1',
    '172.32.0.1', '198.17.0.1', '198.20.0.1', '223.255.255.255', '11.0.0.1',
    '2606:4700::1111', '2001:4860:4860::8888', '::ffff:8.8.8.8',
  ];
  for (const ip of publicos) assert.equal(ipPublico(ip), true, ip);
});

test('pagina: host que resolve para IP privado -> 400 sem chamar o fetch', async () => {
  const f = fetchRotas({});
  const { GET } = pagina.criar(dep(f, lookupFalso({ 'interno.exemplo': ['10.0.0.5'] })));
  const r = await GET(pedido(urlPagina('https://interno.exemplo/noticia')));
  assert.equal(r.status, 400);
  assert.deepEqual(await r.json(), { erro: 'destino' });
  assert.equal(f.chamadas.length, 0);
});

test('pagina: qualquer endereço privado na resolução -> 400', async () => {
  const f = fetchRotas({});
  const lookup = lookupFalso({ 'misto.exemplo': ['8.8.8.8', '192.168.0.10'] });
  const { GET } = pagina.criar(dep(f, lookup));
  const r = await GET(pedido(urlPagina('https://misto.exemplo/')));
  assert.equal(r.status, 400);
  assert.equal(f.chamadas.length, 0);
  assert.deepEqual(lookup.chamadas[0].opcoes, { all: true });
});

test('pagina: localhost, IP literal privado, esquema e porta errados -> 400', async () => {
  const f = fetchRotas({});
  const { GET } = pagina.criar(dep(f));
  for (const alvo of [
    'http://localhost/', 'http://app.localhost/', 'http://127.0.0.1/', 'http://[::1]/',
    'http://[::ffff:10.0.0.1]/', 'http://169.254.169.254/latest/meta-data/', 'http://2130706433/',
    'ftp://exemplo.com/', 'file:///etc/passwd', 'javascript:alert(1)', 'nao e url',
    'http://exemplo.com:8080/', 'https://exemplo.com:22/', 'http://usuario:senha@exemplo.com/',
  ]) {
    const r = await GET(pedido(urlPagina(alvo)));
    assert.equal(r.status, 400, alvo);
  }
  assert.equal((await GET(pedido('/api/noticias/pagina'))).status, 400);
  assert.equal(f.chamadas.length, 0);
});

test('pagina: portas 80 e 443 explícitas são aceitas', async () => {
  const f = fetchRotas({
    'http://exemplo.com/a': conteudo('<html></html>', 'text/html'),
    'https://exemplo.com:80/b': conteudo('<html></html>', 'text/html'),
  });
  const { GET } = pagina.criar(dep(f));
  assert.equal((await GET(pedido(urlPagina('http://exemplo.com:80/a')))).status, 200);
  assert.equal((await GET(pedido(urlPagina('https://exemplo.com:80/b')))).status, 200);
});

test('pagina: redirecionamento para 169.254.169.254 -> 400 no 2º salto', async () => {
  const f = fetchRotas({
    'https://noticia.exemplo/a': redirecionar('http://169.254.169.254/latest/meta-data/'),
  });
  const { GET } = pagina.criar(dep(f));
  const r = await GET(pedido(urlPagina('https://noticia.exemplo/a')));
  assert.equal(r.status, 400);
  assert.equal(f.chamadas.length, 1);
});

test('pagina: redirecionamento para host que resolve privado -> 400', async () => {
  const f = fetchRotas({ 'https://noticia.exemplo/a': redirecionar('https://rebind.exemplo/') });
  const lookup = lookupFalso({ 'rebind.exemplo': ['::ffff:192.168.1.1'] });
  const { GET } = pagina.criar(dep(f, lookup));
  const r = await GET(pedido(urlPagina('https://noticia.exemplo/a')));
  assert.equal(r.status, 400);
  assert.equal(f.chamadas.length, 1);
});

test('pagina: 4 redirecionamentos públicos -> 508', async () => {
  const f = fetchRotas({
    'https://a.exemplo/0': redirecionar('https://a.exemplo/1'),
    'https://a.exemplo/1': redirecionar('/2', 301),
    'https://a.exemplo/2': redirecionar('https://b.exemplo/3', 307),
    'https://b.exemplo/3': redirecionar('https://b.exemplo/4', 308),
    'https://b.exemplo/4': conteudo('<html></html>', 'text/html'),
  });
  const { GET } = pagina.criar(dep(f));
  const r = await GET(pedido(urlPagina('https://a.exemplo/0')));
  assert.equal(r.status, 508);
  assert.equal(f.chamadas.length, 4);
});

test('pagina: segue até 3 redirecionamentos; x-url-final = último salto', async () => {
  const f = fetchRotas({
    'https://a.exemplo/0': redirecionar('https://a.exemplo/1'),
    'https://a.exemplo/1': redirecionar('/2', 303),
    'https://a.exemplo/2': redirecionar('https://b.exemplo/fim'),
    'https://b.exemplo/fim': conteudo('<html><head></head></html>', 'text/html; charset=utf-8'),
  });
  const { GET } = pagina.criar(dep(f));
  const r = await GET(pedido(urlPagina('https://a.exemplo/0')));
  assert.equal(r.status, 200);
  assert.equal(r.headers.get('x-url-final'), 'https://b.exemplo/fim');
  assert.equal(r.headers.get('content-type'), 'text/html; charset=utf-8');
  assert.equal(await r.text(), '<html><head></head></html>');
  for (const c of f.chamadas) assert.equal(c.redirect, 'manual');
});

test('pagina: redirecionamento sem Location -> 502', async () => {
  const f = fetchRotas({ 'https://a.exemplo/': () => new Response(null, { status: 302 }) });
  const { GET } = pagina.criar(dep(f));
  assert.equal((await GET(pedido(urlPagina('https://a.exemplo/')))).status, 502);
});

test('pagina: content-type application/pdf ou ausente -> 415', async () => {
  const f = fetchRotas({
    'https://a.exemplo/pdf': conteudo('%PDF', 'application/pdf'),
    'https://a.exemplo/sem': conteudo('<html></html>'),
  });
  const { GET } = pagina.criar(dep(f));
  assert.equal((await GET(pedido(urlPagina('https://a.exemplo/pdf')))).status, 415);
  assert.equal((await GET(pedido(urlPagina('https://a.exemplo/sem')))).status, 415);
});

test('pagina: HTML de 1,5 MB -> 200 cortado em 1 048 576 bytes, com cache e defesas', async () => {
  const f = fetchRotas({
    'https://a.exemplo/grande': conteudo(new Uint8Array(1.5 * MB).fill(65), 'text/html'),
  });
  const { GET } = pagina.criar(dep(f));
  const r = await GET(pedido(urlPagina('https://a.exemplo/grande')));
  assert.equal(r.status, 200);
  assert.equal((await r.arrayBuffer()).byteLength, 1048576);
  assert.match(r.headers.get('cache-control'), /s-maxage=3600/);
  assert.equal(r.headers.get('content-security-policy'), "sandbox; default-src 'none'");
  assert.equal(r.headers.get('x-content-type-options'), 'nosniff');
  assert.equal(r.headers.get('x-url-final'), 'https://a.exemplo/grande');
});

test('pagina: destino com erro HTTP ou falha de rede -> 502', async () => {
  const f = fetchRotas({
    'https://a.exemplo/404': () => new Response('x', { status: 404, headers: { 'content-type': 'text/html' } }),
  });
  const { GET } = pagina.criar(dep(f));
  assert.equal((await GET(pedido(urlPagina('https://a.exemplo/404')))).status, 502);
  assert.equal((await GET(pedido(urlPagina('https://a.exemplo/rede')))).status, 502);
});

test('buscarPublico: tempo esgotado -> ErroPrevia(504)', async () => {
  const f = async (url, { signal }) =>
    new Promise((_, rejeitar) => {
      signal.addEventListener('abort', () => rejeitar(signal.reason ?? new Error('abort')));
    });
  await assert.rejects(
    buscarPublico('https://a.exemplo/', {
      fetch: f, lookup: lookupFalso(), tipos: /^text\/html/i, maxBytes: MB, tempoMs: 20,
    }),
    (e) => e instanceof ErroPrevia && e.status === 504,
  );
});

test('buscarPublico: repassa ao fetch os endereços conferidos', async () => {
  const f = fetchRotas({ 'https://a.exemplo/': conteudo('<html></html>', 'text/html') });
  const lookup = lookupFalso({ 'a.exemplo': ['8.8.4.4'] });
  const r = await buscarPublico('https://a.exemplo/', {
    fetch: f, lookup, tipos: /^text\/html/i, maxBytes: MB,
  });
  assert.equal(r.status, 200);
  assert.equal(r.urlFinal, 'https://a.exemplo/');
  assert.ok(r.corpo instanceof Uint8Array);
  assert.deepEqual(f.chamadas[0].enderecos, [{ address: '8.8.4.4', family: 4 }]);
});

test('imagem: image/png de 3 MB -> 413', async () => {
  const f = fetchRotas({ 'https://a.exemplo/g.png': conteudo(new Uint8Array(3 * MB), 'image/png') });
  const { GET } = imagem.criar(dep(f));
  assert.equal((await GET(pedido(urlImagem('https://a.exemplo/g.png')))).status, 413);
});

test('imagem: text/html -> 415', async () => {
  const f = fetchRotas({ 'https://a.exemplo/i': conteudo('<html></html>', 'text/html') });
  const { GET } = imagem.criar(dep(f));
  assert.equal((await GET(pedido(urlImagem('https://a.exemplo/i')))).status, 415);
});

test('imagem: image/jpeg pequeno -> 200 com s-maxage=3600', async () => {
  const f = fetchRotas({ 'https://a.exemplo/p.jpg': conteudo(new Uint8Array(100).fill(7), 'image/jpeg') });
  const { GET } = imagem.criar(dep(f));
  const r = await GET(pedido(urlImagem('https://a.exemplo/p.jpg')));
  assert.equal(r.status, 200);
  assert.match(r.headers.get('cache-control'), /s-maxage=3600/);
  assert.equal(r.headers.get('content-type'), 'image/jpeg');
  assert.equal(r.headers.get('x-url-final'), 'https://a.exemplo/p.jpg');
  assert.equal(r.headers.get('content-security-policy'), "sandbox; default-src 'none'");
  assert.equal(r.headers.get('x-content-type-options'), 'nosniff');
  assert.equal((await r.arrayBuffer()).byteLength, 100);
});

test('pagina e imagem: sem origem -> 403; limite 120/min por IP', async () => {
  const f = fetchRotas({ 'https://a.exemplo/p.jpg': conteudo('x', 'image/jpeg') });
  for (const rota of [pagina, imagem]) {
    const { GET } = rota.criar(dep(f));
    const r = await GET(pedido(urlImagem('https://a.exemplo/p.jpg'), { origem: null }));
    assert.equal(r.status, 403);
  }
  assert.equal(f.chamadas.length, 0);
  const { GET } = imagem.criar(dep(f));
  for (let i = 0; i < 120; i++) await GET(pedido(urlImagem('https://a.exemplo/p.jpg'), { ip: '2.2.2.2' }));
  assert.equal((await GET(pedido(urlImagem('https://a.exemplo/p.jpg'), { ip: '2.2.2.2' }))).status, 429);
});
