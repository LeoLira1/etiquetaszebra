import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'porta_serial.dart';

enum EstadoImpressora { semEscolha, desconectada, conectando, conectada }

/// Onde o app lembra qual Zebra foi escolhida (troca-se por memoria nos testes).
abstract class MemoriaImpressora {
  Future<Pareado?> ler();
  Future<void> gravar(Pareado? p);
}

/// Cuida da Zebra: lembra a escolhida, conecta, reconecta sozinho quando cai e envia o ZPL.
class Impressora extends ChangeNotifier {
  Impressora(
    this._porta,
    this._memoria, {
    this.pausaEntreEtiquetas = const Duration(milliseconds: 250),
    this.esperasReconexao = const [Duration(seconds: 2), Duration(seconds: 4), Duration(seconds: 8), Duration(seconds: 15), Duration(seconds: 30)],
  }) {
    _sub = _porta.eventos.listen(_aoEvento);
  }

  final PortaSerial _porta;
  final MemoriaImpressora _memoria;
  final Duration pausaEntreEtiquetas;

  /// Esperas entre tentativas de reconexao; a ultima se repete enquanto o app esta aberto.
  final List<Duration> esperasReconexao;

  late final StreamSubscription<EventoConexao> _sub;

  Pareado? _escolhida;
  EstadoImpressora _estado = EstadoImpressora.semEscolha;
  String? _erro;
  bool _abrirAjustes = false;
  bool _querConectada = false; // o usuario nao desligou de proposito
  bool _emSegundoPlano = false;
  Timer? _timerReconexao;
  int _tentativa = 0;
  Future<void>? _conectando;
  bool _fechada = false;
  final List<String> _diario = [];

  Pareado? get escolhida => _escolhida;
  EstadoImpressora get estado => _estado;
  bool get conectada => _estado == EstadoImpressora.conectada;

  /// Ultima mensagem de erro (ja em portugues), ou null.
  String? get erro => _erro;

  /// true quando a mensagem de erro pede para abrir as configuracoes do Android.
  bool get erroPedeAjustes => _abrirAjustes;

  /// Ultimas linhas do que aconteceu (mais nova primeiro), para diagnostico.
  List<String> get diario => List.unmodifiable(_diario);

  void _log(String s) {
    final t = DateTime.now();
    String d(int n) => n.toString().padLeft(2, '0');
    _diario.insert(0, '${d(t.hour)}:${d(t.minute)}:${d(t.second)}  $s');
    if (_diario.length > 40) _diario.removeLast();
  }

  void _mudar(EstadoImpressora e) {
    _estado = e;
    notifyListeners();
  }

  /// Le a Zebra lembrada. Nao conecta - quem chama decide (normalmente [conectar] em seguida).
  Future<void> carregar() async {
    _escolhida = await _memoria.ler();
    _estado = _escolhida == null ? EstadoImpressora.semEscolha : EstadoImpressora.desconectada;
    notifyListeners();
  }

  Future<List<Pareado>> listarPareados() async {
    try {
      final l = await _porta.listarPareados();
      _erro = null;
      _abrirAjustes = false;
      return l;
    } on ErroBluetooth catch (e) {
      _registrarErro(e);
      rethrow;
    }
  }

  /// Escolhe (e lembra) a Zebra e conecta nela.
  Future<void> escolher(Pareado p) async {
    _cancelarReconexao();
    if (_escolhida != null && _escolhida!.endereco != p.endereco) await _porta.desconectar();
    _escolhida = p;
    await _memoria.gravar(p);
    _log('Escolhida: ${p.nome} (${p.endereco})');
    _mudar(EstadoImpressora.desconectada);
    await conectar();
  }

  Future<void> esquecer() async {
    _querConectada = false;
    _cancelarReconexao();
    await _porta.desconectar();
    _escolhida = null;
    await _memoria.gravar(null);
    _erro = null;
    _log('Impressora esquecida');
    _mudar(EstadoImpressora.semEscolha);
  }

  /// Conecta na Zebra escolhida. Varias chamadas ao mesmo tempo viram uma so.
  Future<void> conectar() {
    if (_escolhida == null) {
      _erro = 'Escolha a Zebra primeiro.';
      notifyListeners();
      return Future.value();
    }
    if (conectada) return Future.value();
    return _conectando ??= _conectarDeVerdade().whenComplete(() => _conectando = null);
  }

