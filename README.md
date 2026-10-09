# FirmDrop — firmwares Samsung no Mac

App nativo para macOS (SwiftUI) que baixa firmwares **oficiais** da Samsung direto do
servidor FUS (*Firmware Update Server*), o mesmo usado pelo Smart Switch. É o que sites
como o SamMobile fazem por trás. Os arquivos são os pacotes oficiais da Samsung, sem
nenhuma modificação: o app só decifra o `.enc4` com a chave fornecida pelo servidor, e o
`.zip` sai pronto para o Odin.

- Busca por modelo e região (Brasil: ZTO, Claro, TIM, Vivo, ou qualquer outro CSC)
- Mostra nome comercial, tamanho, versão do Android e versões anteriores com mês/ano
- **Não exige IMEI**
- Downloads com pausa e retomada, inclusive depois de fechar o app
- Confere o **CRC32** e decifra o `.enc4` automaticamente
- Evita que o Mac entre em repouso durante o download, avisa com notificação ao terminar
  e mostra a contagem de downloads no Dock
- Avisa quando há uma versão nova do app (Releases do GitHub)

Visual Liquid Glass (barras e cartões de vidro flutuantes, modo claro e escuro).
Requer **macOS 26** ou mais novo.

## Instalar

1. Baixe o `FirmDrop.dmg` da versão mais recente na [página de Releases](https://github.com/julianamarques/firmdrop/releases).
2. Abra o arquivo e arraste o **FirmDrop** para **Aplicativos**.

O app avisa quando há uma versão nova. Em **FirmDrop › Verificar Atualizações…** você verifica
na hora, e em **Ajustes › Atualizações** escolhe se a verificação é automática (ao abrir o app e
uma vez por dia) ou só manual. Quem usa uma versão estável não é avisado de pré-lançamentos
(alpha, beta, rc).

O app é assinado apenas localmente (*ad-hoc*). Em outro Mac, o macOS bloqueia a primeira
abertura: libere em **Ajustes do Sistema › Privacidade e Segurança › Abrir Mesmo Assim**.
Para distribuir sem esse aviso, é preciso assinar e notarizar com uma conta Apple Developer.

## Compilar

É preciso o Xcode 26 ou mais novo (ou as Command Line Tools com Swift 6.2+).

```sh
scripts/build-app.sh             # gera build/FirmDrop.app
scripts/build-app.sh --install   # e copia para /Applications
scripts/make-dmg.sh              # gera build/FirmDrop.dmg
```

Opção para os dois scripts: `--universal` gera um binário para Apple Silicon e Intel.

Para desenvolver no Xcode, abra o `Package.swift` (`xed .`) e rode o esquema **FirmDrop**.

## Publicar uma versão

O `scripts/release.sh` atualiza a versão no `Info.plist`, faz o commit `chore: release vX.Y.Z`,
envia o `main`, gera o `.dmg` universal e cria a Release no GitHub com as notas tiradas dos
commits desde a versão anterior. Requer o [GitHub CLI](https://cli.github.com) autenticado e o
`main` local igual ao `origin/main`.

```sh
DRY_RUN=1 scripts/release.sh 0.1.0-beta.1   # mostra as notas sem alterar nada
scripts/release.sh 0.1.0-beta.1             # pré-lançamento (alpha, beta ou rc)
scripts/release.sh 1.0.0                    # versão estável
```

A verificação de atualizações consulta a API pública do GitHub, então só funciona com o
repositório público.

## Uso

1. Digite o modelo, por exemplo `SM-A556E`. Ele aparece em Configurações › Sobre o
   telefone; sufixos como `/DS` podem ficar, o app remove.
2. Escolha a região e clique em **Buscar**.
3. Clique em **Baixar** na versão mais recente ou em qualquer versão anterior.

Os arquivos vão para `~/Downloads`; a pasta pode ser trocada em **FirmDrop › Ajustes** (⌘,).
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
e guarda em `~/Library/Caches/FirmDrop/`. Ele não é distribuído neste repositório.

Se a Samsung trocar o esquema de autenticação, as buscas passam a falhar com
"Autenticação recusada pelo servidor" (HTTP/status 401). Nesse caso, é preciso
atualizar `paramsURL`/`paramsSHA256` em `Sources/FirmDropCore/Authenticator.swift`
(e possivelmente o algoritmo) acompanhando o Bifrost.

## Estrutura

| Caminho | Conteúdo |
|---|---|
| `Sources/FirmDropCore/` | Protocolo FUS, autenticação, criptografia e motor de download (sem UI) |
| `Sources/FirmDrop/` | App SwiftUI: busca, lista de downloads, ajustes |
| `Tests/FirmDropCoreTests/` | Testes (`swift test`) |
| `Resources/` | `Info.plist` e ícone do app |
| `scripts/` | `build-app.sh` (monta o .app), `make-dmg.sh`, `release.sh` e `make-icon.sh` (gera o ícone) |

## Testes

```sh
swift test                  # testes offline
FIRMDROP_LIVE=1 swift test     # inclui testes contra o servidor real (baixa ~30 MB)
```

## Limitações

- O `version.xml` só lista versões anteriores que têm atualização OTA. Outras podem
  existir no servidor, mas o app não tem como descobri-las.
- Use para seus próprios aparelhos. Redistribuir os firmwares publicamente pode violar os
  termos de uso da Samsung.

## Licença

O FirmDrop é distribuído sob a [licença Apache 2.0](LICENSE). Os créditos e as licenças de terceiros estão em [NOTICE](NOTICE) e acompanham o app em `Contents/Resources/`.

## Créditos

A autenticação no servidor FUS é um porte do [Bifrost](https://github.com/zacharee/SamloaderKotlin), de Zachary Wander, sob a licença MIT (texto completo em [Resources/licenses/Bifrost-LICENSE.txt](Resources/licenses/Bifrost-LICENSE.txt)). O `auth_param.dat` usado na autenticação não é distribuído com o app: ele é baixado do repositório do Bifrost na primeira busca.
