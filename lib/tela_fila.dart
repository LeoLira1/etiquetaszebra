import 'dart:async';

import 'package:flutter/material.dart';

import 'armazenamento.dart';
import 'config_page.dart';
import 'impressora.dart';
import 'item_fila.dart';
import 'painel_impressora.dart';
import 'porta_serial.dart';
import 'repositorio.dart';
import 'zpl.dart';

const _verde = Color(0xFF2E9E5B);
const _ambar = Color(0xFFE6B800);

/// Tela unica: a fila, o estado da Zebra e os botoes de imprimir/apagar.
class TelaFila extends StatefulWidget {
  const TelaFila({
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

  /// Enquanto a tela esta aberta, busca novidades (o que o Claude lancou) a cada tanto.
  final Duration intervaloSync;

  @override
  State<TelaFila> createState() => _TelaFilaState();
}

class _TelaFilaState extends State<TelaFila> with WidgetsBindingObserver {
  final Set<String> _marcados = {};
  Timer? _timer;
  bool _imprimindo = false;
  String? _progresso;

  RepositorioFila get repo => widget.repo;
  Impressora get imp => widget.impressora;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(widget.intervaloSync, (_) => repo.sincronizar());
    unawaited(repo.sincronizar());
    if (imp.escolhida != null) unawaited(imp.conectar());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(repo.sincronizar());
      imp.aoVoltarParaOApp();
    }
    if (state == AppLifecycleState.paused) imp.aoIrParaSegundoPlano();
  }

