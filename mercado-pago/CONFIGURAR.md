# Ativar Pix Mercado Pago no Pinguin LA

Esta versão usa a API Payments (`/v1/payments`), com Pix, e webhook do tópico `payment`. Não é o produto de QR de loja física/Orders. Não misture URLs, tópicos, status nem credenciais de integrações diferentes.

## O que está implementado

- Botão **Pix · Mercado Pago** nos detalhes de cada dívida.
- Pix do saldo total ou apenas dos juros, com QR, copia e cola e link do Mercado Pago.
- Compartilhar pelo WhatsApp: abre a mensagem para você conferir e enviar. Sem robô de disparo e sem envio por e-mail.
- Webhook assinado + consulta autenticada ao Mercado Pago + baixa transacional e idempotente no Supabase.
- Recibo interno associado ao pagamento, disponível no histórico. Não é comprovante bancário do pagador.
- Consulta automática a cada 20 segundos enquanto o modal Pix está aberto e botão de consulta manual.
- Cancelamento de Pix pendente, conferindo primeiro se já foi pago.
- Função de conciliação agendável para recuperar pagamentos quando um webhook falhar.

O código está preparado. Sem executar a migração, publicar as funções e configurar sua conta, não há emissão nem confirmação real. A demonstração não inventa QR Code nem pagamento confirmado.

## 1. Preparar Mercado Pago

1. Acesse sua conta e confirme o cadastro, a disponibilidade de Pix via API e a aceitação da sua atividade pelo Mercado Pago. Conta com CPF pode existir, mas este código não garante a elegibilidade da operação.
2. No painel de desenvolvedores, crie uma aplicação e selecione a integração que usa Checkout Transparente/API Payments. Se sua conta só disponibilizar Orders ou exigir outra modalidade, adapte à documentação dela antes de usar este pacote; não misture as duas APIs.
3. Cadastre a chave Pix se exigida pela conta. Separe o Access Token do ambiente escolhido. Não coloque o token na tela de configurações do Pinguin LA.
4. Identifique o número da sua conta recebedora (collector/user ID), disponível nas informações da conta/desenvolvedor. O backend também consulta `/users/me` e exige que o token pertença a esse ID.
5. Configure o webhook na aplicação com o tópico **Pagamentos / payment** e obtenha a assinatura secreta. A URL será a descrita na etapa 5. Esta integração exige notificações assinadas; não desligue a verificação para aceitar notificações sem assinatura.

Use os recursos de teste disponibilizados à sua conta conforme a documentação do Mercado Pago. A disponibilidade de simulação de Pix depende da modalidade e do ambiente. Não use dados fictícios para cobrar uma pessoa real. Se sua modalidade exigir validação em produção, só faça um pagamento controlado depois de configurar e revisar toda a integração.

## 2. Preparar o banco Supabase

1. Se for projeto novo, execute primeiro `schema.sql` da raiz do app.
2. Se já usa o Pinguin LA, preserve as tabelas existentes.
3. Execute `mercado-pago/migration.sql` no SQL Editor.
4. Em Authentication > Users, copie o UUID da sua conta que é dona das dívidas.

A migração adiciona `mp_requests`, evidência do provedor em `payments` e funções de emissão/liquidação. RLS permite ler somente cobranças da própria conta. Emissão, atualização do PSP e baixa só podem ser chamadas pelo servidor com service_role.

Esta versão é de **conta única**: `MP_OWNER_ID` deve ser o UUID do seu usuário no Supabase. Outros usuários do banco não podem emitir Pix usando seu token Mercado Pago. Para múltiplos recebedores seria necessário OAuth e credenciais segregadas; não está implementado.

## 3. Publicar as Edge Functions

Use a CLI oficial do Supabase no seu computador. A pasta `mercado-pago` contém uma pasta `supabase` com configuração e funções prontas. Dentro dela:

```bash
cd CAMINHO_DA_PASTA_EXTRAIDA/pinguin-la/mercado-pago
npx supabase login
npx supabase link --project-ref SEU_PROJECT_REF
npx supabase functions deploy mp-create
npx supabase functions deploy mp-sync
npx supabase functions deploy mp-webhook --no-verify-jwt
npx supabase functions deploy mp-reconcile --no-verify-jwt
```

Substitua `SEU_PROJECT_REF` pelo identificador do projeto Supabase (não é o UUID do usuário).

- `mp-create` e `mp-sync`: JWT exigido pela plataforma e sessão também validada em `/auth/v1/user` pelo código.
- `mp-webhook`: não pode exigir o JWT de um usuário, porque quem chama é o Mercado Pago. O handler exige assinatura HMAC e consulta o pagamento no provedor antes de escrever no banco.
- `mp-reconcile`: exige o segredo próprio `x-reconcile-secret`; não é uma rota pública sem autenticação.

