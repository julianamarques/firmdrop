# SamFW — firmwares Samsung no Mac

App nativo para macOS (SwiftUI) que baixa firmwares **oficiais** da Samsung direto do
servidor FUS (*Firmware Update Server*), o mesmo usado pelo Smart Switch. É o que sites
como o SamMobile fazem por trás. Os arquivos são idênticos aos oficiais e saem prontos
para o Odin.

- Busca por modelo e região (Brasil: ZTO, Claro, TIM, Vivo, ou qualquer outro CSC)
- Mostra nome comercial, tamanho, versão do Android e versões anteriores com mês/ano
- **Não exige IMEI**
- Downloads com pausa e retomada, inclusive depois de fechar o app
- Confere o **CRC32** e decifra o `.enc4` automaticamente
- Evita que o Mac entre em repouso durante o download, avisa com notificação ao terminar
  e mostra a contagem de downloads no Dock

Visual Liquid Glass (barras e cartões de vidro flutuantes, modo claro e escuro).
Requer **macOS 26** ou mais novo.

## Compilar e instalar

É preciso o Xcode 26 ou mais novo (ou as Command Line Tools com Swift 6.2+).

```sh
scripts/build-app.sh             # gera build/SamFW.app
scripts/build-app.sh --install   # e copia para /Applications
open build/SamFW.app
```

Opções: `--universal` gera um binário para Apple Silicon e Intel.

Para desenvolver no Xcode, abra o `Package.swift` (`xed .`) e rode o esquema **SamFW**.

### Levar para outro Mac

O app é assinado *ad-hoc* (sem conta de desenvolvedor). Em outro Mac, o Gatekeeper vai
bloquear a primeira abertura. Para liberar, clique com o botão direito no app e escolha
**Abrir**, ou use Ajustes do Sistema › Privacidade e Segurança › **Abrir Mesmo Assim**.
Para distribuir sem esse aviso, é preciso assinar e notarizar com uma conta Apple
Developer.

## Uso

1. Digite o modelo, por exemplo `SM-A556E`. Ele aparece em Configurações › Sobre o
   telefone; sufixos como `/DS` podem ficar, o app remove.
2. Escolha a região e clique em **Buscar**.
3. Clique em **Baixar** na versão mais recente ou em qualquer versão anterior.

Os arquivos vão para `~/Downloads`; a pasta pode ser trocada em **SamFW › Ajustes** (⌘,).
Também nos Ajustes: manter o `.enc4` depois de decifrar e escolher a região padrão.

### Regiões do Brasil

| CSC | Região/operadora |
|-----|------------------|
| `ZTO` | Brasil, desbloqueado (padrão) |
| `ZTA` | Claro |
| `ZTM` | TIM |
| `ZVV` | Vivo |

Todos servem o mesmo firmware multi-CSC (`OWO`). O CSC ativo é escolhido pelo chip.

### Espaço em disco

Durante a decifragem, o `.enc4` e o `.zip` existem ao mesmo tempo, então é preciso o
**dobro** do tamanho do firmware. Um topo de linha como o S24 Ultra passa de 19 GB.

## Como funciona

1. **Versões**: `https://fota-cloud-dn.ospserver.net/firmware/{CSC}/{MODELO}/version.xml`
   (público; o CDN só aceita alguns User-Agents).
2. **Autenticação**: `NF_SmartDownloadGenerateNonce.do` devolve um nonce. A assinatura é
   esse nonce passado por uma cifra AES *white-box* extraída do Smart Switch, cujas
   tabelas ficam no `auth_param.dat` (ver abaixo).
3. **BinaryInform**: informa modelo, CSC e versão; a resposta traz o nome do arquivo, o
   tamanho, o CRC32 e o `LOGIC_VALUE_FACTORY`, do qual se deriva a chave AES.
4. **BinaryInitForMass** libera o arquivo, que é baixado de
   `cloud-neofussvr.samsungmobile.com/NF_SmartDownloadBinaryForMass.do` (aceita `Range`).
5. **Decifragem**: AES-128-ECB com `MD5(logicCheck(versão, LOGIC_VALUE_FACTORY))`.

### `auth_param.dat`

Na primeira busca, o app baixa o `auth_param.dat` (~800 KB) do projeto
[Bifrost](https://github.com/zacharee/SamloaderKotlin) num commit fixo, confere o SHA-256
e guarda em `~/Library/Caches/SamFW/`. Ele não é distribuído neste repositório.

Se a Samsung trocar o esquema de autenticação, as buscas passam a falhar com
"Autenticação recusada pelo servidor" (HTTP/status 401). Nesse caso, é preciso
atualizar `paramsURL`/`paramsSHA256` em `Sources/SamFWCore/Authenticator.swift`
(e possivelmente o algoritmo) acompanhando o Bifrost.

## Estrutura

| Caminho | Conteúdo |
|---|---|
| `Sources/SamFWCore/` | Protocolo FUS, autenticação, criptografia e motor de download (sem UI) |
| `Sources/SamFW/` | App SwiftUI: busca, lista de downloads, ajustes |
| `Tests/SamFWCoreTests/` | Testes (`swift test`) |
| `Resources/` | `Info.plist` e ícone do app |
| `scripts/` | `build-app.sh` (monta o .app) e `make-icon.sh` (gera o ícone) |

## Testes

```sh
swift test                  # testes offline
SAMFW_LIVE=1 swift test     # inclui testes contra o servidor real (baixa ~30 MB)
```

## Limitações

- O `version.xml` só lista versões anteriores que têm atualização OTA. Outras podem
  existir no servidor, mas o app não tem como descobri-las.
- Use para seus próprios aparelhos. Redistribuir os firmwares publicamente pode violar os
  termos de uso da Samsung.

Créditos e licença do código de terceiros: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
