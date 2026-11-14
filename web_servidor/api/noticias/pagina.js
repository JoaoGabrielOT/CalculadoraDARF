import { criarRotaPrevia, depPrevias } from '../_lib/rede_publica.js';

// Só text/html; o que passar de 1 MB é cortado (o app só lê até </head>).
export const criar = (dep) =>
  criarRotaPrevia({ tipos: /^text\/html\s*(;|$)/i, maxBytes: 1024 * 1024, cortar: true }, dep);

export const { GET, POST, OPTIONS } = criar(depPrevias);