  Future<void> _conectarDeVerdade() async {
    final p = _escolhida!;
    _querConectada = true;
    _mudar(EstadoImpressora.conectando);
    _log('Conectando em ${p.nome}…');
    try {
      await _porta.conectar(p.endereco);
      _tentativa = 0;
      _erro = null;
      _abrirAjustes = false;
      _log('Conectada');
      _mudar(EstadoImpressora.conectada);
    } on ErroBluetooth catch (e) {
      _registrarErro(e, prefixo: 'Não consegui conectar na ${p.nome}. ');
      _mudar(EstadoImpressora.desconectada);
      if (!e.abrirAjustes) _agendarReconexao();
    }
  }

  void _registrarErro(ErroBluetooth e, {String prefixo = ''}) {
    final dica = prefixo.isEmpty
        ? ''
        : '\nConfira: a Zebra está ligada e perto? Outro app (como o Serial Bluetooth Terminal) está conectado nela? '
            'Só um aparelho fala com a Zebra por vez.';
    _erro = '$prefixo${e.mensagem}$dica';
    _abrirAjustes = e.abrirAjustes;
    _log('Erro: ${e.mensagem}');
    notifyListeners();
  }

  void _aoEvento(EventoConexao ev) {
    final p = _escolhida;
    if (p == null || ev.endereco != p.endereco) return;
    // Durante _conectarDeVerdade quem trata o resultado e o proprio conectar().
    if (_conectando != null) return;
    if (!ev.conectado && _estado == EstadoImpressora.conectada) {
      _log('Conexão caiu (${ev.detalhe})');
      _erro = 'A conexão com a ${p.nome} caiu. Tentando reconectar sozinho…';
      _abrirAjustes = false;
      _mudar(EstadoImpressora.desconectada);
      if (_querConectada) _agendarReconexao();
    }
  }

  void _agendarReconexao() {
    if (_fechada || !_querConectada || _emSegundoPlano || _escolhida == null) return;
    _timerReconexao?.cancel();
    final espera = esperasReconexao[_tentativa < esperasReconexao.length ? _tentativa : esperasReconexao.length - 1];
    _tentativa++;
    _log('Nova tentativa em ${espera.inSeconds}s');
    _timerReconexao = Timer(espera, () {
      if (!_fechada && _querConectada && !conectada) unawaited(conectar());
    });
  }

  void _cancelarReconexao() {
    _timerReconexao?.cancel();
    _timerReconexao = null;
    _tentativa = 0;
  }

  /// Chame quando o app volta para a frente: tenta conectar de novo se estiver caida.
  void aoVoltarParaOApp() {
    _emSegundoPlano = false;
    if (_escolhida != null && !conectada) {
      _cancelarReconexao();
      unawaited(conectar());
    }
  }

  /// Chame quando o app sai da frente: para as tentativas (o Android corta o Bluetooth em segundo plano).
  void aoIrParaSegundoPlano() {
    _emSegundoPlano = true;
    _cancelarReconexao();
  }

  /// Envia os comandos ZPL, um por vez (cada um e um par de etiquetas), com uma pausa entre eles.
  /// Reconecta antes se preciso. Lanca [ErroBluetooth] com mensagem pronta; [aoEnviar] avisa cada envio.
  Future<void> imprimir(List<String> comandos, {void Function(int enviados)? aoEnviar}) async {
    if (_escolhida == null) throw const ErroBluetooth('Escolha a Zebra primeiro.');
    if (comandos.isEmpty) return;
    if (!conectada) {
      await conectar();
      if (!conectada) {
        throw ErroBluetooth(_erro ?? 'Não consegui conectar na Zebra.', abrirAjustes: _abrirAjustes);
      }
    }
    var enviados = 0;
    for (final c in comandos) {
      if (!conectada) {
        throw ErroBluetooth('A Zebra desconectou depois de $enviados etiqueta(s) enviada(s). O restante não foi impresso.');
      }
      try {
        await _porta.enviar(utf8.encode('$c\n'));
      } on ErroBluetooth catch (e) {
        _log('Erro ao enviar: ${e.mensagem}');
        _mudar(EstadoImpressora.desconectada);
        if (_querConectada) _agendarReconexao();
        throw ErroBluetooth('${e.mensagem} Foram enviadas $enviados de ${comandos.length}.');
      }
      enviados++;
      aoEnviar?.call(enviados);
      await Future<void>.delayed(pausaEntreEtiquetas);
    }
    if (!conectada) {
      throw ErroBluetooth('A Zebra desconectou durante o envio; a última etiqueta pode não ter saído.');
    }
    _log('Enviadas $enviados etiqueta(s)');
    notifyListeners();
  }

  @override
  void dispose() {
    _fechada = true;
    _cancelarReconexao();
    _sub.cancel();
    super.dispose();
  }
}
