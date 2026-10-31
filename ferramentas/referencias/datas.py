"""Referências de datas: serial do Sheets, meses, dia da semana e datetime.fromisoformat com fuso."""
from datetime import date, datetime, timedelta

from . import base

nc = base.nc
mt = base.mt


def _erro(fn, *args):
    try:
        return fn(*args)
    except Exception as e:  # noqa: BLE001 - o nome da exceção é a referência
        return {"erro": type(e).__name__}


def _instante(texto):
    try:
        dt = mt._dt(texto)  # metas.py:37-39: sem fuso, vale Brasília
    except Exception as e:  # noqa: BLE001
        return {"erro": type(e).__name__}
    return _resumo(dt)


def _resumo(dt):
    return {
        "ts": dt.timestamp(),
        "desvio": int(dt.utcoffset().total_seconds()),
        "data": dt.date().isoformat(),
        "hora": dt.strftime("%H:%M"),
        "iso": dt.isoformat(timespec="seconds"),
    }


def _instante_de_ts(ts):
    return _resumo(datetime.fromtimestamp(ts, mt.FUSO))


def casos():
    out = []
    for i, v in enumerate([45000, 45000.7, 0, "05/10/2026", "5/1/2026", "2026-10-05", "20261005", "31/02/2026", "x"]):
        out.append(base.caso(f"de_serial {i}", "de_serial", {"v": v}, _erro(nc.de_serial, v)))
    for v in [-1.5, 1e-9, "  12/3/2026 ", "1/1/2026x", "00/01/2026", "01/13/2026", "1/1/26", "2026-1-5"]:
        out.append(base.caso(f"de_serial extra {v!r}", "de_serial", {"v": v}, _erro(nc.de_serial, v)))
    for i, v in enumerate(["10/2026", " 1/2026 ", "2026-10", 45000, "12/2026/1", "a/2026", "+3/2026", "03/0099"]):
        out.append(base.caso(f"mes_iso {i}", "mes_iso", {"v": v}, _erro(nc.mes_iso, v)))
    for iso in ["1899-12-30", "1899-12-29", "1970-01-01", "2024-02-29", "2026-10-05", "2100-03-01"]:
        out.append(base.caso(f"serial {iso}", "serial", {"iso": iso}, nc.serial(iso)))
    for mes in ["2026-10", "2026-12", "2025-01", "2024-02", "2100-02", "2000-02", "1999-12"]:
        out.append(base.caso(f"proximo_mes {mes}", "proximo_mes", {"mes": mes}, nc.proximo_mes(mes)))
        out.append(base.caso(f"limites_mes {mes}", "limites_mes", {"mes": mes}, list(nc.limites_mes(mes))))
    for iso in ["2026-10-05", "2024-02-29", "1999-01-31"]:
        out.append(base.caso(f"fmt_data {iso}", "fmt_data", {"iso": iso}, nc.fmt_data(iso)))
    for mes in ["2026-10", "2024-02"]:
        out.append(base.caso(f"fmt_mes {mes}", "fmt_mes", {"mes": mes}, nc.fmt_mes(mes)))
    d0 = date(2025, 1, 1)
    for i in range(1000):
        d = d0 + timedelta(days=i)
        out.append(base.caso(f"weekday {d}", "weekday", {"iso": d.isoformat()}, d.weekday()))
    for t in ["2026-10-20T11:00:00-03:00", "2026-10-20 11:00", "2026-10-20", "2026-10-20T14:00:00Z",
              "2026-10-20T11:00:00.123456+00:00", "20/10/2026", "2026-10-20T11", "2026-10-20T11:05:07.5+05:30",
              "2026-10-20T23:59:59-23:59", "2026-02-30", "2026-10-20T25:00", "2026-10-20T11:00:00+24:00",
              "2026-10-20T11:00:00.1234567", " 2026-10-20"]:
        out.append(base.caso(f"fromisoformat {t!r}", "fromisoformat", {"texto": t}, _instante(t)))
    for ts in [1761000000.123, 0, 1761000000.1234565, 1761000000.0000005, -1.5, 1761000000.9999996]:
        out.append(base.caso(f"fromtimestamp {ts!r}", "fromtimestamp", {"ts": ts}, _instante_de_ts(ts)))
    return out
