import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'impressora.dart';
import 'porta_serial.dart';
import 'zpl.dart';

/// Folha de baixo com tudo da Zebra: estado, escolher/trocar, reconectar, etiqueta de teste e diario.
class PainelImpressora extends StatefulWidget {
  const PainelImpressora({super.key, required this.impressora});

  final Impressora impressora;

  @override
  State<PainelImpressora> createState() => _PainelImpressoraState();
}

class _PainelImpressoraState extends State<PainelImpressora> {
  bool _imprimindo = false;
  String? _resultado;
  bool _resultadoOk = false;

  Impressora get imp => widget.impressora;

  Future<void> _teste() async {
    setState(() {
      _imprimindo = true;
      _resultado = null;
    });
    try {
      await imp.imprimir([zplEtiqueta('TESTE ZEBRA', '1234567')]);
      if (!mounted) return;
      setState(() {
        _resultadoOk = true;
        _resultado = 'Enviado! Saiu um par com TESTE ZEBRA e 1234567?';
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
      await _erro(e.mensagem, ajustes: e.abrirAjustes);
      return;
    }
    if (!mounted) return;
    if (lista.isEmpty) {
      await _erro(
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

  Future<void> _erro(String msg, {bool ajustes = false}) {
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
    return SafeArea(
      child: ListenableBuilder(
        listenable: imp,
        builder: (context, _) {
          final (cor, texto) = rotuloEstado(imp.estado, cs);
          return ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            children: [
              Row(children: [
                Icon(Icons.circle, size: 14, color: cor),
                const SizedBox(width: 8),
                Text(texto, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
              ]),
              if (imp.escolhida != null) ...[
                const SizedBox(height: 6),
                Text(imp.escolhida!.nome, style: Theme.of(context).textTheme.titleLarge),
                Text(imp.escolhida!.endereco, style: TextStyle(color: cs.outline)),
              ],
              if (imp.erro != null) ...[
                const SizedBox(height: 10),
                Text(imp.erro!, style: TextStyle(color: cs.error)),
                if (imp.erroPedeAjustes) TextButton(onPressed: openAppSettings, child: const Text('Abrir configurações')),
              ],
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
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
                if (imp.escolhida != null)
                  OutlinedButton.icon(
                    key: const Key('botao-teste'),
                    onPressed: _imprimindo ? null : _teste,
                    icon: _imprimindo
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.print),
                    label: const Text('Etiqueta de teste'),
                  ),
              ]),
              if (_resultado != null) ...[
                const SizedBox(height: 10),
                Text(_resultado!, style: TextStyle(color: _resultadoOk ? const Color(0xFF2E9E5B) : cs.error)),
              ],
              if (imp.diario.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('Diário', style: TextStyle(color: cs.outline)),
                const SizedBox(height: 4),
                for (final l in imp.diario.take(8)) Text(l, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              ],
            ],
          );
        },
      ),
    );
  }
}

(Color, String) rotuloEstado(EstadoImpressora e, ColorScheme cs) => switch (e) {
      EstadoImpressora.semEscolha => (cs.outline, 'Nenhuma impressora escolhida'),
      EstadoImpressora.desconectada => (cs.error, 'Desconectada'),
      EstadoImpressora.conectando => (Colors.amber.shade700, 'Conectando…'),
      EstadoImpressora.conectada => (const Color(0xFF2E9E5B), 'Conectada'),
    };
