-- Módulos pessoais: execute após schema.sql. Não altera empréstimos nem Mercado Pago.
begin;
create table if not exists public.personal_bills (
 id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id),
 title text not null check(length(trim(title)) between 1 and 150),creditor text not null default '',category text not null default 'Pessoal',
 amount numeric(14,2) not null check(amount>0 and amount::text not in ('NaN','Infinity','-Infinity')),
 paid numeric(14,2) not null default 0 check(paid>=0 and paid<=amount and paid::text not in ('NaN','Infinity','-Infinity')),
 due date not null,notes text not null default '',payment_log jsonb not null default '[]',created_at timestamptz not null default now()
);
create table if not exists public.personal_events (
 id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id),title text not null check(length(trim(title)) between 1 and 150),
 starts_at timestamptz not null,location text not null default '',notes text not null default '',reminder_minutes integer not null default 30 check(reminder_minutes in (0,15,30,60,1440)),done boolean not null default false,created_at timestamptz not null default now()
);
create table if not exists public.personal_devices (
 id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id),room text not null check(length(room) between 1 and 80),
 name text not null check(length(name) between 1 and 100),type text not null default 'Iluminação',demo_on boolean not null default false,created_at timestamptz not null default now()
);
create table if not exists public.personal_preferences (user_id uuid primary key references auth.users(id),energy_tariff numeric(8,4) not null default 0 check(energy_tariff between 0 and 100));
create table if not exists public.personal_alert_jobs (
 id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id),source_type text not null,source_id uuid not null,
 dedup_key text not null unique,message text not null,status text not null default 'claimed' check(status in ('claimed','sent','cancelled')),
 telegram_message_id text,created_at timestamptz not null default now(),sent_at timestamptz
);
do $$declare t text;begin foreach t in array array['personal_bills','personal_events','personal_devices','personal_preferences'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('drop policy if exists personal_owner on public.%I',t);
 execute format('create policy personal_owner on public.%I for all to authenticated using (user_id=(select auth.uid())) with check(user_id=(select auth.uid()))',t);
 execute format('revoke all on public.%I from anon,authenticated',t);
 end loop;end $$;
grant select on public.personal_bills to authenticated;
grant insert(user_id,title,creditor,category,amount,due,notes,paid) on public.personal_bills to authenticated;
grant update(title,creditor,category,amount,due,notes) on public.personal_bills to authenticated;
drop policy if exists personal_bill_insert on public.personal_bills;
-- A política geral é permissiva; substituí-la evita inserir pagamentos por fora da RPC.
drop policy if exists personal_owner on public.personal_bills;
drop policy if exists bills_select on public.personal_bills;
create policy bills_select on public.personal_bills for select to authenticated using(user_id=(select auth.uid()));
drop policy if exists bills_update on public.personal_bills;
create policy bills_update on public.personal_bills for update to authenticated using(user_id=(select auth.uid())) with check(user_id=(select auth.uid()));
create policy personal_bill_insert on public.personal_bills for insert to authenticated with check(user_id=(select auth.uid()) and paid=0);
grant select,insert,update on public.personal_events,public.personal_devices,public.personal_preferences to authenticated;
alter table public.personal_alert_jobs enable row level security;
drop policy if exists personal_alert_read on public.personal_alert_jobs;
create policy personal_alert_read on public.personal_alert_jobs for select to authenticated using(user_id=(select auth.uid()));
revoke all on public.personal_alert_jobs from anon,authenticated;
grant select on public.personal_alert_jobs to authenticated;
create index if not exists personal_bills_due on public.personal_bills(user_id,due);
create index if not exists personal_events_time on public.personal_events(user_id,starts_at);
create or replace function public.personal_pay_bill(p_bill uuid,p_amount numeric,p_date date)
returns void language plpgsql security definer set search_path='' as $$
declare b public.personal_bills%rowtype;begin
 select * into b from public.personal_bills where id=p_bill and user_id=auth.uid() for update;
 if not found then raise exception 'Conta não encontrada';end if;
 if p_amount is null or p_amount::text in ('NaN','Infinity','-Infinity') or p_amount<=0 or p_amount<>round(p_amount,2) or p_amount>b.amount-b.paid or p_date is null or p_date>(now() at time zone 'America/Sao_Paulo')::date then raise exception 'Pagamento inválido';end if;
 update public.personal_bills set paid=paid+p_amount,payment_log=payment_log||jsonb_build_array(jsonb_build_object('amount',p_amount,'date',p_date)) where id=p_bill;
 end $$;
revoke all on function public.personal_pay_bill(uuid,numeric,date) from public,anon;
grant execute on function public.personal_pay_bill(uuid,numeric,date) to authenticated;

-- Reserva até 6 alertas por execução. Apenas servidor: chave service_role nas credenciais n8n.
create or replace function public.personal_claim_alerts(p_owner uuid,p_timezone text default 'America/Sao_Paulo')
returns setof public.personal_alert_jobs language plpgsql security definer set search_path='' as $$
declare c record;j public.personal_alert_jobs%rowtype;day_local date;clock_local time;
begin
 if p_owner is null or p_timezone not in ('America/Sao_Paulo','America/Campo_Grande') then raise exception 'Configuração inválida';end if;
 day_local:=(now() at time zone p_timezone)::date;clock_local:=(now() at time zone p_timezone)::time;
 for c in
 select * from (
  select 'bill'::text typ,b.id source,b.id::text||':bill:'||day_local::text key,
   'Conta a pagar: '||left(b.title,100)||E'\nPara: '||left(b.creditor,80)||E'\nRestante: R$ '||(b.amount-b.paid)::text||E'\nVencimento: '||to_char(b.due,'DD/MM/YYYY') msg,b.due::timestamptz sort_at
  from public.personal_bills b where b.user_id=p_owner and b.amount>b.paid and b.due<=day_local and clock_local>='09:00'::time
  union all
  select 'event',e.id,e.id::text||':event:'||e.starts_at::text||':'||e.reminder_minutes::text,
   'Compromisso: '||left(e.title,100)||E'\nQuando: '||to_char(e.starts_at at time zone p_timezone,'DD/MM/YYYY HH24:MI')||E'\nLocal: '||left(e.location,100),e.starts_at
  from public.personal_events e where e.user_id=p_owner and not e.done and e.starts_at- make_interval(mins=>e.reminder_minutes)<=now() and e.starts_at>=now()-interval '1 hour'
 ) candidates where not exists(select 1 from public.personal_alert_jobs aj where aj.dedup_key=candidates.key) order by sort_at limit 6
 loop
  insert into public.personal_alert_jobs(user_id,source_type,source_id,dedup_key,message) values(p_owner,c.typ,c.source,c.key,c.msg) on conflict(dedup_key) do nothing returning * into j;
  if found then return next j;end if;
 end loop;
end $$;
create or replace function public.personal_finish_alerts(p_ids uuid[],p_message_id text)
returns void language sql security definer set search_path='' as $$
 update public.personal_alert_jobs set status='sent',sent_at=now(),telegram_message_id=p_message_id where id=any(p_ids) and status='claimed';
$$;
revoke all on function public.personal_claim_alerts(uuid,text),public.personal_finish_alerts(uuid[],text) from public,anon,authenticated;
grant execute on function public.personal_claim_alerts(uuid,text),public.personal_finish_alerts(uuid[],text) to service_role;
commit;
-- Revalidar imediatamente antes de montar o resumo para suprimir contas já pagas/eventos concluídos.
create or replace function public.personal_prepare_alerts(p_ids uuid[],p_timezone text default 'America/Sao_Paulo')
returns setof public.personal_alert_jobs language plpgsql security definer set search_path='' as $$
declare j public.personal_alert_jobs%rowtype;b public.personal_bills%rowtype;e public.personal_events%rowtype;day_local date;
begin
 if p_timezone not in ('America/Sao_Paulo','America/Campo_Grande') then raise exception 'Fuso inválido';end if;
 day_local:=(now() at time zone p_timezone)::date;
 for j in select * from public.personal_alert_jobs where id=any(p_ids) and status='claimed' for update loop
  if j.source_type='bill' then
   select * into b from public.personal_bills where id=j.source_id and user_id=j.user_id;
   if not found or b.amount<=b.paid or b.due>day_local then update public.personal_alert_jobs set status='cancelled' where id=j.id;continue;end if;
   j.message:='Conta a pagar: '||left(b.title,100)||E'\nPara: '||left(b.creditor,80)||E'\nRestante: R$ '||(b.amount-b.paid)::text||E'\nVencimento: '||to_char(b.due,'DD/MM/YYYY');
  else
   select * into e from public.personal_events where id=j.source_id and user_id=j.user_id;
   if not found or e.done or j.dedup_key<>e.id::text||':event:'||e.starts_at::text||':'||e.reminder_minutes::text then update public.personal_alert_jobs set status='cancelled' where id=j.id;continue;end if;
  end if;
  return next j;
 end loop;
end $$;
revoke all on function public.personal_prepare_alerts(uuid[],text) from public,anon,authenticated;
grant execute on function public.personal_prepare_alerts(uuid[],text) to service_role;

-- Celular opcional do credor: compatível com registros antigos.
alter table public.personal_bills add column if not exists phone text not null default '';
grant insert(phone),update(phone) on public.personal_bills to authenticated;

-- Para projetos novos, inclui comprovantes de pagamentos.
-- Atualização aditiva: preserva contas e históricos já cadastrados.
begin;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('personal-receipts','personal-receipts',false,3145728,array['image/jpeg','image/png','image/webp','application/pdf'])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;
drop policy if exists personal_receipts_insert on storage.objects;
create policy personal_receipts_insert on storage.objects for insert to authenticated with check(bucket_id='personal-receipts' and (storage.foldername(name))[1]=(select auth.uid())::text);
drop policy if exists personal_receipts_select on storage.objects;
create policy personal_receipts_select on storage.objects for select to authenticated using(bucket_id='personal-receipts' and (storage.foldername(name))[1]=(select auth.uid())::text);
drop policy if exists personal_receipts_delete on storage.objects;
create policy personal_receipts_delete on storage.objects for delete to authenticated using(bucket_id='personal-receipts' and (storage.foldername(name))[1]=(select auth.uid())::text and not exists(select 1 from public.personal_bills b cross join lateral jsonb_array_elements(b.payment_log) l where b.user_id=(select auth.uid()) and l->>'receipt'=name));
-- A chamada antiga de três argumentos continua válida pelo valor padrão do quarto.
drop function if exists public.personal_pay_bill(uuid,numeric,date);
create or replace function public.personal_pay_bill(p_bill uuid,p_amount numeric,p_date date,p_receipt text default null)
returns void language plpgsql security definer set search_path='' as $$
declare b public.personal_bills%rowtype;item jsonb;uid uuid:=auth.uid();begin
 select * into b from public.personal_bills where id=p_bill and user_id=uid for update;
 if not found then raise exception 'Conta não encontrada';end if;
 if p_amount is null or p_amount::text in ('NaN','Infinity','-Infinity') or p_amount<=0 or p_amount<>round(p_amount,2) or p_amount>b.amount-b.paid or p_date is null or p_date>(now() at time zone 'America/Sao_Paulo')::date then raise exception 'Pagamento inválido';end if;
 if p_receipt is not null and (split_part(p_receipt,'/',1)<>uid::text or not exists(select 1 from storage.objects where bucket_id='personal-receipts' and name=p_receipt)) then raise exception 'Comprovante inválido';end if;
 item:=jsonb_build_object('amount',p_amount,'date',p_date);
 if p_receipt is not null then item:=item||jsonb_build_object('receipt',p_receipt);end if;
 update public.personal_bills set paid=paid+p_amount,payment_log=payment_log||jsonb_build_array(item) where id=p_bill;
end $$;
revoke all on function public.personal_pay_bill(uuid,numeric,date,text) from public,anon;
grant execute on function public.personal_pay_bill(uuid,numeric,date,text) to authenticated;
commit;


create or replace function public.personal_attach_receipt(p_bill uuid,p_index integer,p_receipt text)
returns void language plpgsql security definer set search_path='' as $$
declare b public.personal_bills%rowtype;uid uuid:=auth.uid();begin
 select * into b from public.personal_bills where id=p_bill and user_id=uid for update;
 if not found then raise exception 'Conta não encontrada';end if;
 if p_index is null or p_index<0 or p_index>=jsonb_array_length(b.payment_log) or b.payment_log->p_index->>'receipt' is not null then raise exception 'Pagamento inválido ou já possui comprovante';end if;
 if p_receipt is null or split_part(p_receipt,'/',1)<>uid::text or not exists(select 1 from storage.objects where bucket_id='personal-receipts' and name=p_receipt) then raise exception 'Comprovante inválido';end if;
 update public.personal_bills set payment_log=jsonb_set(payment_log,array[p_index::text,'receipt'],to_jsonb(p_receipt),true) where id=p_bill;
end $$;
revoke all on function public.personal_attach_receipt(uuid,integer,text) from public,anon;
grant execute on function public.personal_attach_receipt(uuid,integer,text) to authenticated;

-- Permite excluir somente contas do próprio usuário. Não registra pagamento.
begin;
grant delete on public.personal_bills to authenticated;
drop policy if exists bills_delete on public.personal_bills;
create policy bills_delete on public.personal_bills
for delete to authenticated using (user_id = (select auth.uid()));
commit;

-- Exclusão somente dos compromissos do próprio usuário.
begin;
grant delete on public.personal_events to authenticated;
drop policy if exists events_delete on public.personal_events;
create policy events_delete on public.personal_events
for delete to authenticated using (user_id = (select auth.uid()));
commit;
