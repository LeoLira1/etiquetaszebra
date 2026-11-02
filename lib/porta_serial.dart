import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_bluetooth_classic_serial/flutter_bluetooth_classic.dart';
import 'package:permission_handler/permission_handler.dart';

/// Aparelho Bluetooth ja pareado no Android.
class Pareado {
  const Pareado(this.nome, this.endereco);
  final String nome;
  final String endereco;
}

/// Falha com mensagem pronta para mostrar ao usuario.
class ErroBluetooth implements Exception {
  const ErroBluetooth(this.mensagem, {this.abrirAjustes = false});
  final String mensagem;

  /// true quando so as configuracoes do Android resolvem (permissao negada para sempre).
  final bool abrirAjustes;
  @override
  String toString() => mensagem;
}

/// Evento de conexao vindo do sistema.
class EventoConexao {
  const EventoConexao(this.endereco, this.conectado, this.detalhe);
  final String endereco;
  final bool conectado;
  final String detalhe;
}

/// A ponta Bluetooth, vista pelo app. Existe para os testes trocarem o plugin por uma falsa.
abstract class PortaSerial {
  /// Pede as permissoes do Android (12+: BLUETOOTH_CONNECT/SCAN). Lanca [ErroBluetooth].
  Future<void> garantirPermissoes();

  Future<List<Pareado>> listarPareados();

  /// Conecta e so retorna quando a conexao abriu (ou lanca [ErroBluetooth]).
  Future<void> conectar(String endereco);

  Future<void> desconectar();

  /// Envia os bytes de UMA vez (uma etiqueta = um envio).
  Future<void> enviar(List<int> bytes);

  /// Conexao aberta/caida, inclusive quedas que o app nao pediu.
  Stream<EventoConexao> get eventos;
}

/// Implementacao real: Bluetooth classico (SPP/RFCOMM) pelo plugin
/// `flutter_bluetooth_classic_serial` + permissoes pelo `permission_handler`.
class PortaSerialAndroid implements PortaSerial {
  PortaSerialAndroid() {
    // Cria o plugin ja (ele escuta os canais nativos desde o construtor).
    _bt = FlutterBluetoothClassic();
    _bt.onConnectionChanged.listen(
      (e) => _eventos.add(EventoConexao(e.deviceAddress, e.isConnected, e.status)),
      onError: (_) {},
    );
  }

  late final FlutterBluetoothClassic _bt;
  final _eventos = StreamController<EventoConexao>.broadcast();

  @override
  Stream<EventoConexao> get eventos => _eventos.stream;

  @override
  Future<void> garantirPermissoes() async {
    if (!Platform.isAndroid) throw const ErroBluetooth('Este app imprime só pelo Bluetooth do Android.');
    final pedidas = await [Permission.bluetoothConnect, Permission.bluetoothScan].request();
    final negadas = pedidas.values.where((s) => !s.isGranted && !s.isLimited).toList();
    if (negadas.isNotEmpty) {
      final parasempre = negadas.any((s) => s.isPermanentlyDenied);
      throw ErroBluetooth(
        parasempre
            ? 'O Android bloqueou a permissão de Bluetooth. Abra as configurações do app e permita '
                '"Dispositivos por perto" (Bluetooth).'
            : 'Sem a permissão de Bluetooth não dá para falar com a Zebra. Toque de novo e escolha "Permitir".',
        abrirAjustes: parasempre,
      );
    }
  }

  Future<void> _garantirLigado() async {
    bool ligado;
    try {
      ligado = await _bt.isBluetoothEnabled();
    } catch (e) {
      throw ErroBluetooth('Não consegui ver se o Bluetooth está ligado ($e).');
    }
    if (!ligado) throw const ErroBluetooth('O Bluetooth do celular está desligado. Ligue e tente de novo.');
  }

  @override
  Future<List<Pareado>> listarPareados() async {
    await garantirPermissoes();
    await _garantirLigado();
    Future<List<Pareado>> ler() async {
      final lista = await _bt.getPairedDevices();
      return lista.map((d) => Pareado(d.name, d.address)).toList();
    }

    try {
      return await ler();
    } catch (e) {
      if (!_ehPermissao(e)) throw ErroBluetooth('Não consegui listar os aparelhos pareados: ${_limpa(e)}');
      // Android antigo (anterior ao 12): o plugin pede localizacao para listar pareados.
      final loc = await Permission.locationWhenInUse.request();
      if (!loc.isGranted) {
        throw ErroBluetooth(
          'Neste Android é preciso permitir a localização para listar os aparelhos pareados.',
          abrirAjustes: loc.isPermanentlyDenied,
        );
      }
      try {
        return await ler();
      } catch (e2) {
        throw ErroBluetooth('Não consegui listar os aparelhos pareados: ${_limpa(e2)}');
      }
    }
  }

  @override
  Future<void> conectar(String endereco) async {
    await garantirPermissoes();
    await _garantirLigado();
    // Escuta ANTES de pedir: o plugin responde "ok" na hora e avisa o resultado por evento.
    final resposta = _eventos.stream.firstWhere((e) => e.endereco == endereco);
    try {
      await _bt.connect(endereco);
    } catch (e) {
      throw ErroBluetooth('Não consegui iniciar a conexão: ${_limpa(e)}');
    }
    final EventoConexao ev;
    try {
      ev = await resposta.timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw const ErroBluetooth('A Zebra não respondeu em 15 segundos.');
    }
    if (!ev.conectado) throw ErroBluetooth(ev.detalhe.replaceFirst(RegExp(r'^ERROR:\s*'), ''));
  }

  @override
  Future<void> desconectar() async {
    try {
      await _bt.disconnect();
    } catch (_) {}
  }

  @override
  Future<void> enviar(List<int> bytes) async {
    try {
      await _bt.sendData(bytes);
    } catch (e) {
      throw ErroBluetooth('Falha ao enviar para a Zebra: ${_limpa(e)}');
    }
  }

  bool _ehPermissao(Object e) => e.toString().contains('PERMISSION_DENIED') || (e is PlatformException && e.code == 'PERMISSION_DENIED');

  String _limpa(Object e) => e.toString().replaceFirst('BluetoothException: ', '');
}
