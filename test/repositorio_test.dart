import 'package:etiquetas_camda/armazenamento.dart';
import 'package:etiquetas_camda/item_fila.dart';
import 'package:etiquetas_camda/repositorio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fonte_falsa.dart';

final _agora = DateTime.utc(2026, 11, 2, 15, 0, 0); // 12:00 em Brasilia

Future<(RepositorioFila, FonteFalsa, ArmazenamentoMemoria)> novo({bool comFonte = true}) async {
  final mem = ArmazenamentoMemoria();
  final repo = RepositorioFila(mem, relogio: () => _agora);
  await repo.carregar();
  final fonte = FonteFalsa();
  if (comFonte) await repo.usarFonte(fonte);
  return (repo, fonte, mem);
}

void main() {
  test('adicionar grava no aparelho, vai ao Turso e normaliza o texto', () async {
    final (repo, fonte, _) = await novo();
    expect(await repo.adicionar('  óleo ', ' us100 ', pares: 2), isNull);
    await repo.sincronizar();
    final i = fonte.linhas.values.single;
    expect((i.nome, i.codigo, i.pares, i.status, i.origem), ('OLEO', 'US100', 2, 'pendente', 'app'));
    expect(i.criadoEm, '2026-11-02 12:00:00');
    expect(repo.semEnviar, 0);
  });

  test('validacao: nome, codigo e pares', () async {
    final (repo, _, _) = await novo();
    expect(await repo.adicionar('', '1'), isNotNull);
    expect(await repo.adicionar('A', ' '), isNotNull);
    expect(await repo.adicionar('A', '1', pares: 0), isNotNull);
    expect(await repo.adicionar('A', '1', pares: 51), isNotNull);
    expect(repo.itens, isEmpty);
  });

  test('offline: tudo fica na fila e sobe quando a rede volta', () async {
    final (repo, fonte, _) = await novo();
    fonte.semRede = true;
    await repo.adicionar('A', '1');
    await repo.adicionar('B', '2');
    final id = repo.itens.first.id;
    await repo.marcarImpresso([id]);
    await repo.sincronizar();
    expect(repo.erro, isNotNull);
    expect(repo.semEnviar, 3);
    expect(repo.itens, hasLength(2));
    fonte.semRede = false;
    expect(await repo.sincronizar(), isTrue);
    expect(fonte.linhas, hasLength(2));
    expect(fonte.linhas[id]!.impresso, isTrue);
    expect(repo.semEnviar, 0);
  });

  test('o que o Claude lancou aparece no sync; item com operacao na fila nao e sobrescrito', () async {
    final (repo, fonte, _) = await novo();
    fonte.linhas['m1'] = daMcp('m1', 'ROUNDUP', '3456', pares: 3);
    await repo.sincronizar();
    expect(repo.itens.single.doClaude, isTrue);
    expect(repo.itens.single.cliques, 3);
    expect(repo.itens.single.rotuloCliques, '3 cliques');

    fonte.semRede = true;
    await repo.marcarImpresso(['m1']);
    fonte.semRede = false;
    fonte.linhas['m1'] = daMcp('m1', 'ROUNDUP', '3456', pares: 3); // banco ainda diz pendente
    fonte.semRede = true;
    await repo.sincronizar();
    expect(repo.porId('m1')!.impresso, isTrue); // continua impresso no aparelho
  });

  test('marcado como impresso nao some e pode reimprimir', () async {
    final (repo, fonte, _) = await novo();
    await repo.adicionar('A', '1');
    final id = repo.itens.single.id;
    await repo.marcarImpresso([id]);
    expect(repo.pendentes, isEmpty);
    expect(repo.totalImpressos, 1);
    expect(repo.itens.single.impresso, isTrue);
    await repo.sincronizar();
    expect(fonte.linhas[id]!.impressoEm, '2026-11-02 12:00:00');
    await repo.marcarImpresso([id]); // reimpressao
    expect(repo.totalImpressos, 1);
  });

  test('ordem: pendentes antigos primeiro, depois impressos recentes', () async {
    final (repo, fonte, _) = await novo();
    fonte.linhas['a'] = daMcp('a', 'A', '1', criado: '2026-11-02 08:00:00');
    fonte.linhas['b'] = daMcp('b', 'B', '2', criado: '2026-11-02 07:00:00');
    fonte.linhas['c'] = daMcp('c', 'C', '3').copyWith(status: statusImpresso, impressoEm: '2026-11-02 09:00:00');
    fonte.linhas['d'] = daMcp('d', 'D', '4').copyWith(status: statusImpresso, impressoEm: '2026-11-02 10:00:00');
    await repo.sincronizar();
    expect(repo.itens.map((i) => i.id), ['b', 'a', 'd', 'c']);
  });

  test('apagar um item, limpar impressos e limpar tudo (DELETE por id)', () async {
    final (repo, fonte, _) = await novo();
    for (final n in ['A', 'B', 'C']) {
      await repo.adicionar(n, n);
    }
    await repo.sincronizar();
    final ids = repo.itens.map((i) => i.id).toList();
    await repo.marcarImpresso([ids[0]]);
    await repo.apagar([ids[1]]);
    await repo.sincronizar();
    expect(fonte.linhas.keys, unorderedEquals([ids[0], ids[2]]));

    // o Claude lanca algo depois: "limpar impressos" nao pode levar junto
    fonte.linhas['m'] = daMcp('m', 'NOVO', '9');
    await repo.limparImpressos();
    await repo.sincronizar();
    expect(fonte.linhas.keys, unorderedEquals([ids[2], 'm']));
    expect(repo.itens, hasLength(2));

    await repo.limparTudo();
    await repo.sincronizar();
    expect(fonte.linhas, isEmpty);
    expect(repo.itens, isEmpty);
  });

  test('criado e apagado offline nem chega ao banco', () async {
    final (repo, fonte, _) = await novo();
    fonte.semRede = true;
    await repo.adicionar('A', '1');
    await repo.apagar([repo.itens.single.id]);
    expect(repo.semEnviar, 0);
    fonte.semRede = false;
    await repo.sincronizar();
    expect(fonte.linhas, isEmpty);
    expect(fonte.aplicadas, 0);
  });

  test('cache: reabrir o app mantem a fila e o que faltava enviar', () async {
    final (repo, fonte, mem) = await novo();
    fonte.semRede = true;
    await repo.adicionar('A', '1', pares: 4);
    final repo2 = RepositorioFila(mem, relogio: () => _agora);
    await repo2.carregar();
    expect(repo2.itens.single.pares, 4);
    expect(repo2.semEnviar, 1);
    final f2 = FonteFalsa();
    await repo2.usarFonte(f2);
    await repo2.sincronizar();
    expect(f2.linhas, hasLength(1));
  });

  test('aviso de nome grande aparece no item', () async {
    final (repo, fonte, _) = await novo();
    fonte.linhas['x'] = daMcp('x', 'ROUNDUP ORIGINAL', '1');
    fonte.linhas['y'] = daMcp('y', 'ROUNDUP', '2');
    await repo.sincronizar();
    expect(repo.porId('x')!.avisoNome, contains('letra 32'));
    expect(repo.porId('y')!.avisoNome, isNull);
    expect(repo.porId('x')!.zpl, contains('^A0N,32,32^FDROUNDUP ORIGINAL^FS'));
    expect(repo.porId('y')!.zpl, contains('^A0N,52,52^FDROUNDUP^FS^FO60,112^A0N,58,58^FD2^FS'));
  });
}
