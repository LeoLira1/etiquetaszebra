import 'dart:math';

import 'zpl.dart';

const origemApp = 'app';
const origemMcp = 'Claude (MCP)';
const statusPendente = 'pendente';
const statusImpresso = 'impresso';
const paresMax = 50;

/// Horario de Brasilia ("AAAA-MM-DD HH:MM:SS"), o mesmo formato do MCP e do app de estoque.
/// Brasilia nao tem horario de verao desde 2019: UTC-3 fixo e exato.
String agoraBrt([DateTime? agora]) {
  final d = (agora ?? DateTime.now()).toUtc().subtract(const Duration(hours: 3));
  String dois(int n) => n.toString().padLeft(2, '0');
  return '${d.year.toString().padLeft(4, '0')}-${dois(d.month)}-${dois(d.day)} '
      '${dois(d.hour)}:${dois(d.minute)}:${dois(d.second)}';
}

/// Identificador curto (8 hex) sorteado no aparelho: o item nasce offline.
String novoId([Random? r]) {
  final rnd = r ?? Random.secure();
  return List.generate(8, (_) => rnd.nextInt(16).toRadixString(16)).join();
}

/// Um item da fila: nome grande + codigo, e quantos PARES de etiquetas (1 par = 1 clique).
class ItemFila {
  const ItemFila({
    required this.id,
    required this.codigo,
    required this.nome,
    this.pares = 1,
    this.status = statusPendente,
    required this.criadoEm,
    this.impressoEm,
    this.origem = origemApp,
  });

  final String id;
  final String codigo;
  final String nome;
  final int pares;
  final String status;
  final String criadoEm;
  final String? impressoEm;
  final String origem;

  bool get impresso => status == statusImpresso;
  bool get doClaude => origem == origemMcp;

  /// "N cliques": o mesmo numero de pares (cada clique imprime um par).
  int get cliques => pares;
  String get rotuloCliques => pares == 1 ? '1 clique' : '$pares cliques';

  /// Aviso de nome grande demais para a letra maior (null se cabe).
  String? get avisoNome => avisoDeNome(nome);

  /// O comando ZPL de UM par; o app manda [pares] vezes.
  String get zpl => zplEtiqueta(nome, codigo);

  ItemFila copyWith({String? status, String? impressoEm, bool limparImpressao = false}) => ItemFila(
        id: id,
        codigo: codigo,
        nome: nome,
        pares: pares,
        status: status ?? this.status,
        criadoEm: criadoEm,
        impressoEm: limparImpressao ? null : (impressoEm ?? this.impressoEm),
        origem: origem,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'codigo': codigo,
        'nome': nome,
        'pares': pares,
        'status': status,
        'criado_em': criadoEm,
        'impresso_em': impressoEm,
        'origem': origem,
      };

  /// Aceita a linha do Turso (valores soltos) ou o cache local. Uma linha estranha nao derruba a tela.
  factory ItemFila.fromJson(Map<String, Object?> j) {
    String? vazio(Object? v) => v == null || '$v'.trim().isEmpty ? null : '$v';
    final pares = j['pares'] is num ? (j['pares'] as num).toInt() : int.tryParse('${j['pares']}') ?? 1;
    return ItemFila(
      id: '${j['id']}',
      codigo: '${j['codigo'] ?? ''}',
      nome: '${j['nome'] ?? ''}',
      pares: pares < 1 ? 1 : pares,
      status: '${j['status']}' == statusImpresso ? statusImpresso : statusPendente,
      criadoEm: '${j['criado_em'] ?? ''}',
      impressoEm: vazio(j['impresso_em']),
      origem: vazio(j['origem']) ?? origemApp,
    );
  }
}

/// Pendentes primeiro (mais antigos antes), depois os impressos (o mais recente antes).
List<ItemFila> ordenar(Iterable<ItemFila> itens) {
  final pend = itens.where((i) => !i.impresso).toList()
    ..sort((a, b) {
      final c = a.criadoEm.compareTo(b.criadoEm);
      return c != 0 ? c : a.id.compareTo(b.id);
    });
  final imp = itens.where((i) => i.impresso).toList()
    ..sort((a, b) => (b.impressoEm ?? '').compareTo(a.impressoEm ?? ''));
  return [...pend, ...imp];
}
