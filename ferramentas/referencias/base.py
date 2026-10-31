"""Apoio comum dos geradores de referência: relógio e ids congelados, pasta de dados temporária, serialização."""
import contextlib
import json
import math
import sys
import tempfile
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[2]
if str(RAIZ) not in sys.path:
    sys.path.insert(0, str(RAIZ))

import mercado as mk  # noqa: E402
import metas as mt  # noqa: E402
import nucleo as nc  # noqa: E402
import sugestoes as sg  # noqa: E402

AGORA = 1761000000.123
HOJE = (2026, 10, 28)
AGORA_BR = datetime(2026, 10, 28, 12, 0, 0, tzinfo=timezone(timedelta(hours=-3)))


class _DateFixa(date):
    @classmethod
    def today(cls):
        return cls(*HOJE)


@contextlib.contextmanager
def congelar():
    """Congela relógio, ids e 'hoje'; o contador de ids recomeça a cada chamada."""
    contador = [0]

    def novo_id():
        contador[0] += 1
        return f"id{contador[0]:04d}"

    salvos = (nc.agora, nc.novo_id, nc.date, mk.date, sg.date, mt.agora_br)
    nc.agora = lambda: AGORA
    nc.novo_id = novo_id
    nc.date = mk.date = sg.date = _DateFixa
    mt.agora_br = lambda: AGORA_BR
    try:
        yield
    finally:
        nc.agora, nc.novo_id, nc.date, mk.date, sg.date, mt.agora_br = salvos


@contextlib.contextmanager
def pasta_dados():
    """Pasta temporária configurada como pasta de dados do núcleo."""
    antes = nc.DADOS
    with tempfile.TemporaryDirectory() as tmp:
        nc.configurar(tmp)
        try:
            yield Path(tmp)
        finally:
            nc.configurar(antes)


def js(obj):
    """Converte para algo serializável em JSON; recusa NaN e infinitos."""
    if isinstance(obj, float):
        if math.isnan(obj) or math.isinf(obj):
            raise ValueError(f"valor não finito em referência: {obj!r}")
        return obj
    if isinstance(obj, datetime):
        return obj.isoformat()
    if isinstance(obj, date):
        return obj.isoformat()
    if isinstance(obj, dict):
        return {str(k): js(v) for k, v in obj.items()}
    if isinstance(obj, (list, tuple)):
        return [js(v) for v in obj]
    if isinstance(obj, (set, frozenset)):
        return [js(v) for v in sorted(obj)]
    return obj


def arquivos(pasta):
    """Lê todos os .json da pasta: {nome: conteúdo}."""
    return {p.name: json.loads(p.read_text(encoding="utf-8")) for p in sorted(Path(pasta).glob("*.json"))}


def gravar_arquivos(pasta, conteudo):
    """Grava {nome: json} na pasta."""
    for nome, dados in conteudo.items():
        (Path(pasta) / nome).write_text(json.dumps(dados, ensure_ascii=False), encoding="utf-8")


def caso(nome, funcao, entrada, saida):
    return {"nome": nome, "funcao": funcao, "entrada": js(entrada), "saida": js(saida)}
