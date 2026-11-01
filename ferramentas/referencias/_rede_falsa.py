"""Rede falsa dos geradores de referência: um módulo `requests` sintético que serve respostas programadas e grava
cada pedido. Também esconde módulos opcionais (`yfinance`, `xml.etree.ElementTree`) e cria o `google.auth.exceptions`
quando o google-auth não está instalado. Nenhum acesso à internet.
"""
import contextlib
import json as _json
import sys
import types
from urllib.parse import urlencode


class RequestException(IOError):
    pass


class ConnectionError(RequestException):  # noqa: A001 (mesmo nome do requests)
    pass


class Timeout(RequestException):
    pass


class HTTPError(RequestException):
    pass


class _Cabecalhos(dict):
    """Cabeçalhos sem diferença entre maiúsculas e minúsculas (como o CaseInsensitiveDict do requests)."""

    def __init__(self, dados=None):
        super().__init__()
        for k, v in (dados or {}).items():
            self[k] = v

    def __setitem__(self, k, v):
        super().__setitem__(k.lower(), v)

    def __getitem__(self, k):
        return super().__getitem__(k.lower())

    def get(self, k, padrao=None):
        return super().get(k.lower(), padrao)

    def __contains__(self, k):
        return super().__contains__(k.lower())


class Resposta:
    """Resposta do requests: status, corpo (json, texto ou bytes), cabeçalhos, url final e motivo."""

    def __init__(self, status=200, json=None, texto=None, conteudo=None, cabecalhos=None, url=None, motivo="OK"):
        self.status_code = status
        self._json = json
        if conteudo is not None:
            self.content = conteudo
        elif texto is not None:
            self.content = texto.encode("utf-8")
        elif json is not None:
            self.content = _json.dumps(json, ensure_ascii=False).encode("utf-8")
        else:
            self.content = b""
        self._texto = texto
        self.headers = _Cabecalhos(cabecalhos)
        self.url = url
        self.reason = motivo
        self.encoding = "utf-8"

    @property
    def text(self):
        if self._texto is not None:
            return self._texto
        return self.content.decode(self.encoding or "utf-8", errors="replace")

    def json(self):
        if self._json is not None:
            return self._json
        return _json.loads(self.text)

    def iter_content(self, n=1):
        for i in range(0, len(self.content), n):
            yield self.content[i:i + n]

    def raise_for_status(self):
        """Mesmo texto do requests: '<status> Client|Server Error: <motivo> for url: <url>'."""
        if 400 <= self.status_code < 500:
            tipo = "Client Error"
        elif 500 <= self.status_code < 600:
            tipo = "Server Error"
        else:
            return
        raise HTTPError(f"{self.status_code} {tipo}: {self.reason} for url: {self.url}")

    def close(self):
        pass

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False


def _lista_de_texto(valor):
    if isinstance(valor, (list, tuple)):
        return [str(v) for v in valor]
    return [str(valor)]


class _Rede:
    """Context manager que instala o `requests` falso em sys.modules e o remove ao sair."""

    def __init__(self, respostas, pedidos):
        self._respostas = list(respostas)
        self._pedidos = pedidos
        self._usadas = 0
        self._antes = None

    def _servir(self, metodo, url, params=None, headers=None, data=None, json=None, **_):
        params = params or {}
        self._pedidos.append({
            "metodo": metodo, "url": url,
            "params": {str(k): _lista_de_texto(v) for k, v in params.items()},
            "cabecalhos": dict(headers or {}), "dados": data, "json": json})
        if not self._respostas:
            raise AssertionError(f"pedido sem resposta programada: {metodo} {url}")
        item = self._respostas[min(self._usadas, len(self._respostas) - 1)]
        self._usadas += 1
        if isinstance(item, BaseException):
            raise item
        if item.url is None:
            item.url = url + (("?" + urlencode(params, doseq=True)) if params else "")
        return item

    def _modulo(self):
        m = types.ModuleType("requests")
        m.get = lambda url, **kw: self._servir("GET", url, **kw)
        m.post = lambda url, **kw: self._servir("POST", url, **kw)
        m.RequestException, m.ConnectionError = RequestException, ConnectionError
        m.Timeout, m.HTTPError = Timeout, HTTPError
        m.exceptions = types.SimpleNamespace(RequestException=RequestException, ConnectionError=ConnectionError,
                                             Timeout=Timeout, HTTPError=HTTPError)
        return m

    def __enter__(self):
        self._antes = sys.modules.get("requests")
        sys.modules["requests"] = self._modulo()
        return self

    def __exit__(self, *args):
        if self._antes is None:
            sys.modules.pop("requests", None)
        else:
            sys.modules["requests"] = self._antes
        return False


def rede(respostas):
    """(context manager, pedidos). `respostas`: lista de Resposta (ou exceção, que é lançada) servidas na ordem;
    esgotada, repete a última. Cada pedido gravado é
    {"metodo", "url", "params": {k: [str]}, "cabecalhos", "dados", "json"}."""
    pedidos = []
    return _Rede(respostas, pedidos), pedidos


@contextlib.contextmanager
def sem_modulo(nome):
    """Faz `import <nome>` falhar com ImportError (inclusive `from pai import filho`)."""
    pai, _, filho = nome.rpartition(".")
    antes = sys.modules.get(nome, False)
    attr = False
    if pai and pai in sys.modules and hasattr(sys.modules[pai], filho):
        attr = getattr(sys.modules[pai], filho)
        delattr(sys.modules[pai], filho)
    sys.modules[nome] = None
    try:
        yield
    finally:
        if antes is False:
            sys.modules.pop(nome, None)
        else:
            sys.modules[nome] = antes
        if attr is not False:
            setattr(sys.modules[pai], filho, attr)


@contextlib.contextmanager
def google_falso():
    """Garante `google.auth.exceptions` (RefreshError, TransportError); sem google-auth, cria módulos sintéticos."""
    try:
        import google.auth.exceptions  # noqa: F401
    except ImportError:
        nomes = ("google", "google.auth", "google.auth.exceptions")
        antes = {n: sys.modules.get(n) for n in nomes}
        exc = types.ModuleType("google.auth.exceptions")

        class GoogleAuthError(Exception):
            pass

        class RefreshError(GoogleAuthError):
            pass

        class TransportError(GoogleAuthError):
            pass

        exc.GoogleAuthError, exc.RefreshError, exc.TransportError = GoogleAuthError, RefreshError, TransportError
        auth = types.ModuleType("google.auth")
        auth.exceptions = exc
        g = types.ModuleType("google")
        g.auth = auth
        g.__path__ = []
        auth.__path__ = []
        sys.modules.update({"google": g, "google.auth": auth, "google.auth.exceptions": exc})
        try:
            yield
        finally:
            for n, m in antes.items():
                if m is None:
                    sys.modules.pop(n, None)
                else:
                    sys.modules[n] = m
    else:
        yield


def erro(e):
    """{"erro": tipo, "mensagem": str(e)}; 'Too Many Requests' vira LimiteConsultas e HTTPError vira ErroHttp."""
    if isinstance(e, RuntimeError) and str(e) == "Too Many Requests":
        nome = "LimiteConsultas"
    elif isinstance(e, HTTPError) or type(e).__name__ == "HTTPError":
        nome = "ErroHttp"
    else:
        nome = type(e).__name__
    return {"erro": nome, "mensagem": str(e)}
