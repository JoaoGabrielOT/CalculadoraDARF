import { lerChave } from './cifra.js';
import { origensPermitidas } from './http.js';

export const URL_TOKEN = 'https://oauth2.googleapis.com/token';
export const URL_REVOGAR = 'https://oauth2.googleapis.com/revoke';
export const COOKIE = '__Host-darf_oauth';
/** Nonce do cliente: volta no fragmento para o site conferir que foi ele quem começou o login. */
export const NONCE = /^[A-Za-z0-9_-]{16,128}$/;

const LOCAL = /^http:\/\/(localhost|127\.0\.0\.1)(:|$)/;

/**
 * Origens aceitas como destino da volta do login: as de ORIGENS_PERMITIDAS.
 * localhost só entra se ORIGENS_PERMITIDAS listar alguma origem localhost (desenvolvimento).
 */
export function origensDeVolta(env) {
  const doEnv = (env?.ORIGENS_PERMITIDAS ?? '').split(',').map((o) => o.trim()).filter(Boolean);
  return doEnv.some((o) => LOCAL.test(o)) ? origensPermitidas(env) : doEnv;
}

const EXIGIDAS = ['GOOGLE_CLIENT_ID', 'GOOGLE_CLIENT_SECRET', 'CHAVE_PACOTE', 'ORIGENS_PERMITIDAS', 'URL_RETORNO'];

/** Variáveis do painel do Vercel; `null` se faltar alguma ou a chave não tiver 32 bytes. */
export function config(env) {
  if (EXIGIDAS.some((nome) => !env?.[nome])) return null;
  if (!lerChave(env.CHAVE_PACOTE)) return null;
  return {
    clientId: env.GOOGLE_CLIENT_ID,
    segredo: env.GOOGLE_CLIENT_SECRET,
    chave: env.CHAVE_PACOTE,
    retorno: env.URL_RETORNO,
  };
}

/** POST de formulário ao Google; devolve `{ status, dados }` ou lança se a rede falhar. */
export async function postarGoogle(fetch, url, campos, tempoMs = 8000) {
  const controle = new AbortController();
  const timer = setTimeout(() => controle.abort(), tempoMs);
  try {
    const r = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams(campos).toString(),
      signal: controle.signal,
      redirect: 'manual',
    });
    let dados = null;
    try {
      dados = await r.json();
    } catch {
      // corpo vazio ou não JSON
    }
    return { status: r.status, dados };
  } finally {
    clearTimeout(timer);
  }
}

/** Lê `{"pacote": "..."}` do corpo; `null` se não vier assim (até 8 KB). */
export async function lerPacote(request) {
  try {
    const texto = await request.text();
    if (texto.length > 8192) return null;
    const pacote = JSON.parse(texto)?.pacote;
    return typeof pacote === 'string' ? pacote : null;
  } catch {
    return null;
  }
}
