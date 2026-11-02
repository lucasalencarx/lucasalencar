-- Complemento opcional: execute DEPOIS do schema.sql do aplicativo.
-- Leitura para o servidor n8n; não altera saldos nem envia mensagens.
create or replace function public.pinguin_daily_due(p_owner uuid, p_timezone text default 'America/Sao_Paulo')
returns table(id uuid,name text,due date,principal numeric,interest numeric,status text)
language plpgsql security definer set search_path='' as $$
declare local_day date;
begin
 if p_owner is null then raise exception 'Proprietário obrigatório'; end if;
 if p_timezone not in ('America/Sao_Paulo','America/Campo_Grande') then raise exception 'Fuso inválido'; end if;
 local_day := (now() at time zone p_timezone)::date;
 return query select d.id,d.name,d.due,d.principal,d.interest,
 case when d.due=local_day then 'Vence hoje' else 'Atrasado' end
 from public.debts d where d.user_id=p_owner and d.principal+d.interest>0 and d.due<=local_day
 order by d.due,d.name;
end $$;
revoke all on function public.pinguin_daily_due(uuid,text) from public,anon,authenticated;
grant execute on function public.pinguin_daily_due(uuid,text) to service_role;
