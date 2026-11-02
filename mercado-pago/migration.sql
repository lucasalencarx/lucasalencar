-- Execute após schema.sql. Integração de conta única: proprietário verificado nas Edge Functions.
begin;
create table if not exists public.mp_requests (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id),
 debt_id uuid not null references public.debts(id), kind text not null check(kind in ('settle','interest')),
 principal numeric(14,2) not null check(principal>=0),interest numeric(14,2) not null check(interest>=0),
 snapshot_principal numeric(14,2) not null,snapshot_interest numeric(14,2) not null,snapshot_due date not null,
 status text not null default 'creating' check(status in ('creating','pending','paid','cancelled','rejected','review')),
 provider_id text unique,provider_status text, payment_id uuid unique references public.payments(id),
 payer jsonb not null,description text not null,qr_code text,qr_base64 text,ticket_url text,
 expires_at timestamptz not null default (now()+interval '24 hours'),
 evidence jsonb,review_reason text,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 check(principal+interest>0)
);
create unique index if not exists mp_one_active_per_debt on public.mp_requests(debt_id) where status in ('creating','pending','review');
alter table public.mp_requests enable row level security;
drop policy if exists mp_owner_read on public.mp_requests;
create policy mp_owner_read on public.mp_requests for select to authenticated using(user_id=(select auth.uid()));
revoke all on public.mp_requests from anon,authenticated;
grant select on public.mp_requests to authenticated;
alter table public.payments add column if not exists provider_receipt jsonb;
alter table public.payments add column if not exists provider_alert text;

