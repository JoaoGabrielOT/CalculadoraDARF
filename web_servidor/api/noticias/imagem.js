import { criarRotaPrevia, depPrevias } from '../_lib/rede_publica.js';

// Só image/* (menos SVG, que pode levar script); acima de 2 MB -> 413.
export const criar = (dep) => criarRotaPrevia({ tipos: /^image\/(?!svg)/i, maxBytes: 2 * 1024 * 1024 }, dep);

export const { GET, POST, OPTIONS } = criar(depPrevias);
