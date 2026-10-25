# Changelog (Portuguese)

What's New in Portuguese: each version's changes, shorter than CHANGELOG.md. Headings stay in English; the app translates them. A version missing here shows in English.

## 1.0.0

### Added

- Cazaque, usbeque e turco na app e nos widgets: treze idiomas. O usbeque usa Ö, Ğ, Ş e Ç.
- Configuração inicial opcional com escolha de fornecedores. Pode ignorá-la ou reabri-la nas Definições. As instalações existentes mantêm as escolhas; a primeira leitura começa após concluir ou ignorar.
- Limiares por fornecedor, alertas de reinício independentes e horas de silêncio no fuso do Mac. Os alertas ignorados não se acumulam; dados antigos não geram avisos.
- CLI opcional: usagenow status e usagenow status --json leem a captura segura com a sua atualidade. Sem pedidos aos fornecedores, autenticação ou exportação do histórico. Instale em Definições › Geral.
- Atualização ao acordar e verificações da migração de alertas e compatibilidade de capturas. A CLI remove percentagens após reinícios e rejeita formatos incompatíveis.

## 0.9.0

### Added

- **JetBrains AI (experimental).** Limites locais do AI Assistant no seu IDE JetBrains, com a data de reposição informada, na barra de menus e nos widgets. Dados antigos mantêm o horário original. Sem acesso a credenciais ou pedidos de rede. A validação com o AI Assistant ativo ainda está pendente.
- **Widgets pessoais.** Escolha fornecedores e contas para cada widget ou deixe a seleção vazia para seguir o UsageNow. Renomear mantém a escolha; uma conta removida nunca é substituída silenciosamente.
- **Widget grande.** Até quatro linhas detalhadas de fornecedores e contas, com dois períodos de quota e as reposições. Continua a mostrar apenas o snapshot filtrado.
- **Ritmo de consumo.** Gráfico local e estimativa identificada para o período mais crítico, com pelo menos três leituras recentes ao longo de 15 minutos. Repetições em cache, dados antigos, pausas longas, reposições e períodos desconhecidos não geram previsões. Não usa tokens.
- **Incidentes opcionais.** Páginas públicas de OpenAI, Claude, Cursor e GitHub Copilot, desativadas por predefinição e com cache de dez minutos. Estado separado da ligação e dos limites; não envia dados da conta ou de utilização.
- **Neerlandês (Nederlands).** App, widgets e novidades integradas: agora dez idiomas.
- **Ícones Windsurf e ElevenLabs renovados.** Logótipos corretos para os modos claro e escuro.

- **Antigravity sem IDE.** Se o IDE não responder, UsageNow lê o relatório oficial `agy /usage` das versões compatíveis do CLI 1.x a partir da 1.1.11. Sem iniciar uma interação do agente nem aceder a credenciais; cache de cinco minutos. Verificado com CLI 1.2.2.

## 0.8.0

### Added

- Chaves, tokens e cookies são verificados com uma consulta de uso somente de leitura antes de salvar. Mensagens claras sobre credenciais, permissões, rede e Chaves; cancelar mantém a conexão anterior.
- Em caso de HTTP 429, a conexão aguarda até o horário permitido pelo serviço, inclusive na atualização manual. Outras contas continuam funcionando e os dados anteriores mantêm a data original.
- Cursor, GitHub Copilot, Perplexity, ElevenLabs e Z.ai: conexão explícita nos Ajustes, desativada por padrão. Cursor e Perplexity oferecem uma janela temporária de login ou cookies manuais; Copilot usa seu token do GitHub. ElevenLabs usa a API oficial; as outras quatro integrações são experimentais. Ainda não verificadas com contas reais.
- Créditos e caracteres da conta aparecem separados da atividade de hoje. Cotas ilimitadas ou desconhecidas não viram porcentagens inventadas.
- Windsurf: limites diários e semanais, horários de redefinição e plano do cache local; créditos por ciclo de cobrança em planos antigos. Sem ler credenciais ou fazer solicitações de rede. Ainda não verificado com uma instalação atual conectada.
- Português, japonês, coreano e hebraico: agora nove idiomas. O widget aceita leitura da direita para a esquerda.
- As novidades estão traduzidas em todos os idiomas do app e funcionam offline.
- Escolha uma conta adicionada para a barra de menus, como “Codex · Trabalho”. Ao removê-la, a conta principal do provedor volta a ser exibida.

### Fixed

