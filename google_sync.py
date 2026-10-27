import sys
from pathlib import Path

SCOPES = [
    "https://www.googleapis.com/auth/drive.file",
    "https://www.googleapis.com/auth/drive.metadata.readonly",
    "https://www.googleapis.com/auth/spreadsheets.readonly",
]
NOME_PLANILHA = "Calculadora DARF"
SHEETS = "https://sheets.googleapis.com/v4/spreadsheets"
DRIVE = "https://www.googleapis.com/drive/v3"

ABAS = {
    "Resumo": {"cor": "#0e9f6e", "colunas": [
        ("Mês", "centro", 90), ("Status", "centro", 90), ("Vendas de ações (swing)", "moeda", 180),
        ("Isento", "centro", 80), ("Lucro bruto", "resultado", 130), ("Taxas B3", "moeda", 110),
        ("Imposto swing (15%)", "moeda", 150), ("Imposto day trade (20%)", "moeda", 170),
        ("IRRF retido", "moeda", 120), ("Lucro líquido", "resultado", 130),
        ("DARF meses anteriores", "moeda", 170), ("Total DARF", "destaque", 130), ("Modificado", "id", 80)]},
    "Compras": {"cor": "#2563eb", "colunas": [
        ("Mês", "centro", 90), ("Ticker", "negrito", 90), ("Tipo", "centro", 70),
        ("Data da compra", "data", 120), ("Quantidade", "inteiro", 100), ("Preço unitário", "moeda", 120),
        ("Total", "moeda", 130), ("Qtd vendida", "inteiro", 100), ("Qtd restante", "inteiro", 110),
        ("Situação", "centro", 130), ("ID", "id", 80), ("Origem", "id", 80), ("Modificado", "id", 80)]},
    "Vendas": {"cor": "#d97706", "colunas": [
        ("Mês", "centro", 90), ("Ticker", "negrito", 90), ("Tipo", "centro", 70),
        ("Data da compra", "data", 120), ("Preço compra", "moeda", 120), ("Data da venda", "data", 120),
        ("Quantidade", "inteiro", 100), ("Preço venda", "moeda", 120), ("Total venda", "moeda", 130),
        ("Operação", "centro", 130), ("Taxas B3", "moeda", 110), ("Lucro bruto", "resultado", 130),
        ("Lucro após taxas", "resultado", 140), ("Imposto", "moeda", 120), ("ID", "id", 80),
        ("ID compra", "id", 80), ("Modificado", "id", 80)]},
    "Amigos": {"cor": "#7c3aed", "colunas": [
        ("E-mail", "texto", 300), ("Adicionado em", "data", 130), ("Modificado", "id", 80)]},
    "Radar": {"cor": "#0891b2", "colunas": [
        ("Ticker", "negrito", 100), ("Empresa", "texto", 300), ("Adicionado em", "data", 130),
        ("Modificado", "id", 80), ("Posição", "id", 80)]},
    "Caixa": {"cor": "#0f766e", "colunas": [
        ("Saldo informado", "moeda", 150), ("Data do saldo", "data", 130), ("Modificado", "id", 80)]},
    "Exclusões": {"cor": "#6b7280", "oculta": True, "colunas": [
        ("Tipo", "texto", 100), ("Mês", "centro", 90), ("ID", "texto", 280), ("Excluído em", "texto", 140)]},
}


class ErroGoogle(Exception):
    def __init__(self, msg="", status=0):
        super().__init__(msg)
        self.status = status


class SemCredencial(ErroGoogle):
    pass


class LoginNecessario(ErroGoogle):
    pass


class Offline(ErroGoogle):
    pass


def rgb(h):
    h = h.lstrip("#")
    return {"red": int(h[0:2], 16) / 255, "green": int(h[2:4], 16) / 255, "blue": int(h[4:6], 16) / 255}


def letra(n):
    return chr(64 + n)


