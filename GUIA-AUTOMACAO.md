# Pinguin LA — guia de Pix, baixa automática e chatbot de IA

Preparado em 27/10/2026. Este arquivo é um projeto de implementação. A atualização visual está pronta; os serviços de pagamento, mensagens e IA abaixo ainda não estão conectados.

## 1. O resultado que queremos

Você cadastra a pessoa, o acordo, o principal, os juros, o vencimento e o tipo de recebimento esperado. O sistema cria uma cobrança Pix identificada. Um serviço agendado envia o lembrete pelo canal autorizado. Quando a pessoa paga esse Pix, o provedor informa seu servidor, que confirma a transação, registra o recebimento, abate o saldo e guarda a evidência. Você recebe um aviso e não precisa marcar o pagamento manualmente.

O app não precisa ficar aberto: o agendamento, a recepção do pagamento e a conciliação rodam no servidor.

## 2. Decisão necessária antes de contratar WhatsApp e Pix

A política oficial do WhatsApp Business consultada lista empréstimos P2P e cobrança de dívidas entre atividades proibidas. O cenário descrito — pessoas devendo com juros — pode entrar diretamente nessa restrição. Portanto, este guia NÃO propõe colocar um robô de cobrança dessas dívidas em produção no WhatsApp. Não trate aprovação de um template como autorização da atividade e não use automação de WhatsApp Web para contornar a política.

Se o caso real for lembrete de pagamento por venda/serviço próprio, descreva a operação real e confirme com a Meta/BSP a elegibilidade exata antes de configurar o canal. Consentimento do cliente não elimina restrições de atividade. Para dívidas/empréstimos, escolha um canal e um provedor que aceitem expressamente sua operação; por exemplo, e-mail ou portal de pagamento, sujeito aos termos do fornecedor.

O provedor de Pix também precisa aprovar seu cadastro e sua atividade. Uma conta Pagar.me já usada em outro projeto não significa autorização para receber parcelas de empréstimos. A arquitetura abaixo usa Pagar.me como referência técnica; um banco ou PSP com Pix Cobrança e API pode substituí-lo se aceitar a atividade. Não há garantia de aprovação, disponibilidade para pessoa física ou tarifa neste guia.

Fonte oficial: https://business.whatsapp.com/policy

## 3. Peças do sistema

| Peça | Trabalho |
|---|---|
| Pinguin LA | Cadastro, saldos, histórico, regras e painel de acompanhamento |
| Supabase | Auth, banco, RLS e bucket privado de comprovantes |
| Backend/Edge Functions | Criar Pix, validar pagamentos e executar transações financeiras |
| Banco/PSP aprovado | Emitir Pix identificado e confirmar o recebimento |
| n8n em servidor disponível | Agendar lembretes, encaminhar mensagens e avisos, tratar falhas |
| Canal de mensagens autorizado | Entregar lembrete/link e receber respostas |
| API de IA | Interpretar perguntas e responder com informações autorizadas do acordo |

O n8n organiza o fluxo; os saldos devem continuar sob regras transacionais do banco. A IA não decide se o dinheiro entrou e não calcula juros livremente.

## 4. Como o Pix deve funcionar

Use uma cobrança dinâmica e identificada por recebimento esperado. Guarde o ID da cobrança, o ID da dívida, o valor em centavos, a data de expiração e a divisão entre principal e juros. Não dependa de reconhecer depósitos feitos em uma chave Pix estática compartilhada.

Exemplo: dívida de R$ 1.000 de principal + R$ 100 em juros.

- Cobrança integral: Pix de R$ 1.100, alocado a R$ 1.000 de principal e R$ 100 de juros.
- Somente juros: Pix de R$ 100, alocado a R$ 0 de principal e R$ 100 de juros.
- Parcial combinado: por exemplo R$ 300, com a alocação explicitamente definida antes de emitir.

Quando um Pix de somente juros é confirmado, o sistema zera os juros pagos e mantém o principal. Novo vencimento e juros de outro período só entram se houver regra de renovação previamente aprovada; não devem surgir da interpretação de uma conversa pela IA.

