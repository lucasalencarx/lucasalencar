# Lucas Alencar — painel pessoal

## Menus e funções

- **Visão geral:** suas contas a pagar, pendências de hoje/atrasadas e próximos compromissos. O total de empréstimos a receber aparece separado.
- **Contas a pagar:** pessoa/empresa, descrição, categoria, valor, vencimento e observações. Registro integral ou parcial de pagamentos com histórico. O sistema não executa pagamento bancário.
- **Compromissos:** título, local, data/hora, notas, conclusão e antecedência de alerta (na hora, 15 min, 30 min, 1h ou 1 dia).
- **Empréstimos pessoais:** módulo anterior preservado, com principal/juros, pagamentos, anexos e integração Mercado Pago preparada. Seus registros antigos não são convertidos em contas a pagar.
- **Energia:** área reservada para medição futura. Não mostra números de consumo inventados. Inclui calculadora por potência × horas × dias e tarifa configurável.
- **Automação residencial:** cadastro de cômodos/dispositivos e botões de demonstração. Nenhum equipamento físico é acionado. Há Sala, Cozinha, Quarto principal, Quarto das crianças, Banheiro, Área de serviço, Varanda e Garagem; você pode escrever outros cômodos no cadastro.

O nome visual foi alterado para Lucas Alencar, mantendo o endereço atual para não quebrar seus links. Claro/escuro continuam disponíveis.

## Acesso inicial

**Somente para demonstração local:** usuário `lucas`, senha `Lucas@2026`. Também existe o botão Explorar demonstração sem conta. Essa senha é pública, está no código e NÃO protege dados reais. Os registros de demonstração ficam no armazenamento deste navegador; não são backup e não chegam ao n8n.

**Para dados reais:** conecte o Supabase pela tela inicial. Entre com e-mail/senha de uma conta Supabase Auth. A autorização de leitura/escrita vem de Auth e RLS no banco, não da senha da demonstração. Você define a senha real na criação da sua conta; não há usuário administrativo fixo no backend. Crie somente a conta que deseja usar e, em projeto estritamente pessoal, desative novos cadastros públicos no Supabase após a configuração, se não precisar deles.

Não reenvie senhas ou tokens por conversa. O usuário `lucas` de demonstração nunca autentica no Supabase nem consegue acessar o banco por si só.

## Preparar o banco

1. Execute `schema.sql` da raiz se o projeto Supabase ainda não tiver o módulo original.
2. Execute `pessoal/migration.sql`. É um complemento para contas, agenda, dispositivos, preferências e alertas.
3. Se já ativou Mercado Pago, preserve sua migração e as funções existentes. A migração pessoal não altera esses registros.
4. Abra o painel > conectar Supabase > informe URL e chave pública anon/publishable > crie/entre na sua conta.
5. Cadastre uma conta e um compromisso de teste. Reabra em outro navegador com a mesma conta para conferir a persistência.
6. Confira isolamento com outra conta de teste antes de guardar dados reais. SQL e entrega Telegram não foram executados no seu projeto sem suas credenciais.

## Telegram: custo e comportamento

A plataforma de bots do Telegram é gratuita para usuários e desenvolvedores, com limites de frequência. Os alertas pessoais desta proposta não exigem Telegram Premium nem broadcasts pagos. n8n Cloud, VPS, eletricidade ou outros serviços de hospedagem podem ter custos; rodar n8n Community localmente usa seu computador e internet.

Fontes: https://core.telegram.org/bots e https://core.telegram.org/bots/faq .

O bot envia os alertas PARA VOCÊ, no seu chat privado. Não envia cobranças para os amigos/devedores. Não há envio por e-mail nesse workflow.

## Configurar bot e Chat ID

1. No Telegram, abra o bot oficial **@BotFather**.
2. Envie `/newbot`, escolha nome (por exemplo Lucas Alencar) e username terminado em `bot`.
3. Guarde o token retornado diretamente no gerenciador de credenciais do seu n8n. Nunca no frontend, no arquivo JSON exportado ou no Git.
4. Abra o bot criado e toque em Iniciar ou envie `/start`. Um bot não pode iniciar a conversa com você antes disso.
5. Para obter seu Chat ID sem expor o token numa URL do navegador, execute localmente:

