/// Endereço público da Vercel (sobrescrevível com --dart-define=URL_VERCEL).
const urlVercel = String.fromEnvironment(
  'URL_VERCEL',
  defaultValue: 'https://calculadora-darf.vercel.app',
);

/// Base da API: a própria origem quando a página vem da Vercel; senão a Vercel.
Uri enderecoApi(Uri pagina) {
  final vercel = Uri.parse(urlVercel);
  if (pagina.host == vercel.host) {
    return Uri.parse('${pagina.origin}/api');
  }
  return Uri.parse('$urlVercel/api');
}
