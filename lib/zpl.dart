// ZPL das etiquetas - MESMO modelo do camda-mcp (src/etiquetas.ts, zplVendido):
// rolo 2-up da Zebra (ZT410, 203 dpi), ^PW832, dois exemplares do mesmo produto
// por comando (x = 60 e x = 490). Cada comando imprime UM PAR de etiquetas.
//
// Mantenha este arquivo igual ao do MCP: se mudar o modelo la, mude aqui.

/// Maior nome (em letras) que ainda cabe na etiqueta, na menor fonte (22).
const nomeMax = 26;

/// Palavras que nao contam como "nome" na etiqueta.
const _ignorar = {'DE', 'DA', 'DO', 'DAS', 'DOS', 'E', 'A', 'O', 'EM', 'COM', 'SEM', 'PARA', 'P/', 'C/', 'S/'};

const _comAcento = 'ÀÁÂÃÄÅàáâãäåÈÉÊËèéêëÌÍÎÏìíîïÒÓÔÕÖòóôõöÙÚÛÜùúûüÇçÑñÝýÿ';
const _semAcento = 'AAAAAAaaaaaaEEEEeeeeIIIIiiiiOOOOOoooooUUUUuuuuCcNnYyy';

String semAcento(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    final c = String.fromCharCode(r);
    final i = _comAcento.indexOf(c);
    b.write(i >= 0 ? _semAcento[i] : c);
  }
  return b.toString();
}

/// Texto seguro para ^FD: sem acento, maiusculo, sem ^ e ~ (comandos ZPL) e so ASCII.
String textoZpl(String s) {
  return semAcento(s)
      .toUpperCase()
      .replaceAll(RegExp(r'[\^~]'), ' ')
      .replaceAll(RegExp(r'[^\x20-\x7E]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// Os dois primeiros nomes da descricao, sem DE/DA/DO/C//S/ e afins.
/// Com S/BICO ou C/BICO e/ou numeracao (N39), vira primeiro nome + bico + numeracao.
String nomeEtiqueta(String descricao) {
  final texto = textoZpl(descricao);
  final palavras = texto
      .split(' ')
      .where((p) => RegExp(r'[A-Z0-9]').hasMatch(p))
      .where((p) => !_ignorar.contains(p) && !RegExp(r'^[CSP]/.').hasMatch(p) && !RegExp(r'^N\d+$').hasMatch(p))
      .toList();
  final bico = RegExp(r'(?:^|\s)([CS])/\s*BICO\b').firstMatch(texto);
  final numero = RegExp(r'(?:^|\s)N\s?(\d+)\b').firstMatch(texto);
  if (bico != null || numero != null) {
    return [
      if (palavras.isNotEmpty) palavras.first,
      if (bico != null) '${bico.group(1)}/BICO',
      if (numero != null) 'N${numero.group(1)}',
    ].join(' ');
  }
  return palavras.take(2).join(' ');
}

/// Fonte do nome pelo n. de caracteres: ate 11 = 52, 12-14 = 40, 15-17 = 32, 18-21 = 26, acima = 22.
int fonteNome(String nome) {
  final n = nome.length;
  if (n <= 11) return 52;
  if (n <= 14) return 40;
  if (n <= 17) return 32;
  if (n <= 21) return 26;
  return 22;
}

/// Fonte do codigo: 58, ou 44 com 8 caracteres ou mais.
int fonteCodigo(String codigo) => codigo.length >= 8 ? 44 : 58;

/// true quando o nome sai na letra maior (52). Acima de 11 letras a fonte diminui.
bool cabeNaLetraMaior(String nome) => textoZpl(nome).length <= 11;

/// Aviso para mostrar na fila quando o nome nao cabe na letra maior; null se cabe.
String? avisoDeNome(String nome) {
  final n = textoZpl(nome).length;
  if (n <= 11) return null;
  if (n > nomeMax) {
    return 'Nome grande demais ($n letras): vai ser cortado em $nomeMax para caber.';
  }
  return 'Nome com $n letras: não cabe na letra maior, sai com letra ${fonteNome(textoZpl(nome))}.';
}

/// Um PAR de etiquetas (x = 60 e x = 490), o mesmo produto nas duas.
/// O nome menor desce para ficar encostado no codigo (y = 92 - fonte; codigo em y = 112).
String zplEtiqueta(String nome, String codigo) {
  var n = textoZpl(nome);
  if (n.length > nomeMax) n = n.substring(0, nomeMax).trim();
  final c = textoZpl(codigo);
  final fn = fonteNome(n);
  final fc = fonteCodigo(c);
  final yn = 92 - fn;
  String um(int x) => '^FO$x,$yn^A0N,$fn,$fn^FD$n^FS^FO$x,112^A0N,$fc,$fc^FD$c^FS';
  return '^XA^LS0^LH0,0^PW832${um(60)}${um(490)}^XZ';
}