```bash
cd CAMINHO_DO_PROJETO/pessoal
python3 telegram-chat-id.py
```

O script pede o token com entrada oculta e imprime somente o ID e o primeiro nome dos chats privados que falaram com esse bot. Escolha o SEU chat. Não configure chat de grupo, pois o resumo contém seus dados pessoais. Use um bot novo sem webhook para essa consulta. Se já possui webhook, preserve-o e obtenha o chat_id pela integração existente, sem desativar outros fluxos.

Fonte n8n: https://docs.n8n.io/integrations/builtin/credentials/telegram/ .

## Instalar n8n e importar

Se ainda não tem n8n, use `n8n-local/compose.yaml` e execute `bash iniciar.sh` naquela pasta. O guia local anterior explica Docker, persistência e acesso em http://localhost:5678. Ele também contém um workflow antigo de e-mail, que é opcional e NÃO é usado nesta configuração. Não ative esse fluxo se não quer e-mails.

No n8n, importe **`pessoal/telegram.n8n.json`**. Ele vem desativado e sem credenciais. Preencha o nó Configurar:

| Campo | Valor |
|---|---|
| supabaseUrl | URL do projeto, sem barra final |
| ownerId | Seu UUID em Supabase > Authentication > Users |
| fuso | `America/Sao_Paulo`; se usar horário de Corumbá/Ladário, `America/Campo_Grande` |
| chatId | ID do SEU chat privado com o bot |

Configure o mesmo fuso nas configurações do workflow. O datetime de compromissos usa o fuso do dispositivo ao preencher e é salvo em UTC; confira o horário exibido antes de ativar o alerta.

### Credencial Supabase no n8n

Nos nós **Reservar alertas**, **Revalidar pendências** e **Confirmar envio**, selecione Generic Credential Type > Custom Auth e use a MESMA credencial:

```json
{
  "headers": {
    "apikey": "SUA_SERVICE_ROLE",
    "Authorization": "Bearer SUA_SERVICE_ROLE"
  }
}
```

Substitua os valores apenas na interface de credenciais do n8n. Essa chave tem poderes amplos no seu projeto: não é a chave pública do app e não pode ficar no navegador. As RPCs de alertas só aceitam o papel de servidor. Para operação multiusuário/maior, prefira um backend com credenciais de escopo restrito.

### Credencial Telegram

No nó **Enviar para meu Telegram**, crie a credencial Telegram e coloque o token do BotFather no campo Access Token. Não acrescente o token ao nó Configurar. O Chat ID não substitui o token: ambos são necessários.

O workflow usa o nó Telegram oficial para enviar uma mensagem privada com até 6 lembretes por execução. Os campos de texto são escapados para não virarem HTML arbitrário.

## Quando os avisos chegam

- Workflow executa a cada minuto no n8n.
- **Contas:** a partir das 9h, vencendo hoje ou atrasadas e com saldo positivo. Uma reserva por conta por dia impede criar novo alerta em toda execução. Enquanto ainda devendo, pode aparecer de novo no dia seguinte. Vencimentos futuros e contas quitadas não entram.
- **Compromissos:** alerta quando chegar o horário configurado pela antecedência. Uma reserva por compromisso + data/hora + antecedência. A rotina aceita recuperação de compromisso que começou há até 1 hora; passado isso não envia retrospectivamente. Marcar como concluído impede alertas futuros. Alterar hora/antecedência cria uma nova ocorrência de lembrete.
- Antes de enviar, o fluxo revalida contas já pagas/adiadas e compromissos concluídos/reagendados. Alterações após essa última consulta podem acontecer durante o envio; uma mensagem já entregue não pode ser retirada pelo banco.
- O site pode ficar fechado. O computador/servidor do n8n precisa continuar ligado, com internet, sem suspender. Para desligar seu PC, hospede n8n numa máquina sempre disponível ou use outra infraestrutura de agendamento.

## Testar e ativar

