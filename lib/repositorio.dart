import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'armazenamento.dart';
import 'fonte_remota.dart';
import 'item_fila.dart';
import 'zpl.dart';

const _chaveEstado = 'fila_estado_v1';

/// Dono da fila. A tela so le daqui: tudo grava primeiro no aparelho (instantaneo, funciona sem
/// rede) e entra numa fila de [Operacao]; [sincronizar] esvazia essa fila no Turso e puxa o que o
/// Claude (MCP) lancou. Mesmo molde do Risca.
class RepositorioFila extends ChangeNotifier {
  RepositorioFila(this._armazem, {DateTime Function()? relogio}) : _agora = relogio ?? DateTime.now;

  final Armazenamento _armazem;
  final DateTime Function() _agora;

  FonteRemota? _fonte;
  List<ItemFila> _itens = [];
  final List<Operacao> _fila = [];

  bool _sincronizando = false;
  bool _repetir = false;
  Future<bool>? _emAndamento;
  String? _erro;
  DateTime? _ultimaSync;

  List<ItemFila> get itens => ordenar(_itens);
  List<ItemFila> get pendentes => _itens.where((i) => !i.impresso).toList()..sort((a, b) => a.criadoEm.compareTo(b.criadoEm));
  int get totalImpressos => _itens.where((i) => i.impresso).length;
  int get semEnviar => _fila.length;
  bool get sincronizando => _sincronizando;
  bool get configurado => _fonte != null;
  String? get erro => _erro;
  DateTime? get ultimaSync => _ultimaSync;

  ItemFila? porId(String id) {
    for (final i in _itens) {
      if (i.id == id) return i;
    }
    return null;
  }

  /// Troca o banco (primeira configuracao ou token novo). A fila fica: o que foi feito offline
  /// ainda precisa subir para o banco novo.
  Future<void> usarFonte(FonteRemota? fonte) async {
    final antiga = _fonte;
    _fonte = fonte;
    _erro = null;
    if (antiga != null) {
      try {
        await antiga.fechar();
      } catch (_) {}
    }
    notifyListeners();
  }

  /// Le o cache do aparelho: o app abre instantaneo, antes de qualquer rede.
  Future<void> carregar() async {
    final bruto = await _armazem.ler(_chaveEstado);
    if (bruto != null) {
      try {
        final j = json.decode(bruto) as Map<String, dynamic>;
        _itens = [for (final t in (j['itens'] as List? ?? const [])) ItemFila.fromJson(Map<String, Object?>.from(t as Map))];
        _fila
          ..clear()
          ..addAll([for (final o in (j['fila'] as List? ?? const [])) Operacao.fromJson(Map<String, Object?>.from(o as Map))]);
        final s = j['ultima_sync'] as String?;
        _ultimaSync = s == null ? null : DateTime.tryParse(s);
      } catch (_) {
        _itens = [];
        _fila.clear();
      }
    }
    notifyListeners();
  }

  Future<void> _salvar() => _armazem.gravar(
        _chaveEstado,
        json.encode({
          'itens': _itens.map((t) => t.toJson()).toList(),
          'fila': _fila.map((o) => o.toJson()).toList(),
          'ultima_sync': _ultimaSync?.toIso8601String(),
        }),
      );

  /// Lanca um item na fila. Devolve a mensagem de erro de validacao, ou null se adicionou.
  Future<String?> adicionar(String nome, String codigo, {int pares = 1}) async {
    final n = textoZpl(nome);
    final c = textoZpl(codigo);
    if (n.isEmpty) return 'Escreva o nome da etiqueta.';
    if (c.isEmpty) return 'Escreva o código do produto.';
    if (pares < 1 || pares > paresMax) return 'Pares deve ficar entre 1 e $paresMax.';
    final novo = ItemFila(id: novoId(), codigo: c, nome: n, pares: pares, criadoEm: agoraBrt(_agora()));
    _itens = [..._itens, novo];
    _fila.add(Operacao.criar(novo));
    await _salvar();
    notifyListeners();
    unawaited(sincronizar());
    return null;
  }

