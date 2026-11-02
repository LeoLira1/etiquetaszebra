#!/usr/bin/env python3
"""Roda os SQLs REAIS de lib/turso_remoto.dart num SQLite, na ordem em que o app e o MCP os usam.
O libsql_dart e nativo e nao roda em `flutter test`; esta e a prova de que as instrucoes sao
validas e fazem o que o README diz. Tambem confere que o esquema e o do camda-mcp."""
import re
import sqlite3
import sys
from pathlib import Path

texto = (Path(__file__).resolve().parent.parent / "lib" / "turso_remoto.dart").read_text(encoding="utf-8")


def const(nome):
    m = re.search(r"const %s = (?:'''(.*?)'''|\"(.*?)\"|'(.*?)');" % nome, texto, re.S)
    assert m, f"constante {nome} nao encontrada"
    return next(g for g in m.groups() if g is not None)


criar, indice, inserir, imprimir, apagar, baixar = (
    const(n) for n in ("sqlCriarTabela", "sqlCriarIndice", "sqlInserir", "sqlImprimir", "sqlApagar", "sqlBaixar")
)

db = sqlite3.connect(":memory:")
db.execute("CREATE TABLE divergencias (id INTEGER PRIMARY KEY, codigo TEXT)")  # tabela do app de estoque
db.execute("INSERT INTO divergencias VALUES (1, '100')")
antes = db.execute("SELECT sql FROM sqlite_master WHERE name='divergencias'").fetchone()

for _ in range(2):  # IF NOT EXISTS: rodar duas vezes nao pode falhar
    db.execute(criar)
    db.execute(indice)

cols = [r[1] for r in db.execute("PRAGMA table_info(fila_etiquetas)")]
assert cols == ["id", "codigo", "nome", "pares", "status", "criado_em", "impresso_em", "origem"], cols

ins = lambda i, nome, pares: db.execute(inserir, [i, "123", nome, pares, "pendente", "2026-11-02 08:00:00", None, "app"])
ins("a", "ROUNDUP", 3)
ins("a", "OUTRO", 9)  # OR IGNORE: reenvio nao duplica nem sobrescreve
ins("b", "NATIVO", 1)
ins("c", "X", 1)
assert db.execute("SELECT COUNT(*) FROM fila_etiquetas").fetchone()[0] == 3
assert db.execute("SELECT nome, pares FROM fila_etiquetas WHERE id='a'").fetchone() == ("ROUNDUP", 3)

db.execute(imprimir, ["2026-11-02 09:00:00", "b"])
assert db.execute("SELECT status, impresso_em FROM fila_etiquetas WHERE id='b'").fetchone() == ("impresso", "2026-11-02 09:00:00")
db.execute(imprimir, ["2026-11-02 10:00:00", "b"])  # reimpressao atualiza a hora, continua impresso
assert db.execute("SELECT status, impresso_em FROM fila_etiquetas WHERE id='b'").fetchone() == ("impresso", "2026-11-02 10:00:00")

db.execute(apagar, ["c"])
db.execute(apagar, ["c"])  # apagar duas vezes nao falha
assert sorted(r[0] for r in db.execute(baixar)) == ["a", "b"]

depois = db.execute("SELECT sql FROM sqlite_master WHERE name='divergencias'").fetchone()
assert antes == depois, "tabela existente foi alterada"

# o esquema tem de ser identico ao do camda-mcp, se o repositorio estiver ao lado
mcp = Path(__file__).resolve().parent.parent.parent / "camda-mcp" / "src" / "fila_etiquetas.ts"
if mcp.exists():
    t = mcp.read_text(encoding="utf-8")
    m = re.search(r"SQL_CRIAR_FILA = `(.*?)`", t, re.S)
    norm = lambda s: re.sub(r"\s+", " ", s).strip()
    assert norm(m.group(1)) == norm(criar), "esquema do app difere do camda-mcp"
    print("esquema igual ao do camda-mcp")
print("SQL do app OK")
sys.exit(0)