As variáveis `SUPABASE_URL`, `SUPABASE_ANON_KEY` e `SUPABASE_SERVICE_ROLE_KEY` são usadas no ambiente das funções. Confirme que estão disponíveis no projeto. Não copie service_role para o frontend.

## 4. Configurar os secrets

Em Supabase > Edge Functions > Secrets, configure:

| Nome | Valor |
|---|---|
| MP_ACCESS_TOKEN | Access Token do Mercado Pago para este ambiente |
| MP_WEBHOOK_SECRET | Assinatura secreta da aplicação que envia os webhooks |
| MP_COLLECTOR_ID | Número da conta recebedora no Mercado Pago |
| MP_OWNER_ID | UUID do seu usuário no Supabase |
| MP_MODE | `test` ou `production`, coerente com o pagamento devolvido pelo PSP |
| MP_ALLOWED_ORIGINS | URL do Pinguin LA, sem barra final; mais origens separadas por vírgula se necessário |
| MP_RECONCILE_SECRET | Segredo aleatório longo, para a rotina de conciliação |
| MP_ENABLED | Comece com `false`; altere para `true` apenas depois de configurar os demais valores |

URL atual do app: `https://pinguin-la-lucas.alencardeniteroi.chatgpt.site`.

Para testes locais do frontend, acrescente `http://localhost:8080` a MP_ALLOWED_ORIGINS. Não use `*` e não coloque origens de terceiros.

Você também pode criar um arquivo `.secrets.env` LOCAL, fora de pasta pública e do Git, e carregá-lo com `npx supabase secrets set --env-file .secrets.env`. O arquivo não está incluído no pacote. Não envie esses segredos por conversa.

A verificação de ambiente compara `live_mode` devolvido pela API: isso impede registrar confirmação de teste como produção e vice-versa. Verifique no painel e nas credenciais qual ambiente a modalidade realmente oferece antes de habilitar emissão.

## 5. Configurar o webhook

Na aplicação Mercado Pago que corresponde ao token, configure para o evento/tópico `payment`:

```text
https://SEU_PROJECT_REF.supabase.co/functions/v1/mp-webhook
```

A mesma URL é incluída na criação de cada Pix como `notification_url`. O handler valida `x-signature`, `x-request-id` e `data.id`, e consulta `/v1/payments/ID` usando o token do servidor. Depois confere conta recebedora, BRL, Pix, valor, referência interna e ambiente.

O endpoint roda na infraestrutura Supabase; não depende de seu computador/n8n nem do app aberto. Configure domínio/certificado válido (a URL Supabase já é HTTPS) e acompanhe logs de erro das funções e entregas no painel Mercado Pago.

A assinatura deve corresponder à aplicação que gerou a notificação. Se o simulador usar dados inexistentes ou referências não vinculadas ao Pinguin LA, ele não produzirá baixa. Não remova verificações para fazer uma simulação “passar”.

## 6. Como usar

1. Entre no Pinguin LA conectado ao mesmo Supabase da migração.
2. Abra uma dívida > **Pix · Mercado Pago**.
3. Escolha saldo total ou somente juros.
4. Informe o e-mail e CPF reais do pagador. Esses dados são exigidos para a emissão; não ativam avisos por e-mail.
5. Clique em **Gerar Pix**. QR Code e copia e cola são os retornados pelo Mercado Pago.
6. Clique em **Compartilhar no WhatsApp**. Confira destinatário e mensagem e confirme o envio no seu WhatsApp. O compartilhamento usa o link do pagamento, quando disponível, para a pessoa acessar também o QR e copia e cola no celular.
7. Depois do pagamento, o webhook registra a baixa. Em Recebimentos, abra **Recibo do Pix confirmado**.

Enquanto houver Pix ativo, baixa manual e renovação ficam bloqueadas. Para mudar o acordo, primeiro consulte/cancele o Pix. Um cancelamento que encontrar pagamento já aprovado registra o recebido em vez de tentar zerar a cobrança. Na janela de emissão, o botão Gerar fica desabilitado; o banco ainda preserva uma única cobrança ativa por dívida e o PSP recebe a mesma chave de idempotência nas retentativas.

A expiração do QR é de 24 horas. Não confunda a validade do QR com o vencimento do acordo: uma dívida atrasada pode precisar de um Pix novo. Depois de confirmar cancelamento/recusa no provedor, o app permite emitir outra cobrança.

## 7. Recibo e privacidade

A confirmação verificada é armazenada em `mp_requests.evidence` e anexada como dados estruturados em `payments.provider_receipt`, na mesma transação da baixa. O app permite baixar um recibo HTML interno com ID, data, valor, principal, juros e ambiente. Não há upload automático de PDF bancário.

O comprovante do banco do pagador continua dependendo de envio por ele; o anexo manual existente continua disponível.

