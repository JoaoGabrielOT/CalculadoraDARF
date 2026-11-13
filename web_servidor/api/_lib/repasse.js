export const USER_AGENT =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36';

const SEM_CORPO = new Set([204, 205, 304]);

const falha = () =>
  new Response('{"erro":"indisponivel"}', {
    status: 502,
    headers: { 'content-type': 'application/json' },
  });

/** Mantém só os parâmetros permitidos (primeira ocorrência, ordem do pedido). */
export function filtrarParametros(params, permitidos) {
  const saida = new URLSearchParams();
  for (const [k, v] of params) {
    if (permitidos.includes(k) && !saida.has(k)) saida.set(k, v);
  }
  return saida;
}

/** Repassa a chamada ao destino: status, corpo e content-type; 502 se falhar. */
export async function repassar(
  url,
  { fetch, metodo = 'GET', corpo, tipo, tempoMs = 8000, cache },
) {
  const controle = new AbortController();
  const timer = setTimeout(() => controle.abort(), tempoMs);
  try {
    const headers = { 'User-Agent': USER_AGENT, 'Accept-Language': 'pt-BR,pt;q=0.9' };
    if (tipo) headers['Content-Type'] = tipo;
    const r = await fetch(url, { method: metodo, headers, body: corpo, signal: controle.signal });
    const dados = SEM_CORPO.has(r.status) ? null : await r.arrayBuffer();
    const saida = {};
    const tipoResp = r.headers.get('content-type');
    if (tipoResp) saida['content-type'] = tipoResp;
    if (r.status === 200 && cache) saida['cache-control'] = cache;
    if (r.url) saida['x-url-final'] = r.url;
    return new Response(dados, { status: r.status, headers: saida });
  } catch {
    return falha();
  } finally {
    clearTimeout(timer);
  }
}
