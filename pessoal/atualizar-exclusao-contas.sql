-- Permite excluir somente contas do próprio usuário. Não registra pagamento.
begin;
grant delete on public.personal_bills to authenticated;
drop policy if exists bills_delete on public.personal_bills;
create policy bills_delete on public.personal_bills
for delete to authenticated using (user_id = (select auth.uid()));
commit;
