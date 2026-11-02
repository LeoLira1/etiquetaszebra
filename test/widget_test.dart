import 'package:etiquetas_camda/impressora.dart';
import 'package:etiquetas_camda/main.dart';
import 'package:etiquetas_camda/porta_serial.dart';
import 'package:flutter_test/flutter_test.dart';

import 'impressora_test.dart' show MemoriaFalsa, PortaFalsa;

void main() {
  testWidgets('tela de teste: sem Zebra escolhida o botao de imprimir fica desligado', (tester) async {
    final imp = Impressora(PortaFalsa(), MemoriaFalsa());
    await imp.carregar();
    await tester.pumpWidget(EtiquetasApp(impressora: imp));
    expect(find.text('Etiquetas CAMDA'), findsOneWidget);
    expect(find.text('Nenhuma impressora escolhida'), findsOneWidget);
    expect(find.text('Escolher a Zebra'), findsOneWidget);
    expect(find.text('Imprimir etiqueta de teste'), findsOneWidget);
  });

  testWidgets('com Zebra lembrada conecta e imprime o teste', (tester) async {
    final porta = PortaFalsa();
    final mem = MemoriaFalsa()..guardada = const Pareado('ZEBRA ZT410', 'AA:BB');
    final imp = Impressora(porta, mem, pausaEntreEtiquetas: Duration.zero);
    await imp.carregar();
    await tester.pumpWidget(EtiquetasApp(impressora: imp));
    await tester.pumpAndSettle();
    expect(find.text('Conectada'), findsOneWidget);
    await tester.tap(find.text('Imprimir etiqueta de teste'));
    await tester.pumpAndSettle();
    expect(porta.enviados, hasLength(1));
    expect(porta.enviados.first, contains('^FDTESTE ZEBRA^FS'));
    expect(find.textContaining('Enviado!'), findsOneWidget);
  });
}
