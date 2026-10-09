# Política de Segurança

## Versões Suportadas

Apenas a versão mais recente publicada em
[Releases](https://github.com/julianamarques/firmdrop/releases) recebe
correções de segurança.

| Versão                 | Suportada |
| ---------------------- | --------- |
| Mais recente (1.0.x)   | Sim       |
| Anteriores             | Não       |

## Como Reportar uma Vulnerabilidade

Não abra uma issue pública para relatar vulnerabilidades.

Use o reporte privado do GitHub: na aba **Security** do repositório, clique em
**Report a vulnerability**. O relato fica visível apenas para a mantenedora até
que uma correção seja publicada.

Inclua, sempre que possível:

- Descrição do problema e do impacto.
- Passos para reproduzir ou uma prova de conceito.
- Versão do FirmDrop e do macOS.
- Modelo, região (CSC) e versão do firmware envolvidos, se for o caso.
- Sugestão de correção, se houver.

## O Que Esperar

- Confirmação do recebimento em até 7 dias.
- Avaliação inicial e retorno sobre a gravidade em até 14 dias.
- Correção publicada em uma nova versão, com crédito a quem reportou, se
  desejado.

Por ser um projeto mantido por uma pessoa, os prazos podem variar; o relato
será acompanhado até a conclusão.

## Escopo

Estão no escopo:

- O código do app: comunicação com os servidores da Samsung, assinatura dos
  pedidos, verificação do `auth_param.dat` embutido, download com retomada,
  verificação do CRC32, decifragem e gravação dos arquivos no disco.
- A verificação de atualizações e os links que ela abre.
- A integração de instalação USB, seleção e validação de pacotes, importação de
  ZIP e o adaptador do motor de instalação.
- Os scripts de build, empacotamento e publicação.

Fora do escopo (reporte diretamente aos projetos de origem):

- Vulnerabilidades nos servidores ou nos firmwares da Samsung:
  [Samsung Mobile Security](https://security.samsungmobile.com).
- Vulnerabilidades no `auth_param.dat` ou no Bifrost:
  [zacharee/SamloaderKotlin](https://github.com/zacharee/SamloaderKotlin).
- Problemas em outras ferramentas de instalação, como Odin e Heimdall. Para falhas
  no Brokkr, informe também o projeto de origem; problemas na integração do FirmDrop
  permanecem no escopo deste repositório.
- Ataques que exigem acesso físico ao Mac desbloqueado.
- O aviso do Gatekeeper na primeira abertura, causado pela assinatura local do
  app (comportamento conhecido e documentado no README).

## Considerações de Segurança para Usuários

- O app não tem contas, não coleta dados e não envia telemetria. Na rede, ele se
  comunica apenas, e sempre por HTTPS, com:
  - `fota-cloud-dn.ospserver.net`, `neofussvr.sslcs.cdngc.net` e
    `cloud-neofussvr.samsungmobile.com`, servidores da Samsung, para consultar
    versões e baixar os firmwares;
  - `api.github.com`, para verificar se há uma versão nova do app.
- O `auth_param.dat` vem embutido no app, baixado de um commit fixo do Bifrost no
  build. Ele só é usado se o SHA-256 conferir com o valor definido no código; caso
  contrário, a busca falha.
- O firmware é baixado direto dos servidores da Samsung e conferido com o CRC32
  informado por eles antes de ser decifrado. Os `.tar.md5` dentro do `.zip`
  trazem o MD5 da própria Samsung, que o motor de instalação confere antes de gravar.
- A instalação USB é experimental. O modelo informado e os nomes dos arquivos não
  comprovam compatibilidade com o hardware ou com a revisão de bootloader. O app
  exige revisão explícita antes de iniciar, usa uma única conexão USB e não envia PIT.
- O app não instala atualizações sozinho: ele apenas abre o link do `.dmg` da
  nova versão no navegador. Confira se o endereço é
  `github.com/julianamarques/firmdrop` antes de baixar.
- Baixe o app apenas pela página de Releases deste repositório.