O Pagar.me documenta o retorno de `qr_code` (copia e cola), `qr_code_url` e eventos como `charge.paid`. A disponibilidade depende da configuração da conta. Valores, campos obrigatórios do pagador e testes devem seguir a modalidade contratada.

Fontes: https://docs.pagar.me/reference/pix-2 e https://docs.pagar.me/docs/webhooks

## 5. Tabelas a acrescentar numa segunda etapa

Este é um desenho de migração futura, não um SQL para executar agora. O `schema.sql` do aplicativo continua suficiente para o controle manual atual.

| Tabela | Campos principais |
|---|---|
| payment_requests | id, owner_id, debt_id, provider, provider_charge_id UNIQUE, principal_cents, interest_cents, amount_cents, status, expires_at, qr_text, qr_image_url, idempotency_key UNIQUE |
| provider_events | provider, event_id UNIQUE por provedor, charge_id, received_at, processing_status, attempts, erro sanitizado |
| payment_settlements | payment_request_id UNIQUE, payment_id, provider_transaction_id UNIQUE, paid_at, amount_cents, end_to_end_id quando disponível |
| message_jobs | owner_id, debt_id, payment_request_id, channel, destination, schedule_at, dedup_key UNIQUE, status, provider_message_id, retry_at |
| contact_preferences | pessoa/acordo, canal autorizado, contato verificado, consentimento quando necessário, opt_out_at |
| conversations | owner_id, contact_id, channel, external_message_id UNIQUE, mensagem, status de atendimento |
| receipt_evidence | payment_id, source, storage_path, transaction_reference, received_at, review_status |

Adicione referência à liquidação no registro financeiro. Dê RLS por proprietário às tabelas visíveis ao app. Tabelas de evento e operações financeiras internas devem aceitar escrita só do backend autorizado. Evite guardar payloads completos contendo dados pessoais desnecessários.

A função atual `record_payment` usa a sessão do usuário (`auth.uid()`). Não deve ser chamada cegamente por um webhook com service_role: crie uma função separada de liquidação automática, disponível apenas ao backend, que derive o proprietário pela cobrança previamente cadastrada e nunca por um owner_id enviado pelo pagador.

## 6. Ordem prática de construção

1. **Aprovar atividade e escolher canal.** Confirme banco/PSP e mensageria antes de gastar com integração. Para o caso de dívidas com juros, resolva a restrição do WhatsApp antes de qualquer configuração de produção.
2. **Preparar o servidor.** Use Edge Functions/backend HTTPS, e n8n em hospedagem sempre disponível. Tokens do PSP, service_role e chave da IA ficam em secrets/credenciais do servidor, nunca em JavaScript público, localStorage ou no ZIP do site.
3. **Criar as tabelas e as regras.** Use centavos inteiros para a integração, identificadores únicos, logs e transação atômica para a baixa. Mantenha registros manuais e automáticos conciliáveis.
4. **Implementar a emissão.** Endpoint autenticado `POST /payment-requests`: verifica o proprietário, lê saldo atual, valida o tipo/valor, cria uma única cobrança no PSP e devolve QR/copia e cola. Use chave de idempotência estável; cliques repetidos e timeouts não devem criar várias cobranças.
5. **Implementar o recebimento do webhook.** Endpoint HTTPS específico, proteção prevista pelo PSP e consulta autenticada da cobrança na API antes de qualquer baixa. Não confie apenas no JSON recebido. Valide conta recebedora, charge_id, moeda, valor, status e associação à dívida.
6. **Liquidar atomicamente.** Grave um evento durável, bloqueie cobrança e dívida, verifique que ainda não foram liquidadas, insira um único pagamento e abata principal/juros na mesma transação. Marque o evento como processado. Só confirme o webhook conforme o protocolo depois de persistir o trabalho; suporte reenvios.
7. **Conciliar falhas.** Um fluxo periódico consulta cobranças pendentes no PSP, com limites e paginação. Assim, um webhook perdido não deixa um Pix pago esquecido. Retentativas devem reutilizar as mesmas chaves.
8. **Gerar evidência e avisar você.** Grave a confirmação financeira e produza um recibo interno. Atualize o painel por atualização periódica ou Supabase Realtime com RLS e publicação configuradas. Envie o aviso ao proprietário pelo canal escolhido.
9. **Adicionar os lembretes.** Só para acordos ativos, com saldo e canal permitido; deduplicação, horários, limite de frequência e suspensão imediata ao pagar/contestar. Antes de enviar, releia o saldo e a situação da cobrança.
10. **Adicionar o chatbot.** Depois que emissão e baixa estiverem estáveis, conecte IA às ferramentas restritas abaixo. Libere produção somente após testes de ponta a ponta.

