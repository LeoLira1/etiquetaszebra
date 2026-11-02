import 'package:flutter/material.dart';

import 'armazenamento.dart';
import 'config_page.dart';
import 'impressora.dart';
import 'memoria_prefs.dart';
import 'porta_serial.dart';
import 'repositorio.dart';
import 'tela_fila.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Um erro solto do plugin Bluetooth nao pode derrubar o app.
  FlutterError.onError = (d) => FlutterError.dumpErrorToConsole(d);
  final armazem = ArmazenamentoPrefs();
  final repo = RepositorioFila(armazem);
  final impressora = Impressora(PortaSerialAndroid(), MemoriaPrefs());
  // So o cache local antes do primeiro quadro: a fila aparece na hora, sem esperar rede.
  await repo.carregar();
  await impressora.carregar();
  await conectarSalvo(repo, armazem);
  runApp(EtiquetasApp(repo: repo, impressora: impressora, armazem: armazem));
}

class EtiquetasApp extends StatelessWidget {
  const EtiquetasApp({
    super.key,
    required this.repo,
    required this.impressora,
    required this.armazem,
    this.criarFonte = criarFontePadrao,
    this.intervaloSync = const Duration(seconds: 30),
  });

  final RepositorioFila repo;
  final Impressora impressora;
  final Armazenamento armazem;
  final CriarFonte criarFonte;
  final Duration intervaloSync;

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
      home: TelaFila(
        repo: repo,
        impressora: impressora,
        armazem: armazem,
        criarFonte: criarFonte,
        intervaloSync: intervaloSync,
      ),
    );
  }
}
