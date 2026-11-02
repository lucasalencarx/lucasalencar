# Lucas Alencar

Painel pessoal em HTML, CSS e JavaScript, com Supabase e workflow n8n/Telegram.

1. Leia `pessoal/COMECE-AQUI.md` para acesso, banco e alertas.
2. Em projeto novo, execute `schema.sql`, depois `pessoal/migration.sql`.
3. Se usar Mercado Pago para empréstimos a receber, siga `mercado-pago/CONFIGURAR.md` e sua migração adicional. Não é necessário para cadastrar suas contas pessoais.
4. Configure Supabase pela tela inicial. A chave pública vai no app; service_role e token Telegram só nas credenciais do servidor n8n.

Demonstração: usuário `lucas`, senha `Lucas@2026`. Esse acesso público só serve para explorar dados locais, não protege dados reais. O acesso real usa a conta Supabase Auth e RLS.

Menu: Visão geral, Contas a pagar, Compromissos, Empréstimos pessoais, Energia e Automação residencial.

O pacote `pessoal/telegram.n8n.json` é importável, desativado e sem tokens. Após configurar e publicar no n8n, envia alertas privados de contas/agenda para seu Telegram. O site pode estar fechado; o n8n precisa continuar rodando.

Energia e equipamentos físicos ainda não estão conectados. A calculadora é uma estimativa e os interruptores são explicitamente de demonstração.

Para servir localmente a pasta do projeto:

```bash
python3 -m http.server 8080
```

Abra http://localhost:8080. Não abra o index.html por file://.
