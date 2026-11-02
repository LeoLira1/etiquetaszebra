import 'package:etiquetas_camda/fonte_remota.dart';
import 'package:etiquetas_camda/item_fila.dart';

/// Turso de mentira: guarda as linhas em memoria e aplica as operacoes com a mesma semantica
/// dos SQLs reais (OR IGNORE no criar, UPDATE/DELETE por id).
class FonteFalsa implements FonteRemota {
  final Map<String, ItemFila> linhas = {};
  bool semRede = false;
  int aplicadas = 0;
  int esquemas = 0;

  void _rede() {
    if (semRede) throw Exception('sem rede');
  }

  @override
  Future<void> garantirEsquema() async {
    _rede();
    esquemas++;
  }

  @override
  Future<void> aplicar(Operacao op) async {
    _rede();
    aplicadas++;
    switch (op.tipo) {
      case TipoOperacao.criar:
        linhas.putIfAbsent(op.item!.id, () => op.item!);
      case TipoOperacao.imprimir:
        final i = linhas[op.id];
        if (i != null) linhas[op.id!] = i.copyWith(status: statusImpresso, impressoEm: op.em);
      case TipoOperacao.apagar:
        linhas.remove(op.id);
    }
  }

  @override
  Future<List<ItemFila>> baixar() async {
    _rede();
    return linhas.values.toList();
  }

  @override
  Future<void> fechar() async {}
}

/// Item lancado pelo Claude (MCP) direto no banco.
ItemFila daMcp(String id, String nome, String codigo, {int pares = 1, String criado = '2026-11-02 08:00:00'}) =>
    ItemFila(id: id, codigo: codigo, nome: nome, pares: pares, criadoEm: criado, origem: origemMcp);