O corpo com CPF e e-mail fica privado no banco enquanto a emissão é recuperável por idempotência; depois de obter o ID da cobrança, o código apaga esse corpo da requisição local. A API do Mercado Pago mantém os dados conforme seus próprios termos. Não registre CPF, e-mail, token ou payload completo em logs de produção. Retentativas usam o mesmo corpo original; se precisar corrigir o pagador de uma emissão, consulte/cancele primeiro, sem reaproveitar o ID com dados diferentes.

## 8. Recuperar webhook perdido sem depender do app

A função `mp-reconcile` consulta até 10 cobranças já identificadas no provedor por execução, incluindo pendentes, pagas e em revisão, começando pelas menos recentemente verificadas. Atualizações válidas atualizam a ordem, permitindo percorrer o conjunto em execuções seguintes. Se seu volume crescer, aumente a capacidade com fila/paginação e monitore atrasos/falhas.

No n8n, crie um workflow SEM nó de e-mail:

1. Schedule Trigger a cada 5 minutos.
2. HTTP Request `POST` para `https://SEU_PROJECT_REF.supabase.co/functions/v1/mp-reconcile`.
3. Credencial Header Auth: nome `x-reconcile-secret`; valor igual a MP_RECONCILE_SECRET.
4. Verifique resposta com `checked`, `ok`, `failed`. Publique o workflow e monitore as execuções.

O n8n local precisa ficar ligado para essa rotina. Para dispensar seu computador, agende a mesma chamada numa infraestrutura sempre disponível (por exemplo Supabase Cron/pg_net usando segredo em Vault). O webhook principal funciona sem esse agendamento, mas não substitua monitoramento e conciliação por uma suposição de que nunca haverá falhas.

Se houver `creating` sem provider_id após um timeout, recupere a emissão no mesmo acordo/tipo: o corpo e a chave são preservados. A conciliação agendada não recria cobranças sem ID. Se uma emissão continuar sem recuperação, especialmente após a expiração, confira a chave/referência no painel/API Mercado Pago e resolva com suporte antes de liberar a reserva. Não apague a reserva nem gere uma nova chave às cegas, porque a emissão anterior pode ter sido aceita.

## 9. Limites e conciliação humana

- Parcial livre não foi incluído na emissão Pix desta versão; há saldo total e somente juros. O registro manual parcial existente permanece, desde que não haja Pix ativo.
- Se o saldo/acordo divergir do retrato usado na emissão, o Pix recebido fica em **Precisa de conciliação**, sem abatimento cego.
- Reembolso total/parcial ou contestação vira **Precisa de conciliação** e marca o recebimento com alerta. Esta versão NÃO reabre automaticamente o saldo nem executa devolução; revise no Mercado Pago e faça lançamento contábil/correção auditável com suporte antes de voltar a cobrar. O total recebido continua bruto até essa conciliação. Não simplesmente marque como cancelado nem apague pagamento para liberar a dívida.
- O modo revisão bloqueia novas cobranças e alterações manuais do acordo. Não há botão para resolver essa exceção no aplicativo nesta versão; exige conciliação administrativa documentada no banco/servidor. Trate isso antes de usar em escala.
- Não há serviço de disparo automático no WhatsApp. O envio desta etapa é manual; as regras do WhatsApp e do Mercado Pago continuam aplicáveis à atividade real.
- O aplicativo não tem acesso ao extrato de outra conta. Pix feito fora da cobrança gerada precisa de conciliação própria.

## 10. Verificação antes de produção

Execute testes controlados no ambiente permitido pelo provedor:

- Saldo total: baixa principal + juros uma vez.
- Somente juros: baixa juros e preserva principal.
- Repetir o mesmo webhook e consultar junto: mantém um único pagamento.
- Assinatura falsa/valor/conta/referência/ambiente divergentes: não baixa.
- Cancelar ao mesmo tempo que aprova: consulta o estado real e não perde o recebimento.
- Dois cliques/timeout na emissão: mesma referência e mesma chave no PSP.
- Outro usuário autenticado: não emite Pix para sua conta recebedora.
- Receber manualmente/renovar com Pix pendente: bloqueado.
- Expiração/cancelamento/recusa e emissão seguinte: nenhuma cobrança antiga esquecida.
- Reembolso: alerta de conciliação visível no histórico, sem ajuste financeiro inventado.
- App fechado: webhook registra; reabrir mostra saldo atualizado.

Testes automatizados de valor, HMAC, isolamento da resposta e validações básicas estão em `tests/core.test.mjs`:

```bash
node --test tests/core.test.mjs
```

Não foi possível executar o SQL em seu banco nem confirmar pagamento real sem configurar suas credenciais. Não use esta entrega como prova de homologação financeira; faça os testes acima e revise o enquadramento da conta antes de habilitar produção.

Fontes oficiais consultadas:
- https://www.mercadopago.com.br/developers/pt/docs/checkout-api-payments/integration-configuration/integrate-pix
- https://www.mercadopago.com.br/developers/pt/docs/your-integrations/notifications/webhooks
- https://supabase.com/docs/guides/functions/auth
- https://supabase.com/docs/guides/functions/deploy
