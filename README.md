# Etiquetas CAMDA

Fila de etiquetas que imprime direto na Zebra por **Bluetooth clássico (SPP)**, no lugar de copiar o ZPL para o "Serial Bluetooth Terminal".

1. Você manda foto ou nome do produto no chat do Claude. Ele acha o código com `buscar_produto` e lança na fila (`adicionar_etiqueta`, no [camda-mcp](https://github.com/LeoLira1/camda-mcp)).
2. O app mostra a fila (em até 30 s). Você aperta imprimir e as etiquetas saem.
3. Apaga item por item, ou limpa a lista.

## No app

- Cada item: **nome**, **código**, **N cliques** (1 clique = 1 par de etiquetas = 1 comando ZPL) e 🤖 quando veio do Claude.
- Botões: **Imprimir tudo**, **Selecionados**, 🖨️ (imprimir/reimprimir um item), 🗑️ (apagar item), menu ⋮ → **Limpar impressos** / **Limpar tudo**, **+** (lançar à mão).
- Depois de imprimir o item vira "✓ impresso 14:32" e **não some**: dá para reimprimir uma que saiu errada.
- ⚠️ quando o nome não cabe na letra maior (mais de 11 letras a fonte diminui; acima de 26 é cortado).
- 🖨️ no topo: escolher a Zebra (entre as já pareadas), reconectar, etiqueta de teste e o diário da conexão.
- Offline: tudo grava primeiro no aparelho e sobe para o Turso quando a rede volta (a cada 30 s com o app aberto, ao voltar para o app e ao puxar a lista para baixo).

## Modelo de etiqueta

Igual ao `zplVendido` do camda-mcp (`src/etiquetas.ts`): `^PW832`, par nas posições x=60 e x=490, nome em `^A0N,52,52` (diminui conforme o tamanho) e código em `^A0N,58,58`, y=112. Sem QR code. Código em `lib/zpl.dart`, com os mesmos testes do MCP.

## Banco (Turso)

Mesmo banco do CAMDA Estoque, **uma tabela nova** `fila_etiquetas` (criada sozinha, pelo app ou pelo MCP). Nenhuma tabela existente é alterada.

| Coluna | Conteúdo |
|---|---|
| `id` | 8 caracteres hex, sorteados no aparelho |
| `codigo`, `nome` | texto da etiqueta (sem acento, maiúsculo) |
| `pares` | pares de etiquetas = cliques (padrão 1) |
| `status` | `pendente` ou `impresso` |
| `criado_em`, `impresso_em` | horário de Brasília `AAAA-MM-DD HH:MM:SS` |
| `origem` | `app` ou `Claude (MCP)` |

O token fica **só no aparelho** (⚙️ → URL + token do Turso, os mesmos do Gondolas/Risca).

## Instalar (sem PC)

1. Celular: `github.com/LeoLira1/etiquetaszebra` → **Actions** → **Build & Release APK** → **Run workflow**.
2. Espere a bolinha ficar verde (roda `flutter analyze`, `flutter test` e a verificação do SQL).
3. Aba **Releases** → mais recente → baixe **app-release.apk** e instale.
4. Abra o app → ⚙️ → URL + token → **Testar** → **Salvar**.

Pacote `com.camda.etiquetas_camda`. Para o APK novo atualizar o antigo por cima, cadastre o secret `DEBUG_KEYSTORE_BASE64` (como no Risca); sem ele, desinstale e instale de novo.

## Primeiro teste na Zebra

1. Pareie a Zebra em Configurações do Android › Bluetooth (senha 0000 ou 1234, se pedir).
2. **Feche o Serial Bluetooth Terminal** (só um aparelho fala com a Zebra por vez).
3. App → 🖨️ → **Escolher a Zebra** → permita "Dispositivos por perto" → toque na Zebra → **Etiqueta de teste**.

## Bluetooth

Plugin `flutter_bluetooth_classic_serial` (Android, RFCOMM/SPP, bytes brutos) + `permission_handler` (BLUETOOTH_CONNECT/SCAN do Android 12+). Lembra a Zebra escolhida e reconecta sozinho (2 s, 4 s, 8 s, 15 s, 30 s…); com o app em segundo plano as tentativas param e voltam ao abrir. Mensagens claras para: permissão negada, Bluetooth desligado, nenhum aparelho pareado e falha de conexão.

## Desenvolvimento

```bash
flutter pub get && flutter analyze && flutter test
python3 tool/verify_sql.py            # roda os SQLs reais do app num SQLite
./tool/preparar_android.sh && dart run flutter_launcher_icons && flutter build apk --release
python3 tool/gerar_icone.py           # refaz os PNGs do ícone
```
O projeto `android/` não fica no repositório: `tool/preparar_android.sh` o gera (como no Gondolas/Risca).
