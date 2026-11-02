# Pinguin LA: n8n local e alertas diários

## O que já está preparado

- `compose.yaml`: servidor n8n local, versão 2.45.4, com dados persistentes e reinício automático.
- `iniciar.sh`: gera uma chave de criptografia local e inicia o servidor.
- `alertas.sql`: consulta somente dívidas com saldo positivo e vencimento até hoje, do proprietário configurado.
- `resumo-diario.n8n.json`: workflow importável para enviar um resumo diário PARA VOCÊ por e-mail, às 9h de São Paulo. Não envia para amigos/devedores.

Faltam suas configurações de Supabase e SMTP. O fluxo não está ativado e não foi executado contra suas contas. Não altera saldos. Não usa IA e não precisa de webhook público.

## 1. O que fica ligado

Pode fechar o Pinguin LA e o navegador: o n8n consulta o Supabase direto, de forma independente.

Mas o computador que executa o n8n deve continuar ligado, sem suspender, com Docker e internet. `restart: unless-stopped` reinicia o container com o Docker, não liga um computador desligado. Configure o serviço Docker para iniciar com o Ubuntu e ajuste suspensão automática na interface de energia do sistema.

Se quiser desligar seu computador, use outro computador sempre ligado, mini PC, VPS ou n8n Cloud. Nenhuma instalação local entrega alertas enquanto o servidor estiver desligado. A recepção por e-mail também depende das notificações do seu aplicativo de e-mail.

## 2. Instalar no seu Ubuntu

Extraia o ZIP atualizado. No terminal, entre na pasta `pinguin-la/n8n-local` que foi extraída. Exemplo, se extraiu em Downloads:

```bash
cd ~/Downloads/pinguin-la/n8n-local
docker --version
docker compose version
```

Se os dois comandos funcionarem:

```bash
bash iniciar.sh
docker compose ps
```

Abra http://localhost:5678 e crie seu usuário administrativo do n8n. Isso é um acesso separado do login do Pinguin LA.

Se Docker não existir, siga a instalação oficial para Ubuntu e depois instale o plugin Compose conforme a mesma documentação: https://docs.docker.com/engine/install/ubuntu/ . O grupo docker dá poderes administrativos; só adicione usuários confiáveis. Este pacote não instala Docker nem modifica seu sistema automaticamente.

A porta foi limitada a `127.0.0.1`: apenas seu próprio computador acessa o editor. Não exponha a porta 5678 diretamente na internet. Não há necessidade de abrir o roteador nem usar ngrok para o resumo diário.

Se o navegador reclamar de cookies seguros, use `localhost` em vez de IP da rede. Para acesso remoto permanente, configure HTTPS e autenticação num domínio; não desative proteções para publicar o editor.

## 3. Preparar o Supabase

1. O Pinguin LA precisa estar conectado ao seu Supabase e você deve ter cadastrado as dívidas reais nele. Dados de demonstração/localStorage não são visíveis para o servidor n8n.
2. Execute o `schema.sql` do app se ainda não configurou o banco.
3. No SQL Editor, execute `n8n-local/alertas.sql`.
4. Em Authentication > Users, copie o UUID da SUA conta que é dona das dívidas. Não é o UUID de um devedor.
5. Separe a URL do projeto e a chave legada `service_role` para configurar localmente uma credencial no n8n. Não é a chave anon do frontend. A service_role tem poderes amplos: ela só vai no cofre de credenciais do seu servidor n8n. Nunca coloque essa chave na configuração pública do Pinguin LA, nos nós Set/Code, em mensagens ou em arquivos compartilhados.

O SQL disponibiliza a função somente para o papel `service_role`. Ela exige o proprietário explicitamente e retorna apenas saldo, data, nome e status das pendências. Para operação maior/multiusuário, prefira substituir a chave ampla por um backend com credencial de escopo restrito.

## 4. Importar o workflow

No n8n, crie um workflow e use a opção de importar de arquivo. Selecione `resumo-diario.n8n.json`.

Abra o nó **Configurar** e substitua:

