import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'impressora.dart';
import 'memoria_prefs.dart';
import 'porta_serial.dart';
import 'zpl.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Um erro solto do plugin Bluetooth nao pode derrubar o app.
  FlutterError.onError = (d) => FlutterError.dumpErrorToConsole(d);
  final impressora = Impressora(PortaSerialAndroid(), MemoriaPrefs());
  await impressora.carregar();
  runApp(EtiquetasApp(impressora: impressora));
}

class EtiquetasApp extends StatelessWidget {
  const EtiquetasApp({super.key, required this.impressora});

  final Impressora impressora;

  @override
  Widget build(BuildContext context) {
    const semente = Color(0xFF2E6B46);
    return MaterialApp(
      title: 'Etiquetas CAMDA',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: semente), useMaterial3: true),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: semente, brightness: Brightness.dark),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: TelaTeste(impressora: impressora),
    );
  }
}

/// Fase 1: conecta na Zebra e imprime UMA etiqueta de teste.
class TelaTeste extends StatefulWidget {
  const TelaTeste({super.key, required this.impressora});

  final Impressora impressora;

  @override
  State<TelaTeste> createState() => _TelaTesteState();
}

class _TelaTesteState extends State<TelaTeste> with WidgetsBindingObserver {
  bool _imprimindo = false;
  String? _resultado;
  bool _resultadoOk = false;

  Impressora get imp => widget.impressora;

  static final String _zplTeste = zplEtiqueta('TESTE ZEBRA', '1234567');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (imp.escolhida != null) unawaited(imp.conectar());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) imp.aoVoltarParaOApp();
    if (state == AppLifecycleState.paused) imp.aoIrParaSegundoPlano();
  }

  Future<void> _imprimirTeste() async {
    setState(() {
      _imprimindo = true;
      _resultado = null;
    });
    try {
      await imp.imprimir([_zplTeste]);
      if (!mounted) return;
      setState(() {
        _resultadoOk = true;
        _resultado = 'Enviado! Saíram 2 etiquetas (um par) com TESTE ZEBRA e 1234567?';
      });
    } on ErroBluetooth catch (e) {
      if (!mounted) return;
      setState(() {
        _resultadoOk = false;
        _resultado = e.mensagem;
      });
    } finally {
      if (mounted) setState(() => _imprimindo = false);
    }
  }

  Future<void> _escolher() async {
    List<Pareado> lista;
    try {
      lista = await imp.listarPareados();
    } on ErroBluetooth catch (e) {
      if (!mounted) return;
      await _mostrarErro(e.mensagem, ajustes: e.abrirAjustes);
      return;
    }
    if (!mounted) return;
    if (lista.isEmpty) {
      await _mostrarErro(
        'Nenhum aparelho pareado. Pareie a Zebra em Configurações do Android › Bluetooth '
        '(senha 0000 ou 1234, se pedir) e volte aqui.',
      );
      return;
    }
    final escolhido = await showModalBottomSheet<Pareado>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Escolha a Zebra', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            ),
            for (final p in lista)
              ListTile(
                leading: const Icon(Icons.print_outlined),
                title: Text(p.nome),
                subtitle: Text(p.endereco),
                selected: p.endereco == imp.escolhida?.endereco,
                onTap: () => Navigator.pop(ctx, p),
              ),
          ],
        ),
      ),
    );
    if (escolhido != null) await imp.escolher(escolhido);
  }

  Future<void> _mostrarErro(String msg, {bool ajustes = false}) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bluetooth'),
        content: Text(msg),
        actions: [
          if (ajustes)
            TextButton(
              onPressed: () {
                openAppSettings();
                Navigator.pop(ctx);
              },
              child: const Text('Abrir configurações'),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Etiquetas CAMDA'), centerTitle: false),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: imp,
          builder: (context, _) {
            final (cor, texto) = switch (imp.estado) {
              EstadoImpressora.semEscolha => (cs.outline, 'Nenhuma impressora escolhida'),
              EstadoImpressora.desconectada => (cs.error, 'Desconectada'),
              EstadoImpressora.conectando => (Colors.amber.shade700, 'Conectando…'),
              EstadoImpressora.conectada => (const Color(0xFF2E9E5B), 'Conectada'),
            };
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  elevation: 0,
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.circle, size: 14, color: cor),
                            const SizedBox(width: 8),
                            Text(texto, style: const TextStyle(fontWeight: FontWeight.w600)),
                          ],
                        ),
                        if (imp.escolhida != null) ...[
                          const SizedBox(height: 6),
                          Text(imp.escolhida!.nome, style: Theme.of(context).textTheme.titleLarge),
                          Text(imp.escolhida!.endereco, style: TextStyle(color: cs.outline)),
                        ],
                        if (imp.erro != null) ...[
                          const SizedBox(height: 10),
                          Text(imp.erro!, style: TextStyle(color: cs.error)),
                          if (imp.erroPedeAjustes)
                            TextButton(onPressed: openAppSettings, child: const Text('Abrir configurações')),
                        ],
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilledButton.tonalIcon(
                              onPressed: _escolher,
                              icon: const Icon(Icons.bluetooth_searching),
                              label: Text(imp.escolhida == null ? 'Escolher a Zebra' : 'Trocar'),
                            ),
                            if (imp.escolhida != null && !imp.conectada)
                              OutlinedButton.icon(
                                onPressed: imp.estado == EstadoImpressora.conectando ? null : imp.conectar,
                                icon: const Icon(Icons.refresh),
                                label: const Text('Reconectar'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: imp.escolhida == null || _imprimindo ? null : _imprimirTeste,
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                  icon: _imprimindo
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.print),
                  label: const Text('Imprimir etiqueta de teste', style: TextStyle(fontSize: 16)),
                ),
                if (_resultado != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _resultado!,
                    style: TextStyle(color: _resultadoOk ? const Color(0xFF2E9E5B) : cs.error, fontWeight: FontWeight.w500),
                  ),
                ],
                const SizedBox(height: 20),
                Text('ZPL enviado (1 clique = 1 par)', style: TextStyle(color: cs.outline)),
                const SizedBox(height: 6),
                SelectableText(_zplTeste, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                const SizedBox(height: 20),
                Text('Diário', style: TextStyle(color: cs.outline)),
                const SizedBox(height: 6),
                for (final l in imp.diario.take(12))
                  Text(l, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              ],
            );
          },
        ),
      ),
    );
  }
}
