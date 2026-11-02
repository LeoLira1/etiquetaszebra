import 'item_fila.dart';

enum TipoOperacao { criar, imprimir, apagar }

/// Uma alteracao feita no aparelho que ainda nao chegou ao Turso. Todas sao idempotentes
/// (INSERT OR IGNORE / UPDATE ou DELETE por id): reenviar depois de uma queda nao estraga nada.
class Operacao {
  const Operacao.criar(ItemFila this.item)
      : tipo = TipoOperacao.criar,
        id = null,
        em = null;
  const Operacao.imprimir(String this.id, String this.em)
      : tipo = TipoOperacao.imprimir,
        item = null;
  const Operacao.apagar(String this.id)
      : tipo = TipoOperacao.apagar,
        item = null,
        em = null;

  final TipoOperacao tipo;
  final ItemFila? item;
  final String? id;
  final String? em;

  String get idItem => item?.id ?? id!;

  Map<String, Object?> toJson() => {
        'tipo': tipo.name,
        if (item != null) 'item': item!.toJson(),
        if (id != null) 'id': id,
        if (em != null) 'em': em,
      };

  factory Operacao.fromJson(Map<String, Object?> j) {
    switch (TipoOperacao.values.byName(j['tipo'] as String)) {
      case TipoOperacao.criar:
        return Operacao.criar(ItemFila.fromJson(Map<String, Object?>.from(j['item'] as Map)));
      case TipoOperacao.imprimir:
        return Operacao.imprimir(j['id'] as String, j['em'] as String);
      case TipoOperacao.apagar:
        return Operacao.apagar(j['id'] as String);
    }
  }
}

/// O Turso, visto pelo app. Troca-se por uma falsa nos testes.
abstract class FonteRemota {
  /// `CREATE TABLE IF NOT EXISTS fila_etiquetas` - so a tabela nova, nunca as do app de estoque.
  Future<void> garantirEsquema();

  Future<void> aplicar(Operacao op);

  /// Todos os itens da fila (pendentes e impressos).
  Future<List<ItemFila>> baixar();

  Future<void> fechar();
}
