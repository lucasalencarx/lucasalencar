-- Exclusão somente dos compromissos do próprio usuário.
begin;
grant delete on public.personal_events to authenticated;
drop policy if exists events_delete on public.personal_events;
create policy events_delete on public.personal_events
for delete to authenticated using (user_id = (select auth.uid()));
commit;
