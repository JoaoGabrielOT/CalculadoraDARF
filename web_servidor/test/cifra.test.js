import test from 'node:test';
import assert from 'node:assert/strict';
import { cifrar, decifrar, ErroPacote } from '../api/_lib/cifra.js';

const CHAVE = Buffer.alloc(32, 7).toString('base64');
const OUTRA = Buffer.alloc(32, 9).toString('base64');

test('ida e volta', () => {
  const pacote = cifrar({ r: 'rt-1', t: 123 }, CHAVE);
  assert.match(pacote, /^v1\.[A-Za-z0-9_-]+$/);
  assert.deepEqual(decifrar(pacote, CHAVE), { r: 'rt-1', t: 123 });
});

test('nonce aleatório: o mesmo dado cifra diferente', () => {
  assert.notEqual(cifrar({ a: 1 }, CHAVE), cifrar({ a: 1 }, CHAVE));
});

test('qualquer caractere trocado -> ErroPacote', () => {
  const pacote = cifrar({ r: 'rt-1' }, CHAVE);
  for (let i = 3; i < pacote.length; i++) {
    const c = pacote[i] === 'A' ? 'B' : 'A';
    const alterado = pacote.slice(0, i) + c + pacote.slice(i + 1);
    assert.throws(() => decifrar(alterado, CHAVE), ErroPacote, `posição ${i}`);
  }
});

test('outra chave -> ErroPacote', () => {
  assert.throws(() => decifrar(cifrar({ r: 'x' }, CHAVE), OUTRA), ErroPacote);
});

test('sem v1. -> ErroPacote', () => {
  const pacote = cifrar({ r: 'x' }, CHAVE);
  assert.throws(() => decifrar(pacote.slice(3), CHAVE), ErroPacote);
  assert.throws(() => decifrar('v2.' + pacote.slice(3), CHAVE), ErroPacote);
});

test('curto, vazio ou não texto -> ErroPacote', () => {
  for (const p of ['v1.', 'v1.AAAA', '', undefined, null, 12]) {
    assert.throws(() => decifrar(p, CHAVE), ErroPacote);
  }
});