Se outra cobrança ou pagamento manual mudar o saldo, invalide/cancele as cobranças antigas quando o PSP permitir. Um pagamento antigo que entrar mesmo assim precisa ir para conciliação, sem gerar saldo negativo ou desaparecer. Trate também expiração, divergência de valor e estornos com lançamento de reversão auditável, sem apagar o pagamento original.

## 7. Quatro workflows do n8n

### A — Preparar e enviar o lembrete

`Schedule Trigger` no fuso America/Sao_Paulo → backend lista acordos elegíveis → reserva um message_job com chave única → cria ou reutiliza Pix pendente válido → consulta novamente saldo/situação → envia pelo canal permitido → grava ID e resultado do envio.

Comece com um lembrete configurável por vencimento. Não reenvie a cada execução. Falhas transitórias usam retentativas limitadas; cancelamento/opt-out e contestação suspendem novos envios. Mantenha minimização de dados e verifique o contato para não revelar saldo a outra pessoa.

### B — Baixa financeira

`Webhook` de produção → backend valida evento e consulta PSP → função transacional de liquidação → gerar evidência/recibo interno → avisar proprietário. Esse fluxo funciona sem IA.

O n8n documenta URLs distintas para teste e produção: use a URL de produção do workflow publicado no PSP. A URL de teste não é uma integração permanente.

### C — Atendimento com IA

Webhook do canal autorizado → deduplicar mensagem → identificar conversa e verificar acesso ao acordo → carregar apenas os dados necessários → IA interpreta a intenção → ferramenta autorizada → validar resposta → enviar e registrar.

Se a atividade de WhatsApp for elegível e confirmada, n8n oferece WhatsApp Trigger para receber eventos e WhatsApp Business Cloud para enviar mensagens e trabalhar com mídia. Configure credenciais da Meta no n8n conforme documentação atual. Para mensagens iniciadas pela empresa, valide opt-in, regras de janela e templates aplicáveis com a Meta/BSP. Esses requisitos não tornam permitida uma atividade proibida.

### D — Conciliação e alertas de operação

Agendamento → buscar requisições pendentes/eventos com falha → consultar PSP → repetir a mesma função idempotente de liquidação → alertar proprietário/operador sobre divergências. Uma mensagem entregue não é um pagamento recebido.

Fontes n8n:
- https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-base.webhook/
- https://docs.n8n.io/integrations/builtin/credentials/whatsapp/
- https://docs.n8n.io/integrations/builtin/trigger-nodes/n8n-nodes-base.whatsapptrigger/
- https://docs.n8n.io/integrations/builtin/app-nodes/n8n-nodes-base.whatsapp/

## 8. Ferramentas do chatbot

| Ferramenta | Permissão |
|---|---|
| consultar_meu_acordo | Só o acordo vinculado à identidade verificada da conversa |
| obter_pix_valido | Retorna cobrança atual já autorizada; não inventa chave Pix |
| informar_promessa | Registra que a pessoa pretende pagar em uma data, sem alterar vencimento/juros |
| anexar_comprovante | Guarda arquivo como recebido e pendente de verificação |
| solicitar_revisao | Encaminha contestação, renegociação ou erro para Lucas |

Não entregue à IA acesso irrestrito ao SQL, à service_role, à função de quitação ou ao cadastro completo de pessoas. O backend deve verificar cada chamada independentemente do texto gerado pelo modelo. Uma mensagem recebida pode tentar instruir o agente a ignorar regras; ela é conteúdo do cliente, não autorização administrativa.

