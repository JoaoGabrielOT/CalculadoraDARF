"""Verificação e instalação de novas versões publicadas nas releases do GitHub."""
import hashlib
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

from versao import VERSAO

REPOSITORIO = "JoaoGabrielOT/CalculadoraDARF"
NOME_ASSET = "CalculadoraDARF.exe"
API = f"https://api.github.com/repos/{REPOSITORIO}/releases/latest"


class ErroAtualizacao(Exception):
    pass


def versao_tupla(v):
    nums = re.findall(r"\d+", v.lstrip("vV"))
    return tuple(int(n) for n in nums[:3]) + (0,) * (3 - len(nums[:3]))


def pode_atualizar():
    """A troca automática só funciona no .exe gerado pelo PyInstaller no Windows."""
    return getattr(sys, "frozen", False) and sys.platform == "win32"


def limpar_sobras():
    """Apaga um download de atualização que não chegou a ser instalado."""
    try:
        exe = Path(sys.executable)
        exe.with_name(exe.stem + ".novo.exe").unlink(missing_ok=True)
    except OSError:
        pass


def verificar(nome_asset=NOME_ASSET):
    """Retorna os dados da nova versão ou None. Executar fora da thread da interface."""
    import requests
    r = requests.get(API, timeout=15, headers={"Accept": "application/vnd.github+json",
                                               "User-Agent": "CalculadoraDARF"})
    if r.status_code == 404:
        return None
    r.raise_for_status()
    rel = r.json()
    if rel.get("draft") or rel.get("prerelease"):
        return None
    tag = rel.get("tag_name", "")
    if versao_tupla(tag) <= versao_tupla(VERSAO):
        return None
    asset = next((a for a in rel.get("assets", []) if a.get("name") == nome_asset), None)
    if not asset:
        return None
    digest = asset.get("digest") or ""
    return {"versao": tag.lstrip("vV"), "notas": (rel.get("body") or "").strip(),
            "url": asset["browser_download_url"], "tamanho": asset.get("size", 0),
            "sha256": digest.split(":", 1)[1] if digest.startswith("sha256:") else ""}


def baixar(info, progresso, destino=None):
    """Baixa a nova versão (por padrão ao lado do .exe atual). progresso(baixado, total) é chamado no download."""
    import requests
    if destino is None:
        exe = Path(sys.executable)
        destino = exe.with_name(exe.stem + ".novo.exe")
    destino = Path(destino)
    h = hashlib.sha256()
    baixado = 0
    try:
        return _baixar(info, progresso, destino, h, requests)
    except BaseException:
        destino.unlink(missing_ok=True)
        raise


def _baixar(info, progresso, destino, h, requests):
    baixado = 0
    with requests.get(info["url"], stream=True, timeout=30, headers={"User-Agent": "CalculadoraDARF"}) as r:
        r.raise_for_status()
        total = int(r.headers.get("Content-Length") or info["tamanho"] or 0)
        with open(destino, "wb") as f:
            for bloco in r.iter_content(chunk_size=256 * 1024):
                if not bloco:
                    continue
                f.write(bloco)
                h.update(bloco)
                baixado += len(bloco)
                progresso(baixado, total)
    if info["tamanho"] and baixado != info["tamanho"]:
        destino.unlink(missing_ok=True)
        raise ErroAtualizacao("O download ficou incompleto.")
    if info["sha256"] and h.hexdigest().lower() != info["sha256"].lower():
        destino.unlink(missing_ok=True)
        raise ErroAtualizacao("O arquivo baixado não confere com o publicado.")
    return destino


SCRIPT = r"""@echo off
set "NOVO=%~1"
set "EXE=%~2"
:espera
tasklist /FI "PID eq %~3" 2>nul | find "%~3" >nul && (ping -n 2 127.0.0.1 >nul & goto espera)
tasklist /FI "PID eq %~4" 2>nul | find "%~4" >nul && (ping -n 2 127.0.0.1 >nul & goto espera)
set /a tentativas=0
:troca
move /y "%NOVO%" "%EXE%" >nul 2>&1
if not errorlevel 1 goto pronto
set /a tentativas+=1
if %tentativas% geq 30 goto fim
ping -n 2 127.0.0.1 >nul
goto troca
:pronto
start "" "%EXE%"
:fim
(goto) 2>nul & del "%~f0"
"""


def instalar_e_reiniciar(novo):
    """Agenda a troca do .exe para depois que o app fechar e reabre a nova versão.

    O script só contém ASCII; caminhos e PIDs vão como argumentos para funcionar com pastas acentuadas.
    O app deve ser encerrado logo após esta chamada.
    """
    exe = Path(sys.executable)
    bat = Path(tempfile.gettempdir()) / "CalculadoraDARF_atualizar.cmd"
    bat.write_bytes(SCRIPT.replace("\n", "\r\n").encode("ascii"))
    env = {k: v for k, v in os.environ.items() if not (k.startswith("_PYI") or k == "_MEIPASS2")}
    env["PYINSTALLER_RESET_ENVIRONMENT"] = "1"
    # aspas externas extras: o cmd /c remove o primeiro e o último caractere de aspas da linha
    args = f'cmd /c ""{bat}" "{novo}" "{exe}" {os.getpid()} {os.getppid()}"'
    base = 0x08000000 | 0x00000200  # CREATE_NO_WINDOW | CREATE_NEW_PROCESS_GROUP
    try:
        subprocess.Popen(args, creationflags=base | 0x01000000, env=env, cwd=str(exe.parent))  # BREAKAWAY_FROM_JOB
    except OSError:
        subprocess.Popen(args, creationflags=base, env=env, cwd=str(exe.parent))
