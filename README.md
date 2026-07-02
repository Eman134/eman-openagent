# eman-openagent

Adiciona um item **"Abrir agente"** ao menu de contexto do Windows Explorer.
Ao clicar com o botão direito em uma pasta (ou no espaço vazio dentro dela),
o script detecta quais agentes de IA de linha de comando estão instalados
(Claude Code, Codex, Copilot CLI, Gemini CLI, Aider, etc.), mostra uma lista
para escolher e abre o agente selecionado no **Windows Terminal**, já na
pasta clicada.

A detecção é feita em tempo real, a cada clique — não é um menu fixo
gerado uma única vez. Se você instalar um novo agente amanhã, ele já
aparece na lista sem precisar reconfigurar nada.

## Requisitos

- Windows 10/11
- PowerShell 5.1+ (já vem no Windows)
- [Windows Terminal](https://aka.ms/terminal) instalado (`wt.exe` no PATH)
- Pelo menos um agente de IA de linha de comando instalado e no PATH
  (ex.: `claude`, `codex`, `copilot`, `gemini`, `aider`, `cursor-agent`)

Não é necessário rodar como administrador — a instalação usa apenas
`HKEY_CURRENT_USER`, então afeta só o seu usuário do Windows.

## Instalação

```powershell
git clone https://github.com/Eman134/eman-openagent.git
cd eman-openagent
.\install.ps1
```

Se o PowerShell bloquear a execução de scripts, rode uma vez:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

Após instalar, se o item "Abrir agente" não aparecer de imediato no menu
de contexto, reinicie o Explorer (`taskkill /f /im explorer.exe && start explorer.exe`)
ou faça logoff/login.

## Uso

1. Clique com o botão direito em uma pasta, **ou** no espaço vazio dentro
   de uma pasta aberta no Explorer.
2. Clique em **"Abrir agente"**.
3. Escolha o agente na lista que aparecer (só aparecem os que estão
   instalados no seu PATH).
4. O Windows Terminal abre já na pasta escolhida, rodando o agente.

## Agentes suportados / como adicionar outros

A lista de agentes fica em:

```
%LOCALAPPDATA%\eman-openagent\agents.json
```

Esse arquivo é copiado automaticamente do repositório na primeira
instalação, e fica sob seu controle — editá-lo não afeta o repositório
nem é sobrescrito em uma reinstalação.

Cada entrada tem este formato:

```json
{
  "name": "Nome que aparece no menu",
  "checkCommand": "comando-usado-para-detectar-se-esta-instalado",
  "runCommand": "comando-que-sera-executado-no-terminal"
}
```

Padrão incluído:

| Nome                | Comando detectado |
|----------------------|-------------------|
| Claude Code          | `claude`          |
| OpenAI Codex CLI     | `codex`           |
| GitHub Copilot CLI   | `copilot`         |
| Gemini CLI           | `gemini`          |
| Aider                | `aider`           |
| Cursor Agent CLI     | `cursor-agent`    |

Para adicionar outro agente, inclua um novo objeto na lista, por exemplo:

```json
{
  "name": "Meu Agente Custom",
  "checkCommand": "meu-agente",
  "runCommand": "meu-agente --algum-flag"
}
```

Salve o arquivo e pronto — na próxima vez que abrir "Abrir agente", ele
já é detectado (se `checkCommand` estiver no PATH).

## Desinstalação

```powershell
cd eman-openagent
.\uninstall.ps1
```

Isso remove as entradas do menu de contexto. O arquivo de configuração em
`%LOCALAPPDATA%\eman-openagent\agents.json` é mantido (apague manualmente
se quiser removê-lo também).

## Como funciona por baixo dos panos

- `install.ps1` cria duas chaves em `HKCU:\Software\Classes`:
  - `Directory\shell\OpenAgent` — clique direito em cima de uma pasta.
  - `Directory\Background\shell\OpenAgent` — clique direito no espaço
    vazio dentro de uma pasta.
- Cada chave chama `scripts\Invoke-OpenAgent.ps1` passando o caminho da
  pasta clicada (`%1` ou `%V`, conforme o caso).
- O script lê `agents.json`, testa com `Get-Command` quais estão
  disponíveis no PATH, mostra um formulário simples (Windows Forms) para
  escolha e chama `wt.exe -d "<pasta>" powershell -NoExit -Command "<comando>"`.

## Troubleshooting

- **O item não aparece no menu**: reinicie o Explorer ou faça
  logoff/login. Alguns caches de menu de contexto do Windows demoram
  para atualizar.
- **"Nenhum agente encontrado"**: confirme que o agente está instalado e
  disponível em uma nova janela de terminal rodando `where <comando>`.
- **Erro de política de execução**: rode
  `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` uma vez no
  PowerShell.

## Licença

MIT — veja [LICENSE](LICENSE).
