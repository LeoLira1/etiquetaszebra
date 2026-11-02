import 'package:shared_preferences/shared_preferences.dart';

/// Onde o app guarda texto no aparelho. Existe para os testes trocarem o
/// `shared_preferences` por uma memória.
abstract class Armazenamento {
  Future<String?> ler(String chave);
  Future<void> gravar(String chave, String valor);
}

class ArmazenamentoPrefs implements Armazenamento {
  @override
  Future<String?> ler(String chave) async => (await SharedPreferences.getInstance()).getString(chave);

  @override
  Future<void> gravar(String chave, String valor) async {
    await (await SharedPreferences.getInstance()).setString(chave, valor);
  }
}

class ArmazenamentoMemoria implements Armazenamento {
  final Map<String, String> dados = {};

  @override
  Future<String?> ler(String chave) async => dados[chave];

  @override
  Future<void> gravar(String chave, String valor) async => dados[chave] = valor;
}
