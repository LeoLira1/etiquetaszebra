import 'package:shared_preferences/shared_preferences.dart';

import 'impressora.dart';
import 'porta_serial.dart';

const chaveNome = 'zebra_nome';
const chaveEndereco = 'zebra_endereco';

/// Guarda a Zebra escolhida no aparelho (shared_preferences).
class MemoriaPrefs implements MemoriaImpressora {
  @override
  Future<Pareado?> ler() async {
    final p = await SharedPreferences.getInstance();
    final end = p.getString(chaveEndereco);
    if (end == null || end.isEmpty) return null;
    return Pareado(p.getString(chaveNome) ?? end, end);
  }

  @override
  Future<void> gravar(Pareado? d) async {
    final p = await SharedPreferences.getInstance();
    if (d == null) {
      await p.remove(chaveEndereco);
      await p.remove(chaveNome);
    } else {
      await p.setString(chaveEndereco, d.endereco);
      await p.setString(chaveNome, d.nome);
    }
  }
}
