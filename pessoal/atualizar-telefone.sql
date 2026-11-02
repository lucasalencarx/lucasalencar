-- Execute uma vez no SQL Editor do Supabase, depois da migração pessoal.
-- Preserva todas as contas e pagamentos existentes.
begin;
alter table public.personal_bills add column if not exists phone text not null default '';
grant insert(phone),update(phone) on public.personal_bills to authenticated;
commit;
