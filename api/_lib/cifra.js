import { createCipheriv, createDecipheriv, randomBytes } from 'node:crypto';

const PREFIXO = 'v1.';

export class ErroPacote extends Error {
  constructor() {
    super('pacote');
    this.name = 'ErroPacote';
  }
}

/** Chave de 32 bytes em base64; `null` se não tiver esse tamanho. */
export function lerChave(chaveB64) {
  if (typeof chaveB64 !== 'string' || !chaveB64) return null;
  const chave = Buffer.from(chaveB64, 'base64');
  return chave.length === 32 ? chave : null;
}

function chaveOuErro(chaveB64) {
  const chave = lerChave(chaveB64);
  if (!chave) throw new Error('chave');
  return chave;
}

/** AES-256-GCM: 'v1.' + base64url(iv[12] ‖ tag[16] ‖ texto). */
export function cifrar(dados, chaveB64) {
  const iv = randomBytes(12);
  const cifra = createCipheriv('aes-256-gcm', chaveOuErro(chaveB64), iv);
  const texto = Buffer.concat([cifra.update(JSON.stringify(dados), 'utf8'), cifra.final()]);
  return PREFIXO + Buffer.concat([iv, cifra.getAuthTag(), texto]).toString('base64url');
}

/** Lança `ErroPacote` se o pacote não for desta chave, estiver alterado ou malformado. */
export function decifrar(pacote, chaveB64) {
  const chave = chaveOuErro(chaveB64);
  if (typeof pacote !== 'string' || !pacote.startsWith(PREFIXO)) throw new ErroPacote();
  const corpo = pacote.slice(PREFIXO.length);
  const bytes = Buffer.from(corpo, 'base64url');
  // Só a forma canônica: um caractere trocado nunca decodifica para os mesmos bytes.
  if (bytes.length < 29 || bytes.toString('base64url') !== corpo) throw new ErroPacote();
  try {
    const decifra = createDecipheriv('aes-256-gcm', chave, bytes.subarray(0, 12));
    decifra.setAuthTag(bytes.subarray(12, 28));
    const texto = Buffer.concat([decifra.update(bytes.subarray(28)), decifra.final()]);
    return JSON.parse(texto.toString('utf8'));
  } catch {
    throw new ErroPacote();
  }
}