- O widget guarda a data dos dados de cada provedor. Atualizar o Codex não faz os limites antigos do Claude parecerem recentes; um relógio indica dados desatualizados.
- Após a redefinição, a porcentagem anterior fica desconhecida até chegarem novos dados. A contagem regressiva continua entre atualizações do widget.
- Uma nova leitura salva sua data mesmo quando a porcentagem não muda.

### Development

- Builds Debug usam identificadores e contêiner de dados próprios, sem interferir no widget instalado. As atualizações automáticas estão desativadas; os testes não iniciam provedores reais.

## 0.7.2

### Fixed

- Privacidade e Sobre não abriam em russo, francês e espanhol: os títulos das abas não cabiam na janela de Ajustes. Agora ela se alarga para caber todos.

## 0.7.1

### Added

- Escolha o idioma do UsageNow em Ajustes › Geral › Idioma: o do macOS, ou alemão, inglês, espanhol, francês ou russo. O widget acompanha.
- Renomeie uma conta adicionada pelo menu … dela em Ajustes › Provedores.

### Changed

- As ações de uma conta adicionada ficam num só menu, para que a linha caiba em qualquer idioma.
- Uma pasta de conta vazia ou ausente avisa isso, em vez de pedir que você inicie sessão.

### Fixed

- Adicionar uma conta fazia as outras contas adicionadas lerem de novo as sessões do mês.

## 0.7.0

### Added

- Mais de uma conta: uma segunda pasta do Codex ou do Claude Code, ou outra chave de API do DeepSeek, Kimi, OpenRouter ou Ollama Cloud, cada uma com sua própria seção — “Codex · Trabalho” — com o nome que você escolher. O UsageNow nunca lê o nome nem o e‑mail da conta.
- Qwen Code — os tokens, as solicitações e os modelos de hoje, e quanto teriam custado, a partir das gravações de sessão que o Qwen Code grava no seu Mac.
- Cline — os tokens, as solicitações de API e os modelos de hoje, com o custo que o Cline registrou, a partir das tarefas do Cline no seu editor e do Cline CLI. Prompts, respostas e chaves nunca são lidos.
- Grok Build — os tokens, as chamadas ao modelo e os modelos de hoje, com o custo informado pela xAI, a partir dos registros de sessão do Grok Build.
- As últimas duas semanas no widget, para provedores sem limites: o formato da sua atividade, nunca valores.
- UsageNow em alemão, espanhol, francês e russo, de acordo com o idioma do seu Mac.
- Novidades em Ajustes › Sobre: as mudanças de cada versão, dentro do app.

### Changed

- No Cline e no Grok Build, o custo mostrado é o que a própria ferramenta registrou, não uma estimativa.

## 0.6.1

### Added

- Notificações de limites: quando resta 20% de um limite e de novo 5%, uma vez cada, e quando um limite sobre o qual você foi avisado é redefinido. Desativadas por padrão; ative-as em Ajustes › Notificações.
- Um atalho de teclado próprio para abrir o UsageNow de qualquer app. Grave-o em Ajustes › Barra de Menus. Não precisa de permissões extras.

### Changed

- A estimativa de custo conhece o Claude Sonnet 5.5 e o GPT-6.1.

### Fixed

- “Tentar Novamente”, uma chave de API recém-adicionada ou um provedor recém-ativado podiam ser ignorados se acionados durante uma atualização.
- O Antigravity não atrasa mais os outros provedores enquanto o UsageNow procura o servidor de linguagem dele.
- Uma linha muito longa num arquivo de sessão é pulada sem ser carregada na memória.

## 0.6.0

### Added

- Os últimos 30 dias abaixo de cada provedor: uma barra por dia, o total de tokens do mês, o custo estimado e o modelo mais usado. Passe o cursor sobre uma barra para ver o dia. Desative os gráficos em Ajustes › Geral.
- OpenCode — os tokens, as solicitações e os modelos de hoje e o custo deles, a partir do banco de dados local do OpenCode, só para leitura. Prompts e respostas nunca são lidos.
- Qoder — os créditos gastos hoje e as respostas que eles pagaram, a partir das transcrições que o Qoder grava no seu Mac. O login do Qoder nunca é aberto.
- Ollama Cloud (experimental) — limites por sessão e semanais, com a sua chave da Cloud API.
- Limites como restante ou usado — na janela, na barra de menus e no widget.
- Créditos no widget para Kiro, Warp e Qoder.
- Relatar um Problema em Ajustes › Sobre: primeiro o relatório inteiro, depois você mesmo o envia como issue no GitHub ou por e‑mail. Nenhum nome, caminho, chave ou prompt.

### Changed

