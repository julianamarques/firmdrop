# Como Contribuir?

Obrigado pelo interesse em contribuir com o FirmDrop. Este guia descreve o fluxo recomendado para propor correções, melhorias e ajustes de documentação.

## Fluxo de Trabalho

- Faça um fork do repositório e clone o projeto.
- Crie uma branch a partir da branch principal.
- Use nomes de branch objetivos, como `feature/nome-da-feature` ou
  `fix/descricao-do-ajuste`.
- Consulte o `README.md` para compilar, empacotar e rodar o app localmente.
- Mantenha pull requests pequenos e focados em uma mudança principal.
- Explique no pull request o problema resolvido, a solução aplicada e como a
  alteração foi validada.

## Commits

Escreva as mensagens em inglês, curtas, no imperativo e com um prefixo que
indique o tipo da mudança ([Conventional Commits](https://www.conventionalcommits.org/)):

```text
feat: show the Android version of previous firmware versions
fix: resume downloads after the server rotates the nonce
refactor: move the download state machine into FirmDropCore
test: cover the version.xml parser
docs: update installation instructions
build: pin a newer auth_param.dat
chore: release v1.1.0
```

## Padrões de Código

- Siga a organização existente: o que não depende de interface (protocolo do
  FUS, criptografia, download, verificação de atualizações) fica em
  `Sources/FirmDropCore`, com testes em `Tests/FirmDropCoreTests`; o app
  SwiftUI fica em `Sources/FirmDrop`.
- Não adicione comentários no código Swift: prefira nomes claros, funções
  pequenas e tipos explícitos. Os scripts podem ter comentários.
- O projeto usa o modo de linguagem Swift 6, com verificação estrita de
  concorrência. Não introduza avisos de compilação.
- Lógica nova em `FirmDropCore` deve vir com testes.
- Trate tudo o que vem dos servidores como não confiável: leia XML com
  `XMLDocument.untrusted`, valide modelos, regiões, versões, nomes de arquivo e
  caminhos com `Identifiers` e monte caminhos locais com
  `FirmwareDownload.localURLs`.
- Os textos exibidos ao usuário são escritos em português do Brasil no código e
  traduzidos para inglês em `Resources/Localizable.xcstrings`. Depois de
  adicionar ou alterar textos, rode `scripts/sync-strings.sh` e preencha a
  tradução; o `swift test` falha enquanto houver texto sem tradução ou com
  marcadores (`%@`, `%lld`) diferentes do original.
- Não inclua no controle de versão o `Resources/auth_param.dat` (baixado por
  `scripts/fetch-auth-params.sh`), firmwares baixados, credenciais ou dados
  pessoais.
- Ao atualizar o `auth_param.dat`, altere juntos o commit em
  `scripts/fetch-auth-params.sh` e o `paramsSHA256` em
  `Sources/FirmDropCore/Authenticator.swift`.

## Validação

Antes de abrir um pull request, rode as verificações aplicáveis:

```sh
scripts/fetch-auth-params.sh   # uma vez
swift build
swift test
FIRMDROP_LIVE=1 swift test     # quando a mudança afeta o protocolo ou o download
scripts/build-app.sh
```

Também revise se:

- A alteração está limitada ao escopo proposto.
- A compilação não gera avisos e todos os testes passam.
- Novas regras possuem testes quando aplicável.
- O app foi testado de verdade quando a mudança afeta busca, download, pausa e
  retomada ou decifragem.
- Os textos novos aparecem corretamente em português e em inglês.
- Nenhuma credencial, token ou dado pessoal foi versionado.
- A documentação foi atualizada quando a alteração muda o uso do projeto.

## Pull Requests

Ao abrir um pull request, inclua:

- Um resumo curto da alteração.
- O motivo da mudança.
- Os comandos executados para validação.
- Os modelos e regiões (CSC) usados nos testes manuais e a versão do macOS.
- Observações sobre impactos de compatibilidade, se existirem.

## Issues

Para reportar vulnerabilidades, não abra uma issue: siga a
[política de segurança](SECURITY.md).

Ao abrir uma issue, informe:

- Descrição clara do problema ou melhoria.
- Passos para reproduzir, quando for um bug.
- Comportamento esperado e comportamento atual.
- Versão do FirmDrop, versão do macOS e se o Mac é Apple Silicon ou Intel.
- Modelo, região (CSC) e versão do firmware envolvidos.
- A mensagem de erro exibida no app, que pode ser selecionada e copiada na
  lista de downloads.
- Em problemas com a verificação de atualizações, os logs, que podem ser
  obtidos com:

```sh
/usr/bin/log show --last 10m --predicate 'subsystem == "com.julianamarques.FirmDrop"' --info
```
