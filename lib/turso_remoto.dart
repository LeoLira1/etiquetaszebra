import 'dart:async';

import 'package:libsql_dart/libsql_dart.dart';

import 'fonte_remota.dart';
import 'item_fila.dart';

/// Esquema da tabela nova. E o MESMO texto que o camda-mcp usa (`src/fila_etiquetas.ts`):
/// quem chegar primeiro cria, o outro so reaproveita.
const sqlCriarTabela = '''
CREATE TABLE IF NOT EXISTS fila_etiquetas (
  id TEXT PRIMARY KEY,
  codigo TEXT NOT NULL,
  nome TEXT NOT NULL,
  pares INTEGER NOT NULL DEFAULT 1,
  status TEXT NOT NULL DEFAULT 'pendente',
  criado_em TEXT NOT NULL,
  impresso_em TEXT,
  origem TEXT NOT NULL DEFAULT 'app'
)''';

const sqlCriarIndice = 'CREATE INDEX IF NOT EXISTS idx_fila_etiquetas_status ON fila_etiquetas (status, criado_em)';

const sqlInserir = '''
INSERT OR IGNORE INTO fila_etiquetas (id, codigo, nome, pares, status, criado_em, impresso_em, origem)
VALUES (?, ?, ?, ?, ?, ?, ?, ?)''';

const sqlImprimir = "UPDATE fila_etiquetas SET status = 'impresso', impresso_em = ? WHERE id = ?";

const sqlApagar = 'DELETE FROM fila_etiquetas WHERE id = ?';

const sqlBaixar = 'SELECT id, codigo, nome, pares, status, criado_em, impresso_em, origem FROM fila_etiquetas';

/// Fala com o Turso pelo `libsql_dart` (conexao remota, a mesma dependencia do Gondolas e do Risca).
/// Cada chamada tem prazo: sem rede o app nao pode ficar preso.
class TursoRemoto implements FonteRemota {
  TursoRemoto(this.url, this.token, {this.prazo = const Duration(seconds: 12)});

  final String url;
  final String token;
  final Duration prazo;

  LibsqlClient? _client;
  bool _esquemaOk = false;

  Future<LibsqlClient> _conectar() async {
    var c = _client;
    if (c != null) return c;
    c = LibsqlClient.remote(url.trim(), authToken: token.trim());
    await c.connect();
    return _client = c;
  }

  /// Qualquer falha descarta a conexao: a proxima tentativa abre outra.
  Future<T> _rodar<T>(Future<T> Function(LibsqlClient c) acao) async {
    try {
      return await (() async => acao(await _conectar()))().timeout(prazo);
    } catch (_) {
      final c = _client;
      _client = null;
      if (c != null) unawaited(c.dispose().catchError((_) {}));
      rethrow;
    }
  }

  @override
  Future<void> garantirEsquema() async {
    if (_esquemaOk) return;
    await _rodar((c) async {
      await c.execute(sqlCriarTabela);
      await c.execute(sqlCriarIndice);
    });
    _esquemaOk = true;
  }

  @override
  Future<void> aplicar(Operacao op) => _rodar((c) async {
        switch (op.tipo) {
          case TipoOperacao.criar:
            final i = op.item!;
            await c.execute(sqlInserir, positional: [
              i.id,
              i.codigo,
              i.nome,
              i.pares,
              i.status,
              i.criadoEm,
              i.impressoEm,
              i.origem,
            ]);
          case TipoOperacao.imprimir:
            await c.execute(sqlImprimir, positional: [op.em, op.id]);
          case TipoOperacao.apagar:
            await c.execute(sqlApagar, positional: [op.id]);
        }
      });

  @override
  Future<List<ItemFila>> baixar() => _rodar((c) async {
        final linhas = await c.query(sqlBaixar);
        return linhas.map((l) => ItemFila.fromJson(Map<String, Object?>.from(l))).toList();
      });

  @override
  Future<void> fechar() async {
    final c = _client;
    _client = null;
    if (c != null) await c.dispose();
  }
}