create or replace function public.mp_reserve(p_owner uuid,p_debt uuid,p_kind text,p_payer jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare d public.debts%rowtype;r public.mp_requests%rowtype;
begin
 select * into d from public.debts where id=p_debt and user_id=p_owner for update;
 if not found then raise exception 'Dívida não encontrada.';end if;
 select * into r from public.mp_requests where debt_id=d.id and status in ('creating','pending','review') for update;
 if found then
  if r.kind<>p_kind then raise exception 'Já existe um Pix para esta dívida. Consulte ou cancele antes de mudar o tipo.';end if;
  return to_jsonb(r);
 end if;
 if p_kind is null or p_kind not in ('settle','interest') or d.principal+d.interest<=0 or (p_kind='interest' and d.interest<=0) then raise exception 'Valor ou tipo de cobrança inválido.';end if;
 insert into public.mp_requests(user_id,debt_id,kind,principal,interest,snapshot_principal,snapshot_interest,snapshot_due,payer,description)
 values(p_owner,d.id,p_kind,case when p_kind='settle' then d.principal else 0 end,d.interest,d.principal,d.interest,d.due,p_payer,left(coalesce(nullif(d.description,''),'Pagamento de acordo'),200)) returning * into r;
 return to_jsonb(r);
end $$;

-- Só a confirmação consultada na API pelo servidor chega a esta função.
create or replace function public.mp_apply(p_request uuid,p_verified jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.mp_requests%rowtype;d public.debts%rowtype;pid uuid;s text:=p_verified->>'status';amount numeric;refunded numeric;ev jsonb;
begin
 -- Ordem de bloqueio igual a mp_reserve e às operações manuais: dívida, depois cobrança.
 select d0.* into d from public.debts d0 join public.mp_requests r0 on r0.debt_id=d0.id where r0.id=p_request for update of d0;
 if not found then raise exception 'Cobrança não encontrada.';end if;
 select * into r from public.mp_requests where id=p_request for update;
 amount:=(p_verified->>'transaction_amount')::numeric;
 refunded:=coalesce((p_verified->>'transaction_amount_refunded')::numeric,0);
 if (p_verified->>'external_reference') is distinct from r.id::text or p_verified->>'currency_id' is distinct from 'BRL' or p_verified->>'payment_method_id' is distinct from 'pix' or amount is distinct from r.principal+r.interest or p_verified->>'id' is null then raise exception 'Confirmação não corresponde à cobrança.';end if;
 if r.provider_id is not null and r.provider_id<>p_verified->>'id' then raise exception 'Identificador de pagamento divergente.';end if;
 ev:=jsonb_build_object('provider','Mercado Pago','payment_id',p_verified->>'id','request_id',r.id,'status',s,'amount',amount,'principal',r.principal,'interest',r.interest,'approved_at',p_verified->>'date_approved','checked_at',now(),'live_mode',p_verified->'live_mode');
 update public.mp_requests set provider_id=p_verified->>'id',provider_status=s,payer='{}'::jsonb,
 qr_code=coalesce(p_verified#>>'{point_of_interaction,transaction_data,qr_code}',qr_code),
 qr_base64=coalesce(p_verified#>>'{point_of_interaction,transaction_data,qr_code_base64}',qr_base64),
 ticket_url=coalesce(p_verified#>>'{point_of_interaction,transaction_data,ticket_url}',ticket_url),
 evidence=ev,updated_at=now() where id=r.id;
 if s in ('refunded','charged_back') or refunded>0 then
  update public.mp_requests set status='review',review_reason='Estorno/reembolso/contestação: conciliar saldo e valor devolvido manualmente.' where id=r.id;
  if r.payment_id is not null then update public.payments set provider_alert='Reembolso/contestação: conciliação necessária' where id=r.payment_id;end if;
 elsif r.payment_id is not null then
  -- Reenvios não lançam outro pagamento e não removem alertas anteriores.
  null;
 elsif r.status='review' then null;
 elsif s='approved' then
  if d.principal<>r.snapshot_principal or d.interest<>r.snapshot_interest or d.due<>r.snapshot_due then
   update public.mp_requests set status='review',review_reason='Saldo ou acordo alterado após emissão. Pagamento recebido; conciliar antes de abater.' where id=r.id;
  else
   perform set_config('pinguin.mp_settlement','yes',true);
   insert into public.payments(user_id,debt_id,kind,principal_paid,interest_paid,paid_on,note,provider_receipt)
   values(r.user_id,r.debt_id,r.kind,r.principal,r.interest,((p_verified->>'date_approved')::timestamptz at time zone 'America/Sao_Paulo')::date,'Pix confirmado pela API do Mercado Pago',ev) returning id into pid;
   update public.debts set principal=principal-r.principal,interest=interest-r.interest where id=d.id;
   update public.mp_requests set status='paid',payment_id=pid,review_reason=null where id=r.id;
  end if;
 elsif s in ('cancelled','rejected') then update public.mp_requests set status=s where id=r.id;
 else update public.mp_requests set status='pending' where id=r.id;
 end if;
 select * into r from public.mp_requests where id=p_request;
 return to_jsonb(r);
end $$;

-- Não permite baixa manual/renovação concorrente com Pix ativo. Primeiro cancele e confirme no PSP.
create or replace function public.mp_guard_balance() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if (new.principal,new.interest,new.due) is distinct from (old.principal,old.interest,old.due)
 and coalesce(current_setting('pinguin.mp_settlement',true),'')<>'yes'
 and exists(select 1 from public.mp_requests where debt_id=old.id and status in ('creating','pending','review')) then
  raise exception 'Há um Pix ativo ou em revisão. Consulte/cancele no Mercado Pago antes de receber manualmente ou renovar.';
 end if;return new;
end $$;
drop trigger if exists mp_guard_balance on public.debts;
create trigger mp_guard_balance before update on public.debts for each row execute function public.mp_guard_balance();
revoke all on function public.mp_reserve(uuid,uuid,text,jsonb),public.mp_apply(uuid,jsonb),public.mp_guard_balance() from public,anon,authenticated;
grant execute on function public.mp_reserve(uuid,uuid,text,jsonb),public.mp_apply(uuid,jsonb) to service_role;
commit;