  void _aviso(String msg, {bool erro = false}) {
    if (!mounted) return;
    final cs = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: erro ? cs.error : null,
        duration: Duration(seconds: erro ? 8 : 3),
      ));
  }

  /// Imprime os itens na ordem. Cada item manda [pares] comandos (um por clique) e, so quando o
  /// item inteiro foi enviado, vira "impresso". Se cair no meio, o que ja saiu fica marcado.
  Future<void> _imprimir(List<ItemFila> itens) async {
    if (itens.isEmpty || _imprimindo) return;
    if (imp.escolhida == null) {
      _aviso('Escolha a Zebra primeiro (toque no botão da impressora, no topo).', erro: true);
      return;
    }
    final totalPares = itens.fold<int>(0, (s, i) => s + i.pares);
    setState(() {
      _imprimindo = true;
      _progresso = '0 de $totalPares';
    });
    var feitos = 0;
    try {
      for (final item in itens) {
        final base = feitos;
        await imp.imprimir(
          List.filled(item.pares, item.zpl),
          aoEnviar: (n) {
            if (mounted) setState(() => _progresso = '${base + n} de $totalPares');
          },
        );
        feitos += item.pares;
        await repo.marcarImpresso([item.id]);
        _marcados.remove(item.id);
      }
      _aviso('Pronto: $totalPares clique(s) enviados (${totalPares * 2} etiquetas).');
    } on ErroBluetooth catch (e) {
      _aviso('${e.mensagem}\nO que não foi marcado como impresso continua na fila.', erro: true);
    } finally {
      if (mounted) {
        setState(() {
          _imprimindo = false;
          _progresso = null;
        });
      }
    }
  }

  Future<bool> _confirmar(String titulo, String texto, String botao) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo),
        content: Text(texto),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(botao)),
        ],
      ),
    );
    return r ?? false;
  }

  Future<void> _imprimirTudo() async {
    final pend = repo.pendentes;
    if (pend.isEmpty) return;
    final cliques = pend.fold<int>(0, (s, i) => s + i.pares);
    if (!await _confirmar('Imprimir tudo?', '${pend.length} item(ns), $cliques clique(s) = ${cliques * 2} etiquetas.', 'Imprimir')) return;
    await _imprimir(pend);
  }

  Future<void> _imprimirSelecionados() async {
    final sel = repo.itens.where((i) => _marcados.contains(i.id)).toList();
    await _imprimir(sel);
  }

  Future<void> _apagarItem(ItemFila i) async {
    _marcados.remove(i.id);
    await repo.apagar([i.id]);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Apagado: ${i.nome}'), duration: const Duration(seconds: 4)));
  }

  Future<void> _limparImpressos() async {
    final n = repo.totalImpressos;
    if (n == 0) {
      _aviso('Não há itens impressos para limpar.');
      return;
    }
    if (!await _confirmar('Limpar impressos?', '$n item(ns) já impresso(s) serão apagados. Os pendentes ficam.', 'Limpar')) return;
    _marcados.clear();
    await repo.limparImpressos();
  }

  Future<void> _limparTudo() async {
    final n = repo.itens.length;
    if (n == 0) return;
    if (!await _confirmar('Limpar tudo?', 'Os $n item(ns) da fila serão apagados, os pendentes também.', 'Limpar tudo')) return;
    _marcados.clear();
    await repo.limparTudo();
  }

  void _abrirImpressora() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => PainelImpressora(impressora: imp),
    );
  }

  Future<void> _abrirConfig() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ConfigPage(repo: repo, armazem: widget.armazem, criar: widget.criarFonte),
    ));
  }

  Future<void> _novoItem() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _FormNovoItem(repo: repo),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Etiquetas CAMDA'),
        centerTitle: false,
        actions: [
          ListenableBuilder(
            listenable: imp,
            builder: (context, _) {
              final (cor, texto) = rotuloEstado(imp.estado, cs);
              return TextButton.icon(
                key: const Key('botao-impressora'),
                onPressed: _abrirImpressora,
                icon: Icon(Icons.print, size: 18, color: cor),
                label: Text(imp.estado == EstadoImpressora.conectada ? (imp.escolhida?.nome ?? texto) : texto,
                    overflow: TextOverflow.ellipsis),
              );
            },
          ),
          IconButton(key: const Key('botao-config'), tooltip: 'Conexão com o Turso', icon: const Icon(Icons.settings_outlined), onPressed: _abrirConfig),
          PopupMenuButton<String>(
            key: const Key('menu-limpar'),
            tooltip: 'Limpar',
            onSelected: (v) => v == 'impressos' ? _limparImpressos() : _limparTudo(),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'impressos', child: Text('Limpar impressos')),
              PopupMenuItem(value: 'tudo', child: Text('Limpar tudo')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        key: const Key('botao-novo'),
        onPressed: _novoItem,
        tooltip: 'Nova etiqueta',
        child: const Icon(Icons.add),
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: repo,
          builder: (context, _) {
            final itens = repo.itens;
            final pend = repo.pendentes;
            final cliquesPend = pend.fold<int>(0, (s, i) => s + i.pares);
            final nSel = itens.where((i) => _marcados.contains(i.id)).length;
            return Column(
              children: [
                _Resumo(repo: repo, pendentes: pend.length, cliques: cliquesPend, progresso: _progresso),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: repo.sincronizar,
                    child: itens.isEmpty
                        ? ListView(children: [
                            const SizedBox(height: 80),
                            Icon(Icons.label_outline, size: 56, color: cs.outline),
                            const SizedBox(height: 12),
                            Center(child: Text('A fila está vazia', style: TextStyle(color: cs.outline, fontSize: 16))),
                            const SizedBox(height: 4),
                            Center(
                              child: Text(
                                repo.configurado ? 'Peça ao Claude ou toque em + para lançar.' : 'Toque em ⚙️ e informe o Turso.',
                                style: TextStyle(color: cs.outline),
                              ),
                            ),
                          ])
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                            itemCount: itens.length,
                            itemBuilder: (context, k) {
                              final i = itens[k];
                              return _CartaoItem(
                                item: i,
                                marcado: _marcados.contains(i.id),
                                ocupado: _imprimindo,
                                onMarcar: (v) => setState(() => v ? _marcados.add(i.id) : _marcados.remove(i.id)),
                                onImprimir: () => _imprimir([i]),
                                onApagar: () => _apagarItem(i),
                              );
                            },
                          ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  decoration: BoxDecoration(color: cs.surface, border: Border(top: BorderSide(color: cs.outlineVariant))),
                  child: Row(children: [
                    Expanded(
                      child: FilledButton.icon(
                        key: const Key('botao-imprimir-tudo'),
                        onPressed: _imprimindo || pend.isEmpty ? null : _imprimirTudo,
                        icon: _imprimindo
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.print),
                        label: Text(_imprimindo ? 'Imprimindo $_progresso' : 'Imprimir tudo'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        key: const Key('botao-imprimir-selecionados'),
                        onPressed: _imprimindo || nSel == 0 ? null : _imprimirSelecionados,
                        icon: const Icon(Icons.checklist),
                        label: Text(nSel == 0 ? 'Selecionados' : 'Selecionados ($nSel)'),
                      ),
                    ),
                  ]),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Resumo extends StatelessWidget {
  const _Resumo({required this.repo, required this.pendentes, required this.cliques, this.progresso});

  final RepositorioFila repo;
  final int pendentes;
  final int cliques;
  final String? progresso;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final String sync;
    if (!repo.configurado) {
      sync = 'sem Turso';
    } else if (repo.sincronizando) {
      sync = 'sincronizando…';
    } else if (repo.erro != null) {
      sync = repo.semEnviar > 0 ? '${repo.semEnviar} sem enviar · ${repo.erro}' : '${repo.erro}';
    } else {
      sync = repo.semEnviar > 0 ? '${repo.semEnviar} sem enviar' : 'sincronizado';
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(children: [
        Text('$pendentes pendente(s) · $cliques clique(s)', style: const TextStyle(fontWeight: FontWeight.w600)),
        const Spacer(),
        Flexible(
          child: Text(sync,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: repo.erro != null ? cs.error : cs.outline, fontSize: 12)),
        ),
      ]),
    );
  }
}

class _CartaoItem extends StatelessWidget {
  const _CartaoItem({
    required this.item,
    required this.marcado,
    required this.ocupado,
    required this.onMarcar,
    required this.onImprimir,
    required this.onApagar,
  });

  final ItemFila item;
  final bool marcado;
  final bool ocupado;
  final ValueChanged<bool> onMarcar;
  final VoidCallback onImprimir;
  final VoidCallback onApagar;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final escuro = Theme.of(context).brightness == Brightness.dark;
    final cor = item.impresso ? _verde : _ambar;
    final fundo = Color.alphaBlend(cor.withValues(alpha: escuro ? 0.12 : 0.13), cs.surface);
    final aviso = item.avisoNome;
    return Card(
      key: Key('item-${item.id}'),
      elevation: 0,
      color: fundo,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: cor.withValues(alpha: 0.7), width: 1.2)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Checkbox(key: Key('marcar-${item.id}'), value: marcado, onChanged: ocupado ? null : (v) => onMarcar(v ?? false)),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SizedBox(height: 4),
              Text(item.nome, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              Text(item.codigo, style: TextStyle(fontSize: 15, color: cs.onSurfaceVariant, fontFeatures: const [FontFeature.tabularFigures()])),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                _Selo(texto: item.rotuloCliques, cor: cs.primary, chave: Key('cliques-${item.id}')),
                if (item.impresso) _Selo(texto: '✓ impresso ${_hora(item.impressoEm)}', cor: _verde),
                if (item.doClaude) const Text('🤖', style: TextStyle(fontSize: 14)),
              ]),
              if (aviso != null) ...[
                const SizedBox(height: 6),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.warning_amber_rounded, size: 16, color: _ambar),
                  const SizedBox(width: 4),
                  Expanded(child: Text(aviso, key: Key('aviso-${item.id}'), style: const TextStyle(fontSize: 12.5))),
                ]),
              ],
            ]),
          ),
          Column(children: [
            IconButton(
              key: Key('imprimir-${item.id}'),
              tooltip: item.impresso ? 'Reimprimir' : 'Imprimir',
              icon: Icon(item.impresso ? Icons.replay : Icons.print),
              onPressed: ocupado ? null : onImprimir,
            ),
            IconButton(
              key: Key('apagar-${item.id}'),
              tooltip: 'Apagar',
              icon: const Icon(Icons.delete_outline),
              onPressed: ocupado ? null : onApagar,
            ),
          ]),
        ]),
      ),
    );
  }

  static String _hora(String? em) => em != null && em.length >= 16 ? em.substring(11, 16) : '';
}