| Campo | Conteúdo |
|---|---|
| supabaseUrl | Sua URL, como `https://seuprojeto.supabase.co`, sem barra no final |
| ownerId | UUID da sua conta em Authentication > Users |
| fuso | `America/Sao_Paulo`; para Ladário/Corumbá, use `America/Campo_Grande` |
| emailRemetente | Endereço autorizado pela sua conta SMTP |
| emailDestino | Seu e-mail que receberá o resumo |

### Credencial do Supabase

No nó **Buscar hoje e atrasados**, selecione Authentication > Generic Credential Type > Custom Auth e crie a credencial. O conteúdo tem esta estrutura, substituindo os textos APENAS no editor de credenciais local:

```json
{
  "headers": {
    "apikey": "SUA_SERVICE_ROLE",
    "Authorization": "Bearer SUA_SERVICE_ROLE"
  }
}
```

Não coloque os caracteres `SUA_SERVICE_ROLE` literalmente: substitua pela chave. Não exponha os valores em capturas ou exports.

### Credencial de e-mail

No nó **Enviar resumo para mim**, crie/selecione a credencial SMTP do seu provedor. Preencha host, porta, usuário e senha/token de aplicativo de acordo com a documentação dele. Use TLS conforme o provedor: normalmente porta 465 com TLS direto ou 587 com STARTTLS. Não use a senha normal quando o provedor exigir senha de aplicativo.

O remetente precisa ser permitido pelo serviço SMTP. O destinatário é o seu próprio e-mail. Se não quiser e-mail, substitua esse nó por outro canal de aviso para você, configurando a conta correspondente.

## 5. Testar e publicar

1. Cadastre no Pinguin LA uma dívida com vencimento hoje, uma de ontem e uma de amanhã. Use registros de teste no seu próprio banco, sem contatos de terceiros.
2. Execute **Testar manualmente**. Somente hoje e ontem devem entrar no e-mail. Amanhã deve ficar fora.
3. Quite um dos registros de teste. Execute de novo: esse registro não deve aparecer mais.
4. Quite tudo que vence até hoje e teste: nenhum e-mail deve ser enviado quando não houver pendências.
5. Confirme o horário no nó **Diariamente às 9h**: cron `0 9 * * *`.
6. Configure o fuso nas configurações do workflow. Se escolheu Campo Grande no nó Configurar, ajuste o fuso do workflow e `TZ`/`GENERIC_TIMEZONE` em compose.yaml para o mesmo valor e reinicie com `docker compose up -d`.
7. Salve e publique/ative o workflow (nome varia por versão). Só importar ou salvar não agenda a execução.
8. Feche o app e o navegador. Deixe o computador ligado e confira a próxima execução no histórico do n8n e no seu e-mail.

Execuções manuais de teste podem gerar e-mails adicionais para você. O workflow de resumo não possui trava persistente de envio único por dia; seu agendamento roda uma vez por dia, mas não o dispare manualmente repetidas vezes se não quiser vários resumos. Para mensagens a terceiros, implemente a fila e a deduplicação descritas abaixo antes de usar em produção.

Se uma execução for perdida porque o computador estava desligado, não assuma recuperação automática: confira as opções de execução perdida disponíveis na sua versão e o histórico. Na próxima execução, os ainda não pagos continuarão aparecendo como atrasados.

## 6. Regra para repetir diariamente só enquanto estiver devendo

A consulta usada pelo fluxo é equivalente a:

```sql
where user_id = proprietario
  and principal + interest > 0
  and due <= data_local_atual
```

- Vence hoje e tem saldo: entra hoje.
- Amanhã ainda tem saldo e venceu ontem: entra como atrasado.
- Vencimento futuro: não entra.
- Quitado: não entra.
- Pagou só juros e o principal ainda venceu: continua com o principal em aberto. Se houve um novo acordo, atualize o vencimento antes de gerar novos lembretes.
- Mudou o vencimento para o futuro: sai da seleção até essa data.

O resumo usa o saldo registrado no Supabase. Se o amigo pagar fora do sistema e você não der baixa nem tiver integração de Pix, a dívida continuará pendente. A IA não consegue adivinhar que o dinheiro entrou.

## 7. Cobrar o amigo automaticamente: próxima etapa separada

