import 'package:etiquetas_camda/zpl.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Os mesmos casos de test/etiquetas.test.ts do camda-mcp.
  test('nomeEtiqueta: dois primeiros nomes, bico e numeracao', () {
    expect(nomeEtiqueta('ÓLEO DE SOJA C/ ADITIVO 4X5L'), 'OLEO SOJA');
    expect(nomeEtiqueta('SERINGA C/50 DESCARTÁVEL'), 'SERINGA DESCARTAVEL');
    expect(nomeEtiqueta('BOTINA DE SEGURANCA S/BICO FUJIWARA PRETA N39'), 'BOTINA S/BICO N39');
    expect(nomeEtiqueta('BOTINA C/ BICO DE AÇO Nº 42'), 'BOTINA C/BICO N42');
    expect(nomeEtiqueta('BOTA PVC BRANCA N40'), 'BOTA N40');
    expect(nomeEtiqueta('BOTINA S/BICO PRETA'), 'BOTINA S/BICO');
    expect(nomeEtiqueta('NEXIDE NOVO 1L'), 'NEXIDE NOVO');
  });

  test('fontes por tamanho do nome e do codigo', () {
    final f = [11, 12, 14, 15, 17, 18, 21, 22].map((n) => fonteNome('A' * n)).toList();
    expect(f, [52, 40, 40, 32, 32, 26, 26, 22]);
    expect(fonteCodigo('1234567'), 58);
    expect(fonteCodigo('12345678'), 44);
  });

  test('modelo aprovado: nome 52, codigo 58 em y=112, par em x=60 e x=490', () {
    expect(
      zplEtiqueta('NOME', 'CODIGO'),
      '^XA^LS0^LH0,0^PW832'
      '^FO60,40^A0N,52,52^FDNOME^FS^FO60,112^A0N,58,58^FDCODIGO^FS'
      '^FO490,40^A0N,52,52^FDNOME^FS^FO490,112^A0N,58,58^FDCODIGO^FS^XZ',
    );
  });

  test('nome menor desce para encostar no codigo; codigo longo usa 44', () {
    expect(zplEtiqueta('ROUNDUP ORIGINAL', '1234'), contains('^FO60,60^A0N,32,32^FDROUNDUP ORIGINAL^FS'));
    expect(zplEtiqueta('A', 'US10047813'), contains('^FO60,112^A0N,44,44^FDUS10047813^FS'));
  });

  test('texto seguro: sem acento, sem ^ e ~, maiusculo', () {
    expect(textoZpl('  óleo ^de~ soja  '), 'OLEO DE SOJA');
    expect(zplEtiqueta('A^B~C', '1'), contains('^FDA B C^FS'));
  });

  test('nome acima de 26 letras e cortado e o comando fica curto', () {
    final z = zplEtiqueta('A' * 40, 'US10047813');
    expect(z, contains('A' * 26));
    expect(z, isNot(contains('A' * 27)));
    expect(z.length, lessThanOrEqualTo(250));
  });

  test('aviso quando o nome nao cabe na letra maior', () {
    expect(cabeNaLetraMaior('ROUNDUP'), isTrue);
    expect(avisoDeNome('ROUNDUP'), isNull);
    expect(avisoDeNome('ROUNDUP ORIGINAL'), contains('letra 32'));
    expect(avisoDeNome('A' * 30), contains('cortado em 26'));
  });
}