  /// Marca como impresso (nao some: da para reimprimir uma que saiu errada).
  Future<void> marcarImpresso(Iterable<String> ids) async {
    final em = agoraBrt(_agora());
    final set = ids.toSet();
    var mudou = false;
    _itens = [
      for (final i in _itens)
        if (set.contains(i.id))
          () {
            mudou = true;
            _fila.add(Operacao.imprimir(i.id, em));
            return i.copyWith(status: statusImpresso, impressoEm: em);
          }()
        else
          i,
    ];
    if (!mudou) return;
    await _salvar();
    notifyListeners();
    unawaited(sincronizar());
  }

  /// Apaga itens (um, os impressos ou tudo): cada um vira um DELETE por id, entao nada que o Claude
  /// lancou depois do toque e apagado por engano.
  Future<void> apagar(Iterable<String> ids) async {
    final set = ids.toSet();
    final existentes = _itens.where((i) => set.contains(i.id)).map((i) => i.id).toList();
    if (existentes.isEmpty) return;
    _itens = _itens.where((i) => !set.contains(i.id)).toList();
    // Um item criado e apagado antes de subir nao precisa nem ir ao banco.
    final criadosSoLocal = _fila.where((o) => o.tipo == TipoOperacao.criar && set.contains(o.idItem)).map((o) => o.idItem).toSet();
    _fila.removeWhere((o) => set.contains(o.idItem) && o.tipo != TipoOperacao.apagar);
    for (final id in existentes) {
      if (!criadosSoLocal.contains(id)) _fila.add(Operacao.apagar(id));
    }
    await _salvar();
    notifyListeners();
    unawaited(sincronizar());
  }

  Future<void> limparImpressos() => apagar(_itens.where((i) => i.impresso).map((i) => i.id));

  Future<void> limparTudo() => apagar(_itens.map((i) => i.id));

  /// Envia a fila e puxa o banco. Nunca lanca: sem rede vira [erro] e a fila espera.
  /// Chamada durante um sync em andamento nao empilha outro: pede uma repeticao.
  Future<bool> sincronizar() {
    final fonte = _fonte;
    if (fonte == null) return Future.value(false);
    final andando = _emAndamento;
    if (andando != null) {
      _repetir = true;
      return andando;
    }
    return _emAndamento = _sincronizar(fonte).whenComplete(() => _emAndamento = null);
  }

  Future<bool> _sincronizar(FonteRemota fonte) async {
    _sincronizando = true;
    notifyListeners();
    var ok = false;
    do {
      _repetir = false;
      try {
        await fonte.garantirEsquema();
        while (_fila.isNotEmpty) {
          await fonte.aplicar(_fila.first);
          _fila.removeAt(0);
          await _salvar();
        }
        final remotos = await fonte.baixar();
        _mesclar(remotos);
        _ultimaSync = _agora();
        _erro = null;
        ok = true;
        await _salvar();
      } catch (e) {
        _erro = _mensagem(e);
        ok = false;
      }
    } while (_repetir);
    _sincronizando = false;
    notifyListeners();
    return ok;
  }

  /// O banco manda, exceto nos itens que ainda tem operacao na fila: esses ficam como estao no
  /// aparelho (senao o sync desfaria o toque que acabou de ser feito). Roda sem `await`.
  void _mesclar(List<ItemFila> remotos) {
    final naFila = _fila.map((o) => o.idItem).toSet();
    final apagados = _fila.where((o) => o.tipo == TipoOperacao.apagar).map((o) => o.idItem).toSet();
    final locais = {for (final t in _itens) t.id: t};
    _itens = [
      for (final r in remotos)
        if (!naFila.contains(r.id)) r,
      for (final id in naFila)
        if (!apagados.contains(id) && locais[id] != null) locais[id]!,
    ];
  }

  String _mensagem(Object e) {
    final t = e.toString().replaceFirst('Exception: ', '');
    if (e is TimeoutException) return 'Sem resposta do Turso (sem rede?).';
    if (t.contains('SocketException') || t.contains('sem rede')) return 'Sem rede.';
    return t.length > 120 ? '${t.substring(0, 120)}…' : t;
  }
}