Política de instrução sugerida para configurar o agente:

“Você é o assistente virtual do Pinguin LA. Identifique-se como assistente automatizado. Use apenas dados retornados por ferramentas autorizadas para este contato. Não invente saldo, taxa, vencimento, desconto, chave Pix ou confirmação de pagamento. Não quite dívidas, altere juros ou aprove renegociação. Se a pessoa disser que pagou, consulte o status financeiro. Receba comprovantes como evidência pendente. Encaminhe contestação, divergência e pedidos de negociação para atendimento humano. Respeite preferência de contato e não exponha informações de outras pessoas.”

## 9. Comprovante automático: o que é possível

Há duas coisas diferentes:

1. **Confirmação da transação pelo PSP:** pode ser obtida automaticamente e vinculada ao pagamento. Guarde ID da cobrança, ID da transação, valor, data, resposta verificada e EndToEndId se disponibilizado. Se o provedor fornecer recibo por arquivo/URL, salve-o com acesso privado. Não assuma que todo PSP entrega PDF bancário.
2. **Comprovante do aplicativo do banco do pagador:** o sistema não tem acesso automático a ele. A pessoa precisa enviá-lo no canal ou no portal. O bot pode baixar a mídia após validar sua origem e salvar no bucket privado, associando ao acordo confirmado da conversa. Limite MIME/tamanho, faça inspeção de arquivo e retenção definida. Não use OCR como confirmação de liquidação.

Você pode gerar um PDF intitulado “Recibo interno do Pinguin LA — pagamento confirmado pelo provedor”. Inclua referências verificadas; não o apresente como comprovante emitido pelo banco do pagador. Esse recibo pode ficar anexado automaticamente assim que a confirmação chegar.

Pagamentos feitos fora do Pix gerado só terão baixa automática se houver integração de extrato/Pix recebido e uma regra confiável de associação. Se a associação não for inequívoca, deixe pendente para conciliação.

## 10. Testes antes de ativar

- Pix integral: uma baixa e dívida quitada.
- Pix somente juros: principal preservado e juros baixados.
- Parcial: alocação aprovada e saldo remanescente correto.
- Mesmo webhook repetido, e webhook junto com conciliação: nenhum pagamento duplicado.
- Webhook falso: nenhuma alteração de saldo.
- Valor/conta/dívida divergente: fila de revisão e nenhum abatimento indevido.
- Webhook perdido e servidor reiniciado: conciliação recupera o pagamento.
- Cobrança expirada ou anterior a uma renegociação: não emitir código inválido nem abater saldo incorreto.
- Pagamento manual simultâneo: bloqueio/validação impedem saldo negativo.
- Print falso e texto “paguei”: arquivo salvo para revisão, sem quitação por IA.
- Estorno: reversão auditada e saldo ajustado conforme a confirmação do PSP.
- Lembrete programado após pagamento/contestação: suprimido antes do envio.
- Outro telefone ou outra conta: nenhum acesso ao acordo alheio.

## 11. O que você precisa separar para a próxima implementação

- Confirmar se os valores são de empréstimos pessoais ou vendas/serviços, e obter aceite do banco/PSP para essa operação.
- Conta de teste do PSP com Pix/API disponíveis e documentação da modalidade.
- Definir o canal permitido e o remetente; para WhatsApp, primeiro resolver a elegibilidade da atividade com Meta/BSP.
- Projeto Supabase e backend com secrets configurados por você no ambiente seguro.
- n8n hospedado e URL HTTPS permanente.
- Provedor/modelo de IA e credencial configurada no servidor, caso queira conversa livre.
- Regras: quando lembrar, quantas vezes, horário, principal/juros de cada cobrança, renovação, contestação e estorno.

Não envie chaves secretas em mensagens. A próxima etapa técnica mais útil é implementar emissão de Pix + confirmação + baixa + evidência, antes do chatbot. Essa etapa resolve o trabalho de marcar pagamentos manualmente mesmo sem uma IA conversando.
