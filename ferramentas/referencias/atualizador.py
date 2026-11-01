"""Referências de `versao_tupla` e `verificar` (atualizador.py:21-23, 40-60).

O módulo `requests` é trocado pela rede falsa (`_rede_falsa`) e `atu.VERSAO` recebe a versão atual de cada caso.

Funções (campo `funcao` de cada caso):
- versao_tupla: entrada texto; saída [maior, menor, correção]
- verificar: entrada {versao_atual, nome_asset, status, json}; saída {pedidos, resultado: dict ou null}
  ou, em falha, {pedidos, erro, mensagem}
"""
import http
from unittest import mock

import atualizador as atu

from . import _rede_falsa as rf
from . import base

TAGS = ["2.0.0", "v1.12.1", "V2", "2.0.0-beta1", "1.2.3.4", "abc", "", "v10.0", "1.2", "01.002.0003"]

ASSET_EXE = "CalculadoraDARF.exe"
ASSET_APK = "CalculadoraDARF.apk"
URL = "https://github.com/JoaoGabrielOT/CalculadoraDARF/releases/download/v2.1.0/"
SHA = "ab" * 32


def _asset(nome=ASSET_EXE, digest=SHA, tamanho=1234567):
    a = {"name": nome, "browser_download_url": URL + nome}
    if digest is not ...:
        a["digest"] = None if digest is None else ("sha256:" + digest if digest else "")
    if tamanho is not ...:
        a["size"] = tamanho
    return a


def _release(tag="v2.1.0", body="Notas da versão.", assets=None, **extra):
    r = {"tag_name": tag, "draft": False, "prerelease": False, "body": body,
         "assets": [_asset(), _asset(ASSET_APK)] if assets is None else assets}
    r.update(extra)
    return r


# (nome, versão atual, nome do asset, status, json)
VERIFICAR = [
    ("nova com digest", "1.12.1", ASSET_EXE, 200, _release()),
    ("nova com digest em maiúsculas", "1.12.1", ASSET_EXE, 200,
     _release(assets=[_asset(digest=SHA.upper())])),
    ("nova sem digest", "1.12.1", ASSET_EXE, 200, _release(assets=[_asset(digest=...)])),
    ("nova com digest nulo", "1.12.1", ASSET_EXE, 200, _release(assets=[_asset(digest=None)])),
    ("nova com digest de outro tipo", "1.12.1", ASSET_EXE, 200,
     _release(assets=[{**_asset(digest=...), "digest": "sha512:" + "cd" * 64}])),
    ("nova sem tamanho", "1.12.1", ASSET_EXE, 200, _release(assets=[_asset(tamanho=...)])),
    ("nova com notas com espaços", "1.12.1", ASSET_EXE, 200, _release(body="  \n- item um\n- item dois\n\n ")),
    ("nova com body nulo", "1.12.1", ASSET_EXE, 200, _release(body=None)),
    ("nova sem body", "1.12.1", ASSET_EXE, 200, {k: v for k, v in _release().items() if k != "body"}),
    ("nova tag com V maiúsculo", "1.12.1", ASSET_EXE, 200, _release(tag="V2.1.0")),
    ("nova tag sem v", "1.12.1", ASSET_EXE, 200, _release(tag="2.1.0")),
    ("nova asset apk", "1.12.1", ASSET_APK, 200, _release()),
    ("nova em relação à 2.0.0", "2.0.0", ASSET_EXE, 200, _release(tag="v2.0.1")),
    ("draft", "1.12.1", ASSET_EXE, 200, _release(draft=True)),
    ("prerelease", "1.12.1", ASSET_EXE, 200, _release(prerelease=True)),
    ("mesma versão", "2.1.0", ASSET_EXE, 200, _release()),
    ("mesma versão com v", "2.0.0", ASSET_EXE, 200, _release(tag="v2.0.0")),
    ("mais antiga", "2.0.0", ASSET_EXE, 200, _release(tag="v1.12.1")),
    ("sem o asset", "1.12.1", ASSET_EXE, 200, _release(assets=[_asset(ASSET_APK)])),
    ("sem assets", "1.12.1", ASSET_EXE, 200, _release(assets=[])),
    ("sem tag", "1.12.1", ASSET_EXE, 200, {"draft": False, "prerelease": False, "assets": [_asset()]}),
    ("http 404", "1.12.1", ASSET_EXE, 404, {"message": "Not Found"}),
    ("http 403", "1.12.1", ASSET_EXE, 403, {"message": "rate limit exceeded"}),
    ("http 500", "1.12.1", ASSET_EXE, 500, {"message": "Server Error"}),
]


def _verificar(versao_atual, nome_asset, status, corpo):
    resposta = rf.Resposta(status, json=corpo, motivo=http.HTTPStatus(status).phrase)
    cm, pedidos = rf.rede([resposta])
    saida = {}
    with cm, mock.patch.object(atu, "VERSAO", versao_atual):
        try:
            saida["resultado"] = atu.verificar(nome_asset)
        except (RuntimeError, rf.RequestException) as e:
            saida.update(rf.erro(e))
    return {"pedidos": pedidos, **saida}


def casos():
    out = [base.caso(repr(t), "versao_tupla", t, list(atu.versao_tupla(t))) for t in TAGS]
    for nome, atual, asset, status, corpo in VERIFICAR:
        entrada = {"versao_atual": atual, "nome_asset": asset, "status": status, "json": corpo}
        out.append(base.caso(nome, "verificar", entrada, _verificar(atual, asset, status, corpo)))
    return out
