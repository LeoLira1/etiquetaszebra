import 'package:flutter/material.dart';

import 'armazenamento.dart';
import 'fonte_remota.dart';
import 'repositorio.dart';
import 'turso_remoto.dart';

/// Mesmos nomes de chave do Gondolas e do Risca: o token fica so no aparelho (shared_preferences),
/// nunca no repositorio nem no APK.
const chaveUrl = 'turso_db_url';
const chaveToken = 'turso_db_token';

typedef CriarFonte = FonteRemota Function(String url, String token);

FonteRemota criarFontePadrao(String url, String token) => TursoRemoto(url, token);

/// Le URL/token salvos e liga o repositorio ao Turso (se houver).
Future<void> conectarSalvo(RepositorioFila repo, Armazenamento armazem, {CriarFonte criar = criarFontePadrao}) async {
  final url = (await armazem.ler(chaveUrl))?.trim() ?? '';
  final token = (await armazem.ler(chaveToken))?.trim() ?? '';
  await repo.usarFonte(url.isEmpty || token.isEmpty ? null : criar(url, token));
}

class ConfigPage extends StatefulWidget {
  const ConfigPage({super.key, required this.repo, required this.armazem, this.criar = criarFontePadrao});

  final RepositorioFila repo;
  final Armazenamento armazem;
  final CriarFonte criar;

  @override
  State<ConfigPage> createState() => _ConfigPageState();
}

class _ConfigPageState extends State<ConfigPage> {
  final _url = TextEditingController();
  final _token = TextEditingController();
  bool _ver = false;
  bool _ocupado = false;
  String? _status;
  bool _statusOk = false;

  @override
  void initState() {
    super.initState();
    widget.armazem.ler(chaveUrl).then((v) {
      if (mounted && v != null) _url.text = v;
    });
    widget.armazem.ler(chaveToken).then((v) {
      if (mounted && v != null) _token.text = v;
    });
  }

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _testar() async {
    final url = _url.text.trim();
    final token = _token.text.trim();
    if (url.isEmpty || token.isEmpty) {
      setState(() {
        _status = 'Preencha URL e token.';
        _statusOk = false;
      });
      return;
    }
    setState(() {
      _ocupado = true;
      _status = 'Testando…';
    });
    final f = widget.criar(url, token);
    try {
      await f.garantirEsquema();
      await f.baixar();
      if (mounted) {
        setState(() {
          _status = 'Conectou e a tabela `fila_etiquetas` está pronta.';
          _statusOk = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = 'Não conectou: $e';
          _statusOk = false;
        });
      }
    } finally {
      try {
        await f.fechar();
      } catch (_) {}
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _salvar() async {
    await widget.armazem.gravar(chaveUrl, _url.text.trim());
    await widget.armazem.gravar(chaveToken, _token.text.trim());
    await conectarSalvo(widget.repo, widget.armazem, criar: widget.criar);
    widget.repo.sincronizar();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Conexão com o Turso')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Use o mesmo banco do CAMDA Estoque (a mesma URL e o mesmo token do Gondolas e do Risca). '
            'A tabela nova `fila_etiquetas` é criada sozinha; nenhuma tabela existente é alterada.',
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('campo-url'),
            controller: _url,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'URL do banco',
              hintText: 'libsql://camda-estoque-leolira1.aws-us-east-2.turso.io',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('campo-token'),
            controller: _token,
            obscureText: !_ver,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: 'Token',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_ver ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _ver = !_ver),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                key: const Key('botao-testar'),
                onPressed: _ocupado ? null : _testar,
                child: const Text('Testar'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                key: const Key('botao-salvar'),
                onPressed: _ocupado ? null : _salvar,
                child: const Text('Salvar'),
              ),
            ),
          ]),
          if (_status != null) ...[
            const SizedBox(height: 16),
            Text(_status!, style: TextStyle(color: _statusOk ? const Color(0xFF2E9E5B) : cs.error)),
          ],
        ],
      ),
    );
  }
}
