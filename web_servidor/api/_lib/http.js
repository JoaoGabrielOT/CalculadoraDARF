const LOCAIS = ['http://localhost:*', 'http://127.0.0.1:*'];

export const depPadrao = {
  fetch: (...args) => fetch(...args),
  env: process.env,
  agora: () => Date.now(),
};

export function origensPermitidas(env) {
  const lista = (env?.ORIGENS_PERMITIDAS ?? '')
    .split(',')
    .map((o) => o.trim())
    .filter(Boolean);
  return [...lista, ...LOCAIS];
}

export function origemDoPedido(request) {
  const origin = request.headers.get('origin');
  if (origin) return origin;
  const referer = request.headers.get('referer');
  if (!referer) return null;
  try {
    return new URL(referer).origin;
  } catch {
    return null;
  }
}

function permitida(origem, lista) {
  return lista.some((padrao) => {
    if (!padrao.endsWith(':*')) return padrao === origem;
    const prefixo = padrao.slice(0, -1);
    return origem.startsWith(prefixo) && /^\d{1,5}$/.test(origem.slice(prefixo.length));
  });
}

export function json(status, objeto, extra = {}) {
  return new Response(JSON.stringify(objeto), {
    status,
    headers: { 'content-type': 'application/json', ...extra },
  });
}

function comCors(resposta, origem) {
  const headers = new Headers(resposta.headers);
  headers.set('access-control-allow-origin', origem);
  headers.set('access-control-expose-headers', 'x-url-final, content-type');
  headers.set('vary', 'Origin');
  return new Response(resposta.body, { status: resposta.status, headers });
}

/**
 * Monta os métodos da rota com origem, limite por IP, CORS e erro genérico.
 * Cada método de `metodos` recebe `(request, url, cache)` e devolve uma Response.
 */
export function criarRota({ metodos, limite, cache, exigirOrigem = true }, dep) {
  const permitidas = origensPermitidas(dep.env);
  const contagens = new Map();

  function estourou(ip) {
    const agora = dep.agora();
    if (contagens.size > 5000) {
      for (const [k, c] of contagens) if (agora - c.inicio >= 60_000) contagens.delete(k);
    }
    let c = contagens.get(ip);
    if (!c || agora - c.inicio >= 60_000) {
      c = { inicio: agora, n: 0 };
      contagens.set(ip, c);
    }
    c.n += 1;
    return c.n > limite;
  }

  function tratar(metodo) {
    const executar = async (request) => {
      try {
        const origem = origemDoPedido(request);
        if (exigirOrigem && (!origem || !permitida(origem, permitidas))) {
          return json(403, { erro: 'origem' });
        }
        const comOrigin = request.headers.get('origin') && origem;
        const finalizar = (r) => (comOrigin ? comCors(r, origem) : r);

        if (metodo === 'OPTIONS') {
          if (!comOrigin) return new Response(null, { status: 204 });
          return new Response(null, {
            status: 204,
            headers: {
              'access-control-allow-origin': origem,
              'access-control-allow-methods': 'GET, POST, OPTIONS',
              'access-control-allow-headers': 'content-type, accept-language',
              'access-control-max-age': '600',
              vary: 'Origin',
            },
          });
        }
        if (!metodos[metodo]) {
          return finalizar(json(405, { erro: 'metodo' }, { allow: Object.keys(metodos).join(', ') }));
        }
        const ip = (request.headers.get('x-forwarded-for') ?? '').split(',')[0].trim() || 'desconhecido';
        if (estourou(ip)) return finalizar(json(429, { erro: 'limite' }, { 'retry-after': '30' }));
        return finalizar(await metodos[metodo](request, new URL(request.url), cache));
      } catch {
        return json(502, { erro: 'indisponivel' });
      }
    };
    // Vary: Origin em toda resposta, para o cache de borda não misturar origens.
    return async (request) => {
      const r = await executar(request);
      r.headers.set('vary', 'Origin');
      return r;
    };
  }

  return { GET: tratar('GET'), POST: tratar('POST'), OPTIONS: tratar('OPTIONS') };
}
