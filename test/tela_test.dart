import 'package:etiquetas_camda/armazenamento.dart';
import 'package:etiquetas_camda/impressora.dart';
import 'package:etiquetas_camda/main.dart';
import 'package:etiquetas_camda/porta_serial.dart';
import 'package:etiquetas_camda/repositorio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fonte_falsa.dart';
import 'impressora_test.dart' show MemoriaFalsa, PortaFalsa;

class Cena {
  Cena(this.repo, this.imp, this.porta, this.fonte);
  final RepositorioFila repo;
  final Impressora imp;
  final PortaFalsa porta;
  final FonteFalsa fonte;
}

Future<Cena> montar(WidgetTester t, {bool zebra = true, List<Object> itens = const []}) async {
  final porta = PortaFalsa();
  final mem = MemoriaFalsa();
  if (zebra) mem.guardada = const Pareado('ZEBRA ZT410', 'AA:BB');
  final imp = Impressora(porta, mem, pausaEntreEtiquetas: Duration.zero);
  await imp.carregar();
  final armazem = ArmazenamentoMemoria();
  final repo = RepositorioFila(armazem, relogio: () => DateTime.utc(2026, 11, 2, 15));
  final fonte = FonteFalsa();
  fonte.linhas['a1'] = daMcp('a1', 'ROUNDUP', '3456', pares: 3, criado: '2026-11-02 08:00:00');
  fonte.linhas['b2'] = daMcp('b2', 'NATIVO FUNGICIDA', 'US10047813', pares: 1, criado: '2026-11-02 09:00:00');
  await repo.usarFonte(fonte);
  await t.pumpWidget(EtiquetasApp(repo: repo, impressora: imp, armazem: armazem, intervaloSync: const Duration(hours: 1)));
  await t.pumpAndSettle();
  return Cena(repo, imp, porta, fonte);
}

void main() {
  testWidgets('mostra a fila com nome, codigo, N cliques e aviso de nome grande', (t) async {
    await montar(t);
    expect(find.text('ROUNDUP'), findsOneWidget);
    expect(find.text('3456'), findsOneWidget);
    expect(find.text('3 cliques'), findsOneWidget);
    expect(find.text('1 clique'), findsOneWidget);
    expect(find.byKey(const Key('aviso-b2')), findsOneWidget); // 16 letras: nao cabe na letra maior
    expect(find.byKey(const Key('aviso-a1')), findsNothing);
    expect(find.text('2 pendente(s) · 4 clique(s)'), findsOneWidget);
    expect(find.text('Conectada'), findsNothing); // so o nome da Zebra no topo
    expect(find.text('ZEBRA ZT410'), findsOneWidget);
  });

  testWidgets('imprimir tudo: manda um comando por clique e marca como impresso sem sumir', (t) async {
    final c = await montar(t);
    await t.tap(find.byKey(const Key('botao-imprimir-tudo')));
    await t.pumpAndSettle();
    expect(find.text('Imprimir tudo?'), findsOneWidget);
    await t.tap(find.text('Imprimir'));
    await t.pumpAndSettle();
    expect(c.porta.enviados, hasLength(4));
    expect(c.porta.enviados.where((e) => e.contains('^FDROUNDUP^FS')), hasLength(3));
    expect(c.porta.enviados.where((e) => e.contains('^FDNATIVO FUNGICIDA^FS')), hasLength(1));
    expect(c.repo.pendentes, isEmpty);
    expect(c.repo.totalImpressos, 2);
    expect(find.text('ROUNDUP'), findsOneWidget); // continua na lista
    expect(find.textContaining('✓ impresso'), findsNWidgets(2));
    // reimprimir uma que saiu errada
    await t.tap(find.byKey(const Key('imprimir-a1')));
    await t.pumpAndSettle();
    expect(c.porta.enviados, hasLength(7));
  });

  testWidgets('imprimir selecionados', (t) async {
    final c = await montar(t);
    expect(tester(t, const Key('botao-imprimir-selecionados')).onPressed, isNull);
    await t.tap(find.byKey(const Key('marcar-b2')));
    await t.pumpAndSettle();
    expect(find.text('Selecionados (1)'), findsOneWidget);
    await t.tap(find.byKey(const Key('botao-imprimir-selecionados')));
    await t.pumpAndSettle();
    expect(c.porta.enviados, hasLength(1));
    expect(c.repo.porId('b2')!.impresso, isTrue);
    expect(c.repo.porId('a1')!.impresso, isFalse);
  });

  testWidgets('apagar item, limpar impressos e limpar tudo', (t) async {
    final c = await montar(t);
    await t.tap(find.byKey(const Key('apagar-b2')));
    await t.pumpAndSettle();
    expect(c.repo.itens.map((i) => i.id), ['a1']);

    await c.repo.marcarImpresso(['a1']);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('menu-limpar')));
    await t.pumpAndSettle();
    await t.tap(find.text('Limpar impressos'));
    await t.pumpAndSettle();
    await t.tap(find.text('Limpar'));
    await t.pumpAndSettle();
    expect(c.repo.itens, isEmpty);
    expect(find.text('A fila está vazia'), findsOneWidget);

    await c.repo.adicionar('X', '1');
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('menu-limpar')));
    await t.pumpAndSettle();
    await t.tap(find.text('Limpar tudo'));
    await t.pumpAndSettle();
    await t.tap(find.text('Limpar tudo').last);
    await t.pumpAndSettle();
    expect(c.repo.itens, isEmpty);
  });

  testWidgets('sem Zebra escolhida avisa em vez de imprimir', (t) async {
    final c = await montar(t, zebra: false);
    await t.tap(find.byKey(const Key('imprimir-a1')));
    await t.pumpAndSettle();
    expect(find.textContaining('Escolha a Zebra primeiro'), findsOneWidget);
    expect(c.porta.enviados, isEmpty);
    expect(c.repo.totalImpressos, 0);
  });

  testWidgets('falha na conexao: nada e marcado como impresso e a mensagem aparece', (t) async {
    final c = await montar(t);
    c.porta.erroAoConectar = const ErroBluetooth('read failed, socket might closed');
    c.imp.aoIrParaSegundoPlano();
    c.porta.eventosCtl.add(const EventoConexao('AA:BB', false, 'DISCONNECTED'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('imprimir-a1')));
    await t.pumpAndSettle();
    expect(c.porta.enviados, isEmpty);
    expect(c.repo.totalImpressos, 0);
    expect(find.textContaining('Não consegui conectar'), findsWidgets);
  });

  testWidgets('lancar item novo pelo app (+) com aviso de nome grande', (t) async {
    final c = await montar(t);
    await t.tap(find.byKey(const Key('botao-novo')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('campo-nome')), 'Glifosato Atanor');
    await t.enterText(find.byKey(const Key('campo-codigo')), '777');
    await t.pumpAndSettle();
    expect(find.textContaining('⚠️ Nome com 16 letras'), findsOneWidget);
    await t.tap(find.byKey(const Key('mais-par')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('botao-lancar')));
    await t.pumpAndSettle();
    final novo = c.repo.itens.firstWhere((i) => i.codigo == '777');
    expect((novo.nome, novo.pares, novo.origem), ('GLIFOSATO ATANOR', 2, 'app'));
    expect(c.fonte.linhas.containsKey(novo.id), isTrue);
  });
}

FilledButton tester(WidgetTester t, Key k) => t.widget<FilledButton>(find.byKey(k));