- A janela da barra de menus é menos transparente e rola, em vez de passar da borda de uma tela pequena.
- Ajustes › Provedores cabe na tela de um notebook.
- A estimativa de custo conhece os modelos mais recentes, incluindo o Claude Opus 5.5 e o GPT-6.
- Ler os arquivos de sessão do mês ficou várias vezes mais rápido e usa muito menos memória.

### Fixed

- Os limites do Codex pararam de atualizar a partir do ChatGPT 26.9, que mudou o Codex CLI embutido de lugar.
- Limites desatualizados do Claude agora dizem como atualizá-los, para que uma porcentagem de uma hora atrás não pareça atual.
- O widget lê os dados de uma versão mais nova do app, em vez de pedir que você abra o UsageNow.
- O UsageNow podia fechar sem aviso se o Codex app-server terminasse cedo demais.

## 0.5.0

### Added

- Kiro — o limite mensal de créditos do plano, a data de redefinição e os créditos e prompts de hoje, a partir do que o Kiro grava no seu Mac. Nenhuma solicitação ao Kiro e nenhuma credencial do Kiro.
- Warp — as solicitações do agente, os créditos e os tokens por modelo de hoje, a partir do banco de dados local do Warp, só para leitura.
- DeepSeek, Kimi e OpenRouter — saldos e gastos das APIs oficiais deles, com a sua chave de API. A chave fica nas Chaves e só é enviada a esse provedor. Nenhum dos três foi verificado ainda numa conta real.

## 0.4.0

### Added

- Quanto os tokens de hoje teriam custado: uma estimativa ao lado dos totais de cada provedor pelos preços publicados da API, com tokens em cache pelo preço de cache. Uma referência, não uma conta: sua assinatura não cobra por token.
- Atualizações dentro do app. O UsageNow verifica e instala atualizações sozinho, e só as assinadas por ele. A verificação não diz nada sobre você. Vindo da 0.3.0, instale a 0.4.0 manualmente uma vez.

### Changed

- Atualizar desenha um arco de progresso em volta da seta, em vez de girar o ícone.
- A porcentagem na barra de menus tem o tamanho ajustado aos ícones vizinhos.

## 0.3.0

### Added

- Antigravity — os limites de 5 horas e semanais de cada grupo de modelos e o seu plano, a partir do app Antigravity enquanto ele está aberto. Sem credenciais e sem ir além de 127.0.0.1.
- Gemini CLI — tokens, solicitações e modelos a partir das gravações locais de sessão. Ele não informa limites, então eles não são mostrados.
- Atividade por modelo: a lista Modelos hoje para Codex, Claude Code e Gemini CLI, os mais ativos primeiro.
- Planos Team: o Claude mostra o assento, por exemplo Team · Premium; o Codex mostra Team, Business e Enterprise.
- Modos da barra de menus para Antigravity e Gemini CLI.
- Os provedores podem ser ordenados arrastando nos ajustes; a janela e o widget seguem essa ordem.
- Cursor e GitHub Copilot aparecem como “em breve”.

### Changed

- Com três ou mais provedores, o widget médio mostra uma linha para cada um, e o pequeno até três, os mais próximos do limite.
- Um provedor adicionado numa atualização se ativa sozinho uma vez. Os que você desativou continuam desativados.

### Fixed

- Os limites do Claude não pedem mais a senha de login e voltam sozinhos depois que o Claude Code é aberto.
- A janela de limite do Claude que foi redefinida enquanto você estava fora continua visível, e limites esgotados aparecem sem nenhum login.
- Os últimos limites conhecidos do Claude sobrevivem ao fechar o app e ao atualizá-lo.

## 0.2.0

### Added

- Dados reais: limites do Codex, horários de redefinição e plano a partir do Codex app-server oficial; tokens, solicitações e o último modelo do Codex e do Claude Code a partir dos arquivos de sessão locais.
- Widgets na mesa, pequeno e médio.
- Limites do Claude Code — experimentais e desativados por padrão.
- Codex e Claude Code podem ser ativados e desativados separadamente.
- Modos da barra de menus: só o ícone, o limite mais crítico ou um provedor.
- Aparência clara, escura ou do sistema.

### Changed

- O uso aparece como o que resta — “58% restante” — e as barras encurtam conforme você usa.
- As janelas de limite aparecem exatamente como o provedor as informa; o que falta nunca é inventado.
- Se os limites não puderem ser lidos, os últimos valores conhecidos ficam por um dia, marcados como desatualizados e com o motivo numa linha.

## 0.1.0

### Added

- O app nativo da barra de menus, seus ajustes e estados — com dados de exemplo.
