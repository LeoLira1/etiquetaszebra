# Etiquetas CAMDA

Fila de etiquetas que imprime direto na Zebra por **Bluetooth clássico (SPP)**, no lugar de copiar o ZPL para o "Serial Bluetooth Terminal".

**Estado: fase 1** — só conecta na Zebra e imprime UMA etiqueta de teste. A fila (Turso + ferramentas do MCP) vem depois da confirmação na impressora.

## Instalar (sem PC)

1. Celular: `github.com/LeoLira1/etiquetaszebra` → **Actions** → **Build & Release APK** → **Run workflow**.
2. Espere a bolinha ficar verde (build roda `flutter analyze` e `flutter test`).
3. Aba **Releases** → mais recente → baixe **app-release.apk** e instale.

## Testar

1. Pareie a Zebra em Configurações do Android › Bluetooth (senha 0000 ou 1234, se pedir).
2. **Feche o Serial Bluetooth Terminal** (só um aparelho fala com a Zebra por vez).
3. Abra o app → **Escolher a Zebra** → permita "Dispositivos por perto" → toque na Zebra.
4. **Imprimir etiqueta de teste**: sai um par com `TESTE ZEBRA` e `1234567`.

## Modelo de etiqueta

Igual ao `zplVendido` do camda-mcp (`src/etiquetas.ts`): `^PW832`, par nas posições x=60 e x=490, nome em `^A0N,52,52` (diminui conforme o tamanho) e código em `^A0N,58,58`, y=112. Um envio = um par = "1 clique". Código em `lib/zpl.dart`, com os mesmos testes do MCP.

## Bluetooth

Plugin `flutter_bluetooth_classic_serial` (Android, RFCOMM/SPP, bytes brutos) + `permission_handler` (BLUETOOTH_CONNECT/SCAN do Android 12+). Lembra a Zebra escolhida, reconecta sozinho (2 s, 4 s, 8 s, 15 s, 30 s…) e para as tentativas com o app em segundo plano.

## Desenvolvimento

```bash
flutter pub get && flutter analyze && flutter test
./tool/preparar_android.sh && flutter build apk --release
```
O projeto `android/` não fica no repositório: `tool/preparar_android.sh` o gera (como no Gondolas/Risca).