def celula(v):
    if v is None or v == "":
        return {}
    if isinstance(v, bool):
        return {"userEnteredValue": {"stringValue": "Sim" if v else "Não"}}
    if isinstance(v, (int, float)):
        return {"userEnteredValue": {"numberValue": v}}
    return {"userEnteredValue": {"stringValue": str(v)}}


def caminho_credencial(base):
    candidatos = []
    if getattr(sys, "_MEIPASS", None):
        candidatos.append(Path(sys._MEIPASS) / "credentials.json")
    candidatos.append(Path(base) / "credentials.json")
    return next((p for p in candidatos if p.exists()), None)


class Google:
    def __init__(self, pasta_dados, base):
        self.token_path = Path(pasta_dados) / "token.json"
        self.cred_path = caminho_credencial(base)
        self.sessao = None
        self.email = None

    def tem_credencial(self):
        return self.cred_path is not None

    def tem_token(self):
        return self.token_path.exists()

    # ------------------------------------------------------------ autenticação
    def carregar_token(self):
        from google.oauth2.credentials import Credentials
        from google.auth.transport.requests import Request
        from google.auth.exceptions import RefreshError, TransportError
        if not self.token_path.exists():
            raise LoginNecessario("Faça login com o Google.")
        try:
            creds = Credentials.from_authorized_user_file(str(self.token_path), SCOPES)
        except Exception:
            raise LoginNecessario("Faça login com o Google.")
        if not creds.valid:
            if not creds.refresh_token:
                raise LoginNecessario("Sessão expirada. Faça login novamente.")
            try:
                creds.refresh(Request())
            except RefreshError:
                raise LoginNecessario("Sessão expirada. Faça login novamente.")
            except TransportError as e:
                raise Offline(str(e))
            self.token_path.write_text(creds.to_json(), encoding="utf-8")
        self._iniciar(creds)
        return self.email

    def login(self):
        from google_auth_oauthlib.flow import InstalledAppFlow
        if not self.cred_path:
            raise SemCredencial("Arquivo credentials.json não encontrado.")
        flow = InstalledAppFlow.from_client_secrets_file(str(self.cred_path), SCOPES)
        try:
            creds = flow.run_local_server(
                port=0, open_browser=True, authorization_prompt_message="", timeout_seconds=300,
                success_message="Login concluído. Pode fechar esta aba e voltar para a Calculadora DARF.")
        except Exception:
            raise ErroGoogle("O login não foi concluído.")
        if not creds or not creds.token:
            raise ErroGoogle("O login não foi concluído.")
        self.token_path.write_text(creds.to_json(), encoding="utf-8")
        self._iniciar(creds)
        return self.email

    def login_navegador(self, abrir_url, tempo_limite=600):
        """Login para plataformas sem `webbrowser` nem `wsgiref` (Android).

        Abre a autorização com abrir_url(url), espera o redirecionamento do Google em 127.0.0.1 e troca o
        código pelo token diretamente (OAuth 2.0 com PKCE), sem depender do google-auth-oauthlib.
        """
        import base64
        import hashlib
        import http.server
        import json
        import secrets
        import time
        import urllib.parse
        from datetime import datetime, timedelta, timezone

        import requests
        from google.oauth2.credentials import Credentials

        if not self.cred_path:
            raise SemCredencial("Arquivo credentials.json não encontrado.")
        cliente = json.loads(self.cred_path.read_text(encoding="utf-8-sig"))
        cliente = cliente.get("installed") or cliente.get("web") or cliente

        recebido = {}

        class Retorno(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                if "code=" not in self.path and "error=" not in self.path:
                    self.send_response(404)
                    self.end_headers()
                    return
                recebido["url"] = self.path
                corpo = ("<html><body style='font-family:sans-serif;text-align:center;padding:48px'>"
                         "<h2>Login concluído</h2><p>Volte para a Calculadora DARF.</p></body></html>")
                self.send_response(200)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.end_headers()
                self.wfile.write(corpo.encode("utf-8"))

            def log_message(self, *a):
                pass

        servidor = http.server.HTTPServer(("127.0.0.1", 0), Retorno)
        servidor.timeout = 1
        redirect = f"http://127.0.0.1:{servidor.server_address[1]}/"
        verificador = secrets.token_urlsafe(64)
        desafio = base64.urlsafe_b64encode(hashlib.sha256(verificador.encode("ascii")).digest()).rstrip(b"=")
        estado = secrets.token_urlsafe(16)
        url = cliente["auth_uri"] + "?" + urllib.parse.urlencode({
            "client_id": cliente["client_id"], "redirect_uri": redirect, "response_type": "code",
            "scope": " ".join(SCOPES), "access_type": "offline", "prompt": "consent",
            "code_challenge": desafio.decode("ascii"), "code_challenge_method": "S256", "state": estado})
        try:
            abrir_url(url)
            fim = time.time() + tempo_limite
            while "url" not in recebido and time.time() < fim:
                servidor.handle_request()
        finally:
            servidor.server_close()
        if "url" not in recebido:
            raise ErroGoogle("O login não foi concluído.")
        q = urllib.parse.parse_qs(urllib.parse.urlparse(recebido["url"]).query)
        if q.get("error"):
            raise ErroGoogle("O login foi cancelado." if q["error"][0] == "access_denied"
                             else f"O login não foi concluído: {q['error'][0]}")
        if q.get("state", [""])[0] != estado or not q.get("code"):
            raise ErroGoogle("O login não foi concluído.")
        # O Android bloqueia a rede de apps em segundo plano (o navegador está na frente quando o Google
        # redireciona). Repete a troca do código até o usuário voltar ao app ou o prazo acabar.
        prazo = time.time() + tempo_limite
        while True:
            try:
                r = requests.post(cliente["token_uri"], timeout=30, data={
                    "code": q["code"][0], "client_id": cliente["client_id"],
                    "client_secret": cliente.get("client_secret", ""), "redirect_uri": redirect,
                    "grant_type": "authorization_code", "code_verifier": verificador})
                break
            except (requests.ConnectionError, requests.Timeout) as e:
                if time.time() > prazo:
                    raise Offline(str(e))
                time.sleep(2)
        tok = r.json() if r.content else {}
        if r.status_code >= 400 or "access_token" not in tok:
            raise ErroGoogle(f"O login não foi concluído: {tok.get('error_description') or tok.get('error') or r.status_code}")
        validade = datetime.now(timezone.utc).replace(tzinfo=None) + timedelta(seconds=int(tok.get("expires_in", 3600)) - 60)
        creds = Credentials(token=tok["access_token"], refresh_token=tok.get("refresh_token"),
                            token_uri=cliente["token_uri"], client_id=cliente["client_id"],
                            client_secret=cliente.get("client_secret"), scopes=SCOPES, expiry=validade)
        self.token_path.write_text(creds.to_json(), encoding="utf-8")
        while True:
            try:
                self._iniciar(creds)
                return self.email
            except Offline:
                if time.time() > prazo:
                    raise
                time.sleep(2)

    def _iniciar(self, creds):
        from google.auth.transport.requests import AuthorizedSession
        self.sessao = AuthorizedSession(creds)
        r = self._req("GET", f"{DRIVE}/about", params={"fields": "user(emailAddress)"})
        self.email = r["user"]["emailAddress"].lower()

    def sair(self):
        try:
            self.token_path.unlink()
        except FileNotFoundError:
            pass
        self.sessao = None
        self.email = None

    def _req(self, metodo, url, **kw):
        import requests
        from google.auth.exceptions import RefreshError, TransportError
        if not self.sessao:
            raise LoginNecessario("Faça login com o Google.")
        try:
            r = self.sessao.request(metodo, url, timeout=30, **kw)
        except RefreshError:
            raise LoginNecessario("Sessão expirada. Faça login novamente.")
        except (requests.ConnectionError, requests.Timeout, TransportError) as e:
            raise Offline(str(e))
        if r.status_code == 401:
            raise LoginNecessario("Sessão expirada. Faça login novamente.")
        if r.status_code >= 400:
            try:
                msg = r.json()["error"]["message"]
            except Exception:
                msg = r.text[:300]
            raise ErroGoogle(msg, r.status_code)
        return r.json() if r.content else {}

    # ------------------------------------------------------------ planilha
    def buscar_planilha(self, dono="me"):
        dono = dono.replace("\\", "\\\\").replace("'", "\\'")
        q = (f"name = '{NOME_PLANILHA}' and mimeType = 'application/vnd.google-apps.spreadsheet' "
             f"and trashed = false and '{dono}' in owners")
        r = self._req("GET", f"{DRIVE}/files", params={
            "q": q, "fields": "files(id)", "orderBy": "modifiedTime desc", "pageSize": 5, "spaces": "drive"})
        arquivos = r.get("files", [])
        return arquivos[0]["id"] if arquivos else None

    def planilha_existe(self, sid):
        try:
            r = self._req("GET", f"{DRIVE}/files/{sid}", params={"fields": "id,trashed"})
            return not r.get("trashed")
        except ErroGoogle as e:
            if e.status == 404:
                return False
            raise

    def criar_planilha(self):
        corpo = {
            "properties": {"title": NOME_PLANILHA, "locale": "pt_BR", "timeZone": "America/Sao_Paulo"},
            "sheets": [{"properties": {
                "title": nome, "index": i, "tabColor": rgb(spec["cor"]), "hidden": spec.get("oculta", False),
                "gridProperties": {"rowCount": 1000, "columnCount": len(spec["colunas"]),
                                   "frozenRowCount": 1, "hideGridlines": True}}}
                for i, (nome, spec) in enumerate(ABAS.items())],
        }
        r = self._req("POST", SHEETS, json=corpo)
        sid = r["spreadsheetId"]
        ids = {s["properties"]["title"]: s["properties"]["sheetId"] for s in r["sheets"]}
        self._formatar(sid, ids)
        return sid

    def _garantir_abas(self, sid):
        """Cria (formatadas) as abas que faltam em planilhas de versões anteriores. Retorna as propriedades."""
        meta = self._req("GET", f"{SHEETS}/{sid}", params={
            "fields": "sheets.properties(sheetId,title,gridProperties(rowCount,columnCount))"})
        abas = {s["properties"]["title"]: s["properties"] for s in meta.get("sheets", [])}
        faltando = [a for a in ABAS if a not in abas]
        if not faltando:
            return abas
        reqs = [{"addSheet": {"properties": {
            "title": nome, "tabColor": rgb(ABAS[nome]["cor"]), "hidden": ABAS[nome].get("oculta", False),
            "gridProperties": {"rowCount": 1000, "columnCount": len(ABAS[nome]["colunas"]),
                               "frozenRowCount": 1, "hideGridlines": True}}}} for nome in faltando]
        r = self._req("POST", f"{SHEETS}/{sid}:batchUpdate", json={"requests": reqs})
        ids = {rep["addSheet"]["properties"]["title"]: rep["addSheet"]["properties"]["sheetId"]
               for rep in r.get("replies", []) if "addSheet" in rep}
        self._formatar(sid, ids)
        for nome, g in ids.items():
            abas[nome] = {"sheetId": g, "title": nome,
                          "gridProperties": {"rowCount": 1000, "columnCount": len(ABAS[nome]["colunas"])}}
        return abas

    def _formatar(self, sid, ids):
        cabecalho = rgb("#1f2937")
        reqs = []
        for nome, g in ids.items():
            spec = ABAS[nome]
            n = len(spec["colunas"])
            reqs.append({"updateCells": {
                "range": {"sheetId": g, "startRowIndex": 0, "endRowIndex": 1, "startColumnIndex": 0, "endColumnIndex": n},
                "rows": [{"values": [celula(c[0]) for c in spec["colunas"]]}], "fields": "userEnteredValue"}})
            reqs.append({"repeatCell": {
                "range": {"sheetId": g, "startRowIndex": 0, "endRowIndex": 1},
                "cell": {"userEnteredFormat": {
                    "backgroundColor": cabecalho, "horizontalAlignment": "CENTER", "verticalAlignment": "MIDDLE",
                    "wrapStrategy": "WRAP",
                    "textFormat": {"foregroundColor": rgb("#ffffff"), "bold": True, "fontSize": 10}}},
                "fields": "userEnteredFormat(backgroundColor,horizontalAlignment,verticalAlignment,wrapStrategy,textFormat)"}})
            reqs.append({"updateDimensionProperties": {
                "range": {"sheetId": g, "dimension": "ROWS", "startIndex": 0, "endIndex": 1},
                "properties": {"pixelSize": 38}, "fields": "pixelSize"}})
            reqs.append({"updateDimensionProperties": {
                "range": {"sheetId": g, "dimension": "ROWS", "startIndex": 1},
                "properties": {"pixelSize": 26}, "fields": "pixelSize"}})
            reqs.append({"addBanding": {"bandedRange": {
                "range": {"sheetId": g, "startRowIndex": 0, "startColumnIndex": 0, "endColumnIndex": n},
                "rowProperties": {"headerColor": cabecalho, "firstBandColor": rgb("#ffffff"),
                                  "secondBandColor": rgb("#f3f6f9")}}}})
            for j, (_, tipo, largura) in enumerate(spec["colunas"]):
                col = {"sheetId": g, "startRowIndex": 1, "startColumnIndex": j, "endColumnIndex": j + 1}
                reqs.append({"updateDimensionProperties": {
                    "range": {"sheetId": g, "dimension": "COLUMNS", "startIndex": j, "endIndex": j + 1},
                    "properties": {"pixelSize": largura, "hiddenByUser": tipo == "id"},
                    "fields": "pixelSize,hiddenByUser"}})
                fmt = {"verticalAlignment": "MIDDLE", "textFormat": {"fontSize": 10}}
                if tipo == "centro":
                    fmt["horizontalAlignment"] = "CENTER"
                elif tipo == "negrito":
                    fmt["textFormat"]["bold"] = True
                elif tipo == "data":
                    fmt["numberFormat"] = {"type": "DATE", "pattern": "dd/mm/yyyy"}
                    fmt["horizontalAlignment"] = "CENTER"
                elif tipo == "inteiro":
                    fmt["numberFormat"] = {"type": "NUMBER", "pattern": "#,##0"}
                    fmt["horizontalAlignment"] = "RIGHT"
                elif tipo in ("moeda", "resultado", "destaque"):
                    fmt["numberFormat"] = {"type": "CURRENCY", "pattern": '"R$ "#,##0.00'}
                    fmt["horizontalAlignment"] = "RIGHT"
                    if tipo == "destaque":
                        fmt["textFormat"] = {"fontSize": 10, "bold": True, "foregroundColor": rgb("#0b8a5f")}
                reqs.append({"repeatCell": {
                    "range": col, "cell": {"userEnteredFormat": fmt},
                    "fields": "userEnteredFormat(numberFormat,horizontalAlignment,verticalAlignment,textFormat)"}})
                if tipo == "resultado":
                    for cond, cor in (("NUMBER_LESS", "#dc2626"), ("NUMBER_GREATER", "#0b8a5f")):
                        reqs.append({"addConditionalFormatRule": {"index": 0, "rule": {
                            "ranges": [col],
                            "booleanRule": {"condition": {"type": cond, "values": [{"userEnteredValue": "0"}]},
                                            "format": {"textFormat": {"foregroundColor": rgb(cor)}}}}}})
        self._req("POST", f"{SHEETS}/{sid}:batchUpdate", json={"requests": reqs})

    def escrever(self, sid, dados):
        """Substitui o conteúdo de cada aba (exceto o cabeçalho) em uma única operação atômica."""
        abas = self._garantir_abas(sid)
        reqs = []
        for aba, linhas in dados.items():
            p = abas[aba]
            g = p["sheetId"]
            colunas = ABAS[aba]["colunas"]
            n = len(colunas)
            total = p["gridProperties"].get("rowCount", 1000)
            if len(linhas) + 1 > total:
                reqs.append({"appendDimension": {"sheetId": g, "dimension": "ROWS",
                                                 "length": len(linhas) + 1 - total + 200}})
            # planilhas de versões anteriores podem ter menos colunas
            atuais = p["gridProperties"].get("columnCount", n)
            if atuais < n:
                reqs.append({"appendDimension": {"sheetId": g, "dimension": "COLUMNS", "length": n - atuais}})
                for j in range(atuais, n):
                    if colunas[j][1] == "id":
                        reqs.append({"updateDimensionProperties": {
                            "range": {"sheetId": g, "dimension": "COLUMNS", "startIndex": j, "endIndex": j + 1},
                            "properties": {"hiddenByUser": True}, "fields": "hiddenByUser"}})
            reqs.append({"updateCells": {
                "range": {"sheetId": g, "startRowIndex": 0, "endRowIndex": 1, "startColumnIndex": 0,
                          "endColumnIndex": n},
                "rows": [{"values": [celula(c[0]) for c in colunas]}], "fields": "userEnteredValue"}})
            reqs.append({"updateCells": {
                "range": {"sheetId": p["sheetId"], "startRowIndex": 1, "startColumnIndex": 0, "endColumnIndex": n},
                "rows": [{"values": [celula(v) for v in linha]} for linha in linhas],
                "fields": "userEnteredValue"}})
        self._req("POST", f"{SHEETS}/{sid}:batchUpdate", json={"requests": reqs})

    def ler(self, sid):
        meta = self._req("GET", f"{SHEETS}/{sid}", params={
            "fields": "sheets.properties(title,gridProperties.columnCount)"})
        colunas = {s["properties"]["title"]: s["properties"].get("gridProperties", {}).get("columnCount", 26)
                   for s in meta.get("sheets", [])}
        nomes = [a for a in ABAS if a in colunas]
        res = {a: [] for a in ABAS}
        if not nomes:
            return res
        r = self._req("GET", f"{SHEETS}/{sid}/values:batchGet", params={
            "ranges": [f"'{a}'!A2:{letra(min(len(ABAS[a]['colunas']), colunas[a]))}" for a in nomes],
            "valueRenderOption": "UNFORMATTED_VALUE", "dateTimeRenderOption": "SERIAL_NUMBER"})
        for aba, vr in zip(nomes, r.get("valueRanges", [])):
            n = len(ABAS[aba]["colunas"])
            res[aba] = [(linha + [""] * n)[:n] for linha in vr.get("values", [])]
        return res

    # ------------------------------------------------------------ compartilhamento
    def compartilhar(self, sid, email):
        self._req("POST", f"{DRIVE}/files/{sid}/permissions",
                  params={"sendNotificationEmail": "true",
                          "emailMessage": f"{self.email} compartilhou as operações da Calculadora DARF com você."},
                  json={"role": "reader", "type": "user", "emailAddress": email})

    def descompartilhar(self, sid, email):
        r = self._req("GET", f"{DRIVE}/files/{sid}/permissions",
                      params={"fields": "permissions(id,emailAddress,role)"})
        for p in r.get("permissions", []):
            if (p.get("emailAddress") or "").lower() == email and p.get("role") != "owner":
                self._req("DELETE", f"{DRIVE}/files/{sid}/permissions/{p['id']}")