1. Configure e teste a credencial Telegram com uma mensagem inofensiva para o SEU chat no n8n.
2. Cadastre uma conta com vencimento hoje e um compromisso alguns minutos à frente, com alerta na hora.
3. Depois das 9h no fuso escolhido, rode Teste manual para conferir o lembrete da conta. Para compromisso, execute quando alcançar a janela.
4. Rode de novo: o mesmo item não deve ser reservado outra vez. Quite a conta e confira que não aparece nos próximos dias. Conclua/reagende o compromisso e confira a revalidação.
5. Confira os destinatários, o fuso e os horários. Salve e publique/ative o workflow para agendamento automático.
6. Feche o site e acompanhe o histórico de execução e a mensagem no Telegram.

## Falhas e alertas reservados

O banco reserva o alerta ANTES do envio e só muda para `sent` depois do retorno do Telegram e da confirmação final. Se houver erro, alguns registros podem ficar `claimed` e NÃO serão reenviados automaticamente. Isso evita disparos repetidos quando o Telegram recebeu a mensagem mas o retorno se perdeu.

Monitore erros no n8n e registros `personal_alert_jobs` com status `claimed`. Confira o histórico e o Telegram antes de decidir por uma retentativa administrativa. Não apague a reserva e reexecute às cegas. Esse fluxo não promete entrega exatamente uma vez entre banco e Telegram, nem recuperação automática de todas as falhas. Configure acompanhamento de erros no servidor antes de depender de alertas críticos.

Não altere o nome dos nós sem ajustar as referências do workflow. Não habilite retentativa automática no envio sem avaliar duplicidade.

## Casa e energia: integração futura

Os botões são uma interface de planejamento, não uma integração com relés ou equipamentos. O estado exibido é explicitamente `demo_on` e pode ser salvo; não prova que uma lâmpada acendeu.

Uma arquitetura possível na próxima etapa:

- Interface autenticada → backend privado → controlador residencial (por exemplo Home Assistant) → dispositivos.
- Estado real retorna do controlador e só então a interface confirma ligado/desligado.
- Token do controlador fica no backend. Não publique esse token ou o painel residencial sem autenticação.
- Para energia, medidor envia potência/energia acumulada com timestamp. O servidor valida e armazena; o painel recebe leituras e identifica desconexão/atraso.
- Energia em kWh exige energia acumulada do medidor ou integração de potência ao longo do tempo; uma leitura instantânea em watts sozinha não é consumo mensal.

Fonte de API residencial: https://developers.home-assistant.io/docs/api/rest/ . Nenhuma credencial, protocolo ou equipamento foi escolhido/configurado nesta entrega.

## Celular do credor e pedir Pix

No cadastro e na edição de Contas a pagar, informe opcionalmente o celular com DDD (por exemplo 21967631210). O botão Editar na lista permite completar as contas que você já cadastrou. Não precisa recriar as pessoas, quitar ou apagar registros.

O ícone WhatsApp prepara a mensagem pedindo a chave Pix com o saldo restante (valor total menos pagamentos). Você confere o contato e confirma o envio no WhatsApp. Contas quitadas não mostram esse pedido. O campo é opcional; contas antigas sem número continuam funcionando.

Se já tem o banco configurado, execute somente `pessoal/atualizar-telefone.sql` no SQL Editor. Em projeto novo, a migração pessoal completa já inclui o campo. Não é necessário executar o SQL base novamente.

Para atualizar localmente, substitua os arquivos do aplicativo na mesma pasta e acesse pelo mesmo endereço/porta do navegador. Dados de demonstração ficam no armazenamento do navegador: não limpe os dados do site e não mude a origem se quiser continuar vendo os registros locais existentes. Registros do Supabase permanecem no banco.

## Vencimento hoje, resumo mensal e comprovantes

Contas que vencem hoje e têm saldo aparecem em vermelho com uma pulsação suave no selo de vencimento. Contas quitadas não recebem esse destaque; movimentos são desativados se o dispositivo preferir movimento reduzido.