A política atual do WhatsApp Business lista cobrança de dívidas e empréstimos P2P como atividades proibidas. Por isso este pacote não conecta um robô de cobrança dessas dívidas no WhatsApp nem usa WhatsApp Web como contorno. Fonte oficial: https://business.whatsapp.com/policy . Para esse caso, escolha um canal/provedor que aceite a atividade real; um canal de e-mail também deve ter sua operação e suas regras de contato confirmadas.

O resumo para você já resolve saber quem cobrar com o app fechado. O envio a cada amigo exige um segundo workflow e um cadastro de destinatários verificados. Não transforme o resumo privado em um disparo para a lista de devedores: cada pessoa só pode receber seus próprios dados.

Estrutura proposta para o segundo fluxo:

1. Agendamento diário às 9h, no mesmo fuso.
2. Selecionar somente dívidas de hoje/atrasadas, com saldo positivo e lembretes permitidos.
3. Agrupar por pessoa para produzir no máximo UM lembrete diário por contato (mesmo se houver várias dívidas).
4. Reservar um job no banco com chave única `(proprietario, pessoa, dia_local, canal)`. A reserva deve ser atômica: se já existe, não enviar outra mensagem.
5. Reconsultar o saldo, a data, a situação do Pix e a preferência de contato imediatamente antes de enviar. Se quitou, foi renegociado para o futuro, pausado ou contestado, cancelar o job.
6. Enviar pelo canal permitido e registrar ID do envio, horário, tentativa e resultado. Se houver timeout com resultado incerto, consultar o provedor ou pedir revisão antes de reenviar; não prometer entrega exatamente uma vez se o canal não oferecer idempotência.
7. No dia seguinte, criar um job novo somente se continuar pendente. Respeitar suspensão de contato, contestação e atendimento humano; não insistir após pedido para parar.

Comece com texto fixo, sem IA: nome, saldo atualizado, vencimento e link/Pix válido. Uma rotina determinística é suficiente para lembrar diariamente. A IA pode ser adicionada depois para interpretar respostas, nunca para decidir quitação ou inventar valores.

## 8. Fazer parar automaticamente quando pagar

O segundo bloco é a integração financeira:

- Criar Pix dinâmico com ID vinculado à dívida e à divisão principal/juros.
- PSP confirma → endpoint HTTPS verifica a cobrança na API → transação idempotente no Supabase registra o pagamento e atualiza o saldo.
- No próximo envio, a seleção já exclui o quitado. Remova também os jobs ainda não enviados. Uma mensagem já entregue não pode ser desfeita por essa lógica.
- Se um webhook falhar, uma rotina de conciliação consulta cobranças pendentes no PSP e reaplica a mesma função idempotente.

Um comprovante recebido por mensagem fica anexado como evidência pendente. Só a confirmação financeira verificada autoriza baixa automática. Veja também `../GUIA-AUTOMACAO.md`.

Para receber webhooks de pagamento, o PSP precisa alcançar um endpoint público HTTPS. A instalação local deste pacote só faz conexões de saída; ela não recebe webhooks externos. Uma boa opção é deixar a recepção/validação do Pix numa Supabase Edge Function pública com autenticação/verificação adequada, e usar o n8n local para agendar e avisar. Não publique o editor do n8n para resolver isso.

## 9. Operação local

```bash
# Ver estado
docker compose ps
# Ver logs recentes
docker compose logs --tail=80 n8n
# Parar sem apagar dados
docker compose stop
# Iniciar de novo
docker compose up -d
```

Guarde backup da pasta e do volume `n8n_data`, junto com a `.env` gerada. A chave criptografa as credenciais. Não use `docker compose down -v`, que apaga o volume. Proteja também os backups, que contêm dados e credenciais.

Este pacote foi validado por sintaxe e estrutura; não foi iniciado aqui porque Docker não está disponível neste ambiente. A compatibilidade dos nós importados e a entrega devem ser verificadas no seu n8n com suas credenciais antes da ativação.

Documentação:
- https://docs.n8n.io/hosting/installation/docker/
- https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-base.scheduletrigger/
- https://docs.docker.com/engine/install/ubuntu/
