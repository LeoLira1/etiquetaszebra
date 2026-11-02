import 'dart:async';
import 'dart:convert';

import 'package:etiquetas_camda/impressora.dart';
import 'package:etiquetas_camda/porta_serial.dart';
import 'package:flutter_test/flutter_test.dart';

class PortaFalsa implements PortaSerial {
  final eventosCtl = StreamController<EventoConexao>.broadcast();
  final enviados = <String>[];
  int conexoes = 0;
  Object? erroAoConectar; // ErroBluetooth
  bool falhaNoEnvio = false;
  List<Pareado> pareados = const [Pareado('ZEBRA ZT410', 'AA:BB')];
  Object? erroListar;

  @override
  Stream<EventoConexao> get eventos => eventosCtl.stream;

  @override
  Future<void> garantirPermissoes() async {}

  @override
  Future<List<Pareado>> listarPareados() async {
    if (erroListar != null) throw erroListar!;
    return pareados;
  }

  @override
  Future<void> conectar(String endereco) async {
    conexoes++;
    if (erroAoConectar != null) throw erroAoConectar!;
  }

  @override
  Future<void> desconectar() async {}

  @override
  Future<void> enviar(List<int> bytes) async {
    if (falhaNoEnvio) throw const ErroBluetooth('Falha ao enviar');
    enviados.add(utf8.decode(bytes));
  }
}

class MemoriaFalsa implements MemoriaImpressora {
  Pareado? guardada;
  @override
  Future<Pareado?> ler() async => guardada;
  @override
  Future<void> gravar(Pareado? p) async => guardada = p;
}

Impressora nova(PortaFalsa porta, MemoriaFalsa mem, {List<Duration>? esperas}) => Impressora(
      porta,
      mem,
      pausaEntreEtiquetas: Duration.zero,
      esperasReconexao: esperas ?? const [Duration(milliseconds: 20)],
    );

void main() {
  test('escolher lembra a Zebra e conecta; ao reabrir o app ela volta', () async {
    final porta = PortaFalsa();
    final mem = MemoriaFalsa();
    final imp = nova(porta, mem);
    await imp.carregar();
    expect(imp.estado, EstadoImpressora.semEscolha);
    await imp.escolher(const Pareado('ZEBRA ZT410', 'AA:BB'));
    expect(imp.estado, EstadoImpressora.conectada);
    expect(mem.guardada?.endereco, 'AA:BB');

    final outra = nova(PortaFalsa(), mem);
    await outra.carregar();
    expect(outra.escolhida?.nome, 'ZEBRA ZT410');
    expect(outra.estado, EstadoImpressora.desconectada);
  });

  test('imprimir manda cada comando separado, com quebra de linha', () async {
    final porta = PortaFalsa();
    final imp = nova(porta, MemoriaFalsa());
    await imp.escolher(const Pareado('Z', 'AA:BB'));
    final vistos = <int>[];
    await imp.imprimir(['^XA^XZ', '^XA^FDX^FS^XZ'], aoEnviar: vistos.add);
    expect(porta.enviados, ['^XA^XZ\n', '^XA^FDX^FS^XZ\n']);
    expect(vistos, [1, 2]);
  });

  test('imprimir reconecta antes se a conexao tinha caido', () async {
    final porta = PortaFalsa();
    final imp = nova(porta, MemoriaFalsa(), esperas: const [Duration(seconds: 30)]);
    await imp.escolher(const Pareado('Z', 'AA:BB'));
    porta.eventosCtl.add(const EventoConexao('AA:BB', false, 'DISCONNECTED: read failed'));
    await Future<void>.delayed(Duration.zero);
    expect(imp.estado, EstadoImpressora.desconectada);
    expect(imp.erro, contains('caiu'));
    await imp.imprimir(['^XA^XZ']);
    expect(porta.conexoes, 2);
    expect(porta.enviados, hasLength(1));
  });

  test('reconecta sozinho quando a conexao cai', () async {
    final porta = PortaFalsa();
    final imp = nova(porta, MemoriaFalsa());
    await imp.escolher(const Pareado('Z', 'AA:BB'));
    porta.eventosCtl.add(const EventoConexao('AA:BB', false, 'DISCONNECTED'));
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(porta.conexoes, 2);
    expect(imp.conectada, isTrue);
    imp.dispose();
  });

  test('falha de conexao: mensagem clara e tenta de novo', () async {
    final porta = PortaFalsa()..erroAoConectar = const ErroBluetooth('read failed, socket might closed');
    final imp = nova(porta, MemoriaFalsa());
    await imp.escolher(const Pareado('ZEBRA', 'AA:BB'));
    expect(imp.estado, EstadoImpressora.desconectada);
    expect(imp.erro, contains('Não consegui conectar na ZEBRA'));
    expect(imp.erro, contains('Serial Bluetooth Terminal'));
    await expectLater(imp.imprimir(['^XA^XZ']), throwsA(isA<ErroBluetooth>()));
    expect(porta.enviados, isEmpty);
    // a Zebra volta: a proxima tentativa automatica conecta
    porta.erroAoConectar = null;
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(imp.conectada, isTrue);
    imp.dispose();
  });

  test('permissao negada para sempre pede para abrir as configuracoes e nao fica tentando', () async {
    final porta = PortaFalsa()..erroAoConectar = const ErroBluetooth('Bloqueada', abrirAjustes: true);
    final imp = nova(porta, MemoriaFalsa());
    await imp.escolher(const Pareado('Z', 'AA:BB'));
    expect(imp.erroPedeAjustes, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(porta.conexoes, 1);
  });

  test('falha no envio diz quantas etiquetas ja foram', () async {
    final porta = PortaFalsa();
    final imp = nova(porta, MemoriaFalsa(), esperas: const [Duration(seconds: 30)]);
    await imp.escolher(const Pareado('Z', 'AA:BB'));
    porta.falhaNoEnvio = true;
    await expectLater(
      imp.imprimir(['a', 'b']),
      throwsA(isA<ErroBluetooth>().having((e) => e.mensagem, 'mensagem', contains('0 de 2'))),
    );
    imp.dispose();
  });

  test('em segundo plano nao fica tentando; ao voltar reconecta', () async {
    final porta = PortaFalsa();
    final imp = nova(porta, MemoriaFalsa());
    await imp.escolher(const Pareado('Z', 'AA:BB'));
    imp.aoIrParaSegundoPlano();
    porta.eventosCtl.add(const EventoConexao('AA:BB', false, 'DISCONNECTED'));
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(porta.conexoes, 1);
    imp.aoVoltarParaOApp();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(porta.conexoes, 2);
    imp.dispose();
  });

  test('sem escolha: imprimir avisa', () async {
    final imp = nova(PortaFalsa(), MemoriaFalsa());
    await expectLater(imp.imprimir(['x']), throwsA(isA<ErroBluetooth>()));
  });

  test('listar pareados repassa o erro com mensagem', () async {
    final porta = PortaFalsa()..erroListar = const ErroBluetooth('O Bluetooth do celular está desligado.');
    final imp = nova(porta, MemoriaFalsa());
    await expectLater(imp.listarPareados(), throwsA(isA<ErroBluetooth>()));
    expect(imp.erro, contains('desligado'));
  });
}
