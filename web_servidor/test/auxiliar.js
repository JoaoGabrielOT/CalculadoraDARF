export const env = {
  ORIGENS_PERMITIDAS: 'https://calculadora-darf.vercel.app,https://calculadora-darf.onrender.com',
};
export const ORIGEM = 'https://calculadora-darf.vercel.app';

export function fetchFalso(status = 200, corpo = '', cabecalhos = { 'content-type': 'application/json' }) {
  const chamadas = [];
  const f = async (url, opcoes = {}) => {
    chamadas.push({ url: String(url), ...opcoes });
    return new Response(corpo, { status, headers: cabecalhos });
  };
  f.chamadas = chamadas;
  return f;
}

export function pedido(caminho, { metodo = 'GET', origem = ORIGEM, ip = '1.1.1.1', corpo, tipo, cabecalhos = {} } = {}) {
  const h = { 'x-forwarded-for': ip, ...cabecalhos };
  if (origem) h.origin = origem;
  if (tipo) h['content-type'] = tipo;
  return new Request('https://calculadora-darf.vercel.app' + caminho, { method: metodo, headers: h, body: corpo });
}