class _Selo extends StatelessWidget {
  const _Selo({required this.texto, required this.cor, this.chave});

  final String texto;
  final Color cor;
  final Key? chave;

  @override
  Widget build(BuildContext context) => Container(
        key: chave,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(color: cor.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(20)),
        child: Text(texto, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cor)),
      );
}

class _FormNovoItem extends StatefulWidget {
  const _FormNovoItem({required this.repo});

  final RepositorioFila repo;

  @override
  State<_FormNovoItem> createState() => _FormNovoItemState();
}

class _FormNovoItemState extends State<_FormNovoItem> {
  final _nome = TextEditingController();
  final _codigo = TextEditingController();
  int _pares = 1;
  String? _erro;

  @override
  void dispose() {
    _nome.dispose();
    _codigo.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    final erro = await widget.repo.adicionar(_nome.text, _codigo.text, pares: _pares);
    if (!mounted) return;
    if (erro != null) {
      setState(() => _erro = erro);
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final aviso = avisoDeNome(_nome.text);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Nova etiqueta', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        TextField(
          key: const Key('campo-nome'),
          controller: _nome,
          textCapitalization: TextCapitalization.characters,
          onChanged: (_) => setState(() => _erro = null),
          decoration: const InputDecoration(labelText: 'Nome na etiqueta', border: OutlineInputBorder()),
        ),
        if (aviso != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text('⚠️ $aviso', style: const TextStyle(fontSize: 12.5))),
        const SizedBox(height: 12),
        TextField(
          key: const Key('campo-codigo'),
          controller: _codigo,
          textCapitalization: TextCapitalization.characters,
          onChanged: (_) => setState(() => _erro = null),
          decoration: const InputDecoration(labelText: 'Código', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        Row(children: [
          const Text('Pares (cliques):'),
          IconButton(onPressed: _pares > 1 ? () => setState(() => _pares--) : null, icon: const Icon(Icons.remove_circle_outline)),
          Text('$_pares', key: const Key('valor-pares'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          IconButton(key: const Key('mais-par'), onPressed: _pares < paresMax ? () => setState(() => _pares++) : null, icon: const Icon(Icons.add_circle_outline)),
        ]),
        if (_erro != null) Text(_erro!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        const SizedBox(height: 8),
        SizedBox(width: double.infinity, child: FilledButton(key: const Key('botao-lancar'), onPressed: _salvar, child: const Text('Lançar na fila'))),
      ]),
    );
  }
}