Ao abrir/recarregar o sistema e entrar na conta, os pagamentos que vencem HOJE são mostrados um por vez. Ciente avança para o próximo, e Ver conta abre os detalhes sem dar ciência automaticamente. O aviso não significa que você pagou. As contas atrasadas continuam identificadas na lista, mas não entram nessa sequência de abertura (que é só de hoje). A sequência é exibida uma vez por abertura da página; fechar e abrir/recarregar pode mostrá-la novamente. Não é um alerta garantido com o site fechado; para isso continue usando Telegram/n8n configurado.

O som usa dois tons curtos. Navegadores podem bloquear reprodução automática; use Ativar/testar som. É possível silenciar e essa preferência fica salva no navegador.

Em Contas a pagar há seleção de mês e três totais calculados pelo MÊS DO VENCIMENTO: Total do mês (valores originais), Já pago (pagamentos dessas contas) e Falta pagar no mês (saldos restantes). Esses totais consideram todas as categorias/status, independentemente da busca. A lista acompanha o mês selecionado. Não é relatório por data do pagamento.

Em Registrar pagamento, o comprovante é opcional: JPEG, PNG, WebP ou PDF de até 3 MB. Na demonstração ele ocupa espaço local do navegador; no Supabase, vai para bucket privado. O histórico permite abrir via link temporário e também anexar a um pagamento antigo que ainda não tenha comprovante, sem alterar o valor pago.

**Se o banco já estava configurado, execute somente `pessoal/atualizar-alertas-comprovantes.sql`.** Não apaga registros nem históricos antigos. Em projeto novo, a migração pessoal completa inclui tudo. O SQL e o armazenamento real precisam ser verificados no seu Supabase após a atualização.

## Login pessoal e imagem de fundo
O login usa sua conta existente no Supabase Auth (e-mail e senha).
A URL e a chave pública já configuradas neste navegador são mantidas.
Em um navegador novo, use Configurar conexão uma vez.
O acesso inicial de demonstração foi removido. Os dados locais antigos não são apagados.
Coloque a imagem em assets/backgrounds/login.jpg.
Para outro nome ou extensão, edite login-config.js.
Sem imagem, o fundo fica escuro.

### Erro permission denied ao excluir
Execute pessoal/atualizar-exclusao-contas.sql no SQL Editor do mesmo projeto Supabase
com sua conta administradora. Esse arquivo concede DELETE somente para usuários
autenticados e uma política restringe a exclusão às próprias contas.
Não execute novamente toda a migration para corrigir apenas essa permissão.

## Fotos por tema e telas menores
O seletor Claro/Escuro existe no login e no painel e mantém a escolha no navegador.
Claro usa assets/backgrounds/orla-dia.png; escuro usa assets/backgrounds/orla-login.png.
Ajuste ambos os caminhos em login-config.js.
Sem escolha anterior, inicia no tema claro.
No celular, as tabelas mantêm todas as colunas e permitem deslizar lateralmente.
Configurações e Sair também ficam disponíveis no menu do celular.

## Ícone e exclusão de compromissos
favicon.svg contém o monograma LA da aba do navegador.
A lixeira na agenda e na visão geral exclui o compromisso após confirmação.
Para banco existente, execute somente pessoal/atualizar-exclusao-compromissos.sql.
A revalidação do fluxo Telegram ignora compromissos que já foram excluídos;
mensagens já enviadas não são removidas.

## GitHub, Vercel e n8n local
Este frontend é estático, sem etapa de compilação. Na Vercel use preset Other,
sem Build Command, com a pasta que contém index.html como raiz de publicação.
Mantenha o mesmo projeto Supabase e usuário ao configurar a conexão no novo endereço.
A URL e a chave pública são configuradas por navegador. service_role fica somente no n8n.
O n8n local consulta o Supabase pela internet e envia ao Telegram; não depende do
endereço do frontend. Mantenha o Ubuntu ligado, sem suspensão, com internet,
n8n em execução e workflow publicado.
Não envie .env, tokens ou credenciais exportadas para GitHub/Vercel.
O painel no tema claro não usa imagem; login mantém as fotos por tema.
