import http from 'node:http';
import https from 'node:https';
import { isIP } from 'node:net';
import { lookup as dnsLookup } from 'node:dns/promises';
import { Readable, pipeline } from 'node:stream';
import zlib from 'node:zlib';
import { criarRota, depPadrao, json } from './http.js';
import { DEFESAS, USER_AGENT } from './repasse.js';

export class ErroPrevia extends Error {
  constructor(status) {
    super(`previa ${status}`);
    this.status = status;
  }
}

const ERROS = {
  400: 'destino', 413: 'tamanho', 415: 'tipo', 502: 'indisponivel', 504: 'tempo', 508: 'redirecionamentos',
};
const REDIRECIONAMENTOS = new Set([301, 302, 303, 307, 308]);

function octetos4(ip) {
  const partes = ip.split('.');
  if (partes.length !== 4) return null;
  const n = partes.map((p) => (/^\d{1,3}$/.test(p) ? Number(p) : 256));
  return n.every((x) => x <= 255) ? n : null;
}

function publico4([a, b]) {
  if (a === 0 || a === 10 || a === 127 || a >= 224) return false;
  if (a === 100 && b >= 64 && b <= 127) return false;
  if (a === 169 && b === 254) return false;
  if (a === 172 && b >= 16 && b <= 31) return false;
  if (a === 192 && b === 168) return false;
  if (a === 198 && (b === 18 || b === 19)) return false;
  return true;
}

/** Os 8 grupos de 16 bits de um IPv6 (aceita o IPv4 no final), ou null. */
function grupos6(ip) {
  let texto = ip;
  const ultimo = texto.lastIndexOf(':');
  if (texto.includes('.')) {
    const v4 = octetos4(texto.slice(ultimo + 1));
    if (!v4) return null;
    texto = texto.slice(0, ultimo + 1) + ((v4[0] << 8) | v4[1]).toString(16) + ':' + ((v4[2] << 8) | v4[3]).toString(16);
  }
  const metades = texto.split('::');
  if (metades.length > 2) return null;
  const ler = (s) => (s ? s.split(':') : []);
  const esq = ler(metades[0]);
  const dir = metades.length === 2 ? ler(metades[1]) : [];
  const faltam = 8 - esq.length - dir.length;
  if (metades.length === 2 ? faltam < 1 : faltam !== 0) return null;
  const todos = [...esq, ...Array(metades.length === 2 ? faltam : 0).fill('0'), ...dir];
  if (!todos.every((g) => /^[0-9a-f]{1,4}$/i.test(g))) return null;
  return todos.map((g) => parseInt(g, 16));
}

const v4DeGrupos = (alto, baixo) => [alto >> 8, alto & 255, baixo >> 8, baixo & 255];

/** true só para endereços que podem ser alcançados na internet pública. */
export function ipPublico(ip) {
  const versao = isIP(ip);
  if (versao === 4) return publico4(octetos4(ip));
  if (versao !== 6) return false;
  const g = grupos6(ip);
  if (!g) return false;
  const zeros = (ate) => g.slice(0, ate).every((x) => x === 0);
  if (zeros(5) && g[5] === 0xffff) return publico4(v4DeGrupos(g[6], g[7])); // ::ffff:a.b.c.d
  if (zeros(6)) return false; // ::, ::1 e IPv4 compatível
  if (g[0] === 0x64 && g[1] === 0xff9b && g.slice(2, 6).every((x) => x === 0)) {
    return publico4(v4DeGrupos(g[6], g[7])); // NAT64
  }
  if (g[0] === 0x2002) return publico4(v4DeGrupos(g[1], g[2])); // 6to4
  if ((g[0] & 0xfe00) === 0xfc00) return false; // fc00::/7
  if ((g[0] & 0xff80) === 0xfe80) return false; // fe80::/10 e fec0::/10
  if ((g[0] & 0xff00) === 0xff00) return false; // multicast
  return true;
}

/** Confere esquema, porta e todos os IPs do host; devolve os endereços conferidos. */
async function conferirDestino(texto, lookup, abortado) {
  let url;
  try {
    url = new URL(texto);
  } catch {
    throw new ErroPrevia(400);
  }
  if (url.protocol !== 'http:' && url.protocol !== 'https:') throw new ErroPrevia(400);
  if (url.username || url.password || !['', '80', '443'].includes(url.port)) throw new ErroPrevia(400);
  const host = url.hostname.replace(/^\[|\]$/g, '').replace(/\.$/, '').toLowerCase();
  if (!host || host === 'localhost' || host.endsWith('.localhost')) throw new ErroPrevia(400);
  const versao = isIP(host);
  if (versao) {
    if (!ipPublico(host)) throw new ErroPrevia(400);
    return { url, enderecos: [{ address: host, family: versao }] };
  }
  const lista = await Promise.race([lookup(host, { all: true }), abortado]);
  if (!lista?.length || !lista.every((e) => ipPublico(e.address))) throw new ErroPrevia(400);
  return { url, enderecos: lista.map(({ address, family }) => ({ address, family })) };
}

/** Lê o corpo em fluxo; ao passar de maxBytes corta (cortar) ou lança 413. */
async function lerCorpo(resposta, maxBytes, cortar, signal) {
  if (!cortar && Number(resposta.headers.get('content-length')) > maxBytes) {
    resposta.body?.cancel().catch(() => {});
    throw new ErroPrevia(413);
  }
  const partes = [];
  let total = 0;
  if (resposta.body) {
    const leitor = resposta.body.getReader();
    try {
      for (;;) {
        if (signal.aborted) throw signal.reason;
        const { done, value } = await leitor.read();
        if (done) break;
        if (total + value.byteLength > maxBytes) {
          if (!cortar) throw new ErroPrevia(413);
          partes.push(value.subarray(0, maxBytes - total));
          total = maxBytes;
          break;
        }
        partes.push(value);
        total += value.byteLength;
      }
    } finally {
      leitor.cancel().catch(() => {});
    }
  }
  const corpo = new Uint8Array(total);
  let pos = 0;
  for (const p of partes) {
    corpo.set(p, pos);
    pos += p.byteLength;
  }
  return corpo;
}

/**
 * Busca `url` só em IPs públicos, seguindo até `maxRedirecionamentos` à mão e
 * conferindo o destino a cada salto. O `fetch` recebe `enderecos` (os IPs já
 * conferidos) para conectar neles, sem resolver o nome de novo.
 */
export async function buscarPublico(
  url,
  { fetch, lookup, tipos, maxBytes, cortar = false, tempoMs = 8000, maxRedirecionamentos = 3 },
) {
  const controle = new AbortController();
  const timer = setTimeout(() => controle.abort(new ErroPrevia(504)), tempoMs);
  const abortado = new Promise((_, rejeitar) => {
    controle.signal.addEventListener('abort', () => rejeitar(controle.signal.reason));
  });
  abortado.catch(() => {});
  try {
    let atual = url;
    for (let saltos = 0; ; saltos++) {
      const { url: destino, enderecos } = await conferirDestino(atual, lookup, abortado);
      const r = await fetch(destino.href, {
        headers: { 'User-Agent': USER_AGENT, 'Accept-Language': 'pt-BR,pt;q=0.9' },
        signal: controle.signal,
        redirect: 'manual',
        enderecos,
      });
      if (REDIRECIONAMENTOS.has(r.status)) {
        r.body?.cancel().catch(() => {});
        const location = r.headers.get('location');
        if (!location) throw new ErroPrevia(502);
        if (saltos >= maxRedirecionamentos) throw new ErroPrevia(508);
        atual = new URL(location, destino).href;
        continue;
      }
      if (r.status < 200 || r.status > 299) {
        r.body?.cancel().catch(() => {});
        throw new ErroPrevia(502);
      }
      const tipo = r.headers.get('content-type');
      if (!tipo || !tipos.test(tipo)) {
        r.body?.cancel().catch(() => {});
        throw new ErroPrevia(415);
      }
      const corpo = await lerCorpo(r, maxBytes, cortar, controle.signal);
      return { status: r.status, tipo, corpo, urlFinal: destino.href };
    }
  } catch (e) {
    if (controle.signal.aborted) throw new ErroPrevia(504);
    if (e instanceof ErroPrevia) throw e;
    throw new ErroPrevia(502);
  } finally {
    clearTimeout(timer);
  }
}

/**
 * fetch mínimo sobre node:http(s) que conecta só nos `enderecos` conferidos
 * (contra DNS rebinding) e nunca segue redirecionamento.
 */
export function fetchFixado(url, { method = 'GET', headers = {}, signal, enderecos } = {}) {
  return new Promise((resolver, rejeitar) => {
    if (!enderecos?.length) return rejeitar(new Error('sem enderecos conferidos'));
    const alvo = new URL(url);
    const modulo = alvo.protocol === 'https:' ? https : http;
    const lookup = (_host, opcoes, cb) => {
      if (opcoes?.all) cb(null, enderecos);
      else cb(null, enderecos[0].address, enderecos[0].family);
    };
    const req = modulo.request(
      alvo,
      { method, headers: { ...headers, 'Accept-Encoding': 'gzip, br' }, signal, lookup, agent: false },
      (res) => {
        try {
          const h = new Headers();
          for (const [k, v] of Object.entries(res.headers)) {
            for (const x of [v].flat()) if (x != null) h.append(k, String(x));
          }
          const codificacao = (res.headers['content-encoding'] ?? '').trim().toLowerCase();
          let fluxo = res;
          const descompressor = codificacao === 'gzip' || codificacao === 'x-gzip'
            ? zlib.createGunzip()
            : codificacao === 'br' ? zlib.createBrotliDecompress() : null;
          if (descompressor) {
            fluxo = pipeline(res, descompressor, () => {});
            h.delete('content-encoding');
            h.delete('content-length');
          }
          const semCorpo = [204, 205, 304].includes(res.statusCode) || method === 'HEAD';
          if (semCorpo) res.resume();
          resolver(new Response(semCorpo ? null : Readable.toWeb(fluxo), { status: res.statusCode, headers: h }));
        } catch (e) {
          res.destroy();
          rejeitar(e);
        }
      },
    );
    req.on('error', rejeitar);
    req.end();
  });
}

export const depPrevias = { ...depPadrao, fetch: fetchFixado, lookup: (host, opcoes) => dnsLookup(host, opcoes) };

/** Rota GET ?url= das prévias: busca só em IP público e repassa o conteúdo com defesas. */
export function criarRotaPrevia({ tipos, maxBytes, cortar = false }, dep) {
  return criarRota(
    {
      limite: 120,
      cache: 'public, s-maxage=3600',
      metodos: {
        GET: async (_request, url, cache) => {
          const alvo = url.searchParams.get('url');
          if (!alvo) return json(400, { erro: 'destino' });
          try {
            const r = await buscarPublico(alvo, { fetch: dep.fetch, lookup: dep.lookup, tipos, maxBytes, cortar });
            return new Response(r.corpo, {
              status: 200,
              headers: { 'content-type': r.tipo, 'cache-control': cache, 'x-url-final': r.urlFinal, ...DEFESAS },
            });
          } catch (e) {
            if (e instanceof ErroPrevia) return json(e.status, { erro: ERROS[e.status] ?? 'indisponivel' });
            throw e;
          }
        },
      },
    },
    dep,
  );
}
