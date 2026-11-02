-- Pinguin LA | Execute no SQL Editor do seu projeto Supabase.
-- Valores em reais, com duas casas. Juros simples lançados uma vez por período.
create table if not exists public.debts (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references auth.users(id) on delete cascade default auth.uid(),
 name text not null check (length(trim(name)) between 1 and 100),
 phone text not null default '', description text not null default '',
 principal numeric(14,2) not null check (principal>=0),
 interest numeric(14,2) not null default 0 check (interest>=0),
 rate numeric(9,2) not null default 0 check(rate between 0 and 1000),
 due date not null, created_at timestamptz not null default now()
);
create table if not exists public.payments (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references auth.users(id) on delete cascade,
 debt_id uuid not null references public.debts(id),
 kind text not null check(kind in ('partial','interest','settle')),
 principal_paid numeric(14,2) not null check(principal_paid>=0),
 interest_paid numeric(14,2) not null check(interest_paid>=0),
 paid_on date not null, note text not null default '', receipt_path text,
 created_at timestamptz not null default now(),
 check(principal_paid+interest_paid>0)
);
create table if not exists public.renewals (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references auth.users(id) on delete cascade,
 debt_id uuid not null references public.debts(id),
 previous_due date not null, new_due date not null,
 interest_added numeric(14,2) not null check(interest_added>=0),
 created_at timestamptz not null default now()
);
alter table public.debts enable row level security;
alter table public.payments enable row level security;
alter table public.renewals enable row level security;
drop policy if exists debts_read on public.debts;
create policy debts_read on public.debts for select to authenticated using(user_id=(select auth.uid()));
drop policy if exists debts_insert on public.debts;
create policy debts_insert on public.debts for insert to authenticated with check(user_id=(select auth.uid()));
drop policy if exists payments_read on public.payments;
create policy payments_read on public.payments for select to authenticated using(user_id=(select auth.uid()));
drop policy if exists renewals_read on public.renewals;
create policy renewals_read on public.renewals for select to authenticated using(user_id=(select auth.uid()));
revoke all on public.debts,public.payments,public.renewals from anon,authenticated;
grant select,insert on public.debts to authenticated;
grant select on public.payments,public.renewals to authenticated;
create index if not exists debts_owner_due on public.debts(user_id,due);
create index if not exists payments_owner_debt on public.payments(user_id,debt_id);
-- Uma transação e um bloqueio por dívida evitam pagamentos simultâneos excedentes.
create or replace function public.record_payment(p_debt uuid,p_kind text,p_principal numeric,p_interest numeric,p_date date,p_note text default '',p_receipt text default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare d public.debts%rowtype; new_id uuid; uid uuid:=auth.uid();
begin
 if uid is null then raise exception 'Entre na sua conta.'; end if;
 select * into d from public.debts where id=p_debt and user_id=uid for update;
 if not found then raise exception 'Dívida não encontrada.'; end if;
 if p_principal is null or p_interest is null or p_principal::text in ('NaN','Infinity','-Infinity') or p_interest::text in ('NaN','Infinity','-Infinity') or p_principal<>round(p_principal,2) or p_interest<>round(p_interest,2) or p_principal<0 or p_interest<0 or p_principal+p_interest<=0 or p_principal>d.principal or p_interest>d.interest then raise exception 'Valores inválidos ou superiores ao saldo.'; end if;
 if p_kind is null or p_kind not in ('partial','interest','settle') then raise exception 'Tipo de pagamento inválido.'; end if;
 if p_kind='interest' and (p_principal<>0 or p_interest<>d.interest) then raise exception 'Informe somente os juros em aberto.'; end if;
 if p_kind='settle' and (p_principal<>d.principal or p_interest<>d.interest) then raise exception 'A quitação exige o saldo integral atualizado.'; end if;
 if p_date is null or p_date>(now() at time zone 'America/Sao_Paulo')::date then raise exception 'Data de pagamento inválida.'; end if;
 if length(coalesce(p_note,''))>500 then raise exception 'Observação muito longa.'; end if;
 if p_receipt is not null and (split_part(p_receipt,'/',1)<>uid::text or not exists(select 1 from storage.objects where bucket_id='receipts' and name=p_receipt)) then raise exception 'Comprovante inválido.'; end if;
 update public.debts set principal=principal-p_principal,interest=interest-p_interest where id=p_debt;
 insert into public.payments(user_id,debt_id,kind,principal_paid,interest_paid,paid_on,note,receipt_path) values(uid,p_debt,p_kind,p_principal,p_interest,p_date,coalesce(p_note,''),p_receipt) returning id into new_id;
 return new_id;
end $$;
create or replace function public.renew_debt(p_debt uuid,p_due date,p_interest numeric default 0)
returns void language plpgsql security definer set search_path='' as $$
declare d public.debts%rowtype; uid uuid:=auth.uid();
begin
 if uid is null then raise exception 'Entre na sua conta.'; end if;
 select * into d from public.debts where id=p_debt and user_id=uid for update;
 if not found then raise exception 'Dívida não encontrada.'; end if;
 if d.principal+d.interest<=0 then raise exception 'Dívida já quitada.'; end if;
 if p_due is null or p_interest is null or p_interest::text in ('NaN','Infinity','-Infinity') or p_interest<0 or p_interest>99999999 or p_interest<>round(p_interest,2) then raise exception 'Dados de renovação inválidos.'; end if;
 insert into public.renewals(user_id,debt_id,previous_due,new_due,interest_added) values(uid,p_debt,d.due,p_due,p_interest);
 update public.debts set due=p_due,interest=interest+p_interest where id=p_debt;
end $$;
revoke all on function public.record_payment(uuid,text,numeric,numeric,date,text,text) from public,anon;
revoke all on function public.renew_debt(uuid,date,numeric) from public,anon;
grant execute on function public.record_payment(uuid,text,numeric,numeric,date,text,text) to authenticated;
grant execute on function public.renew_debt(uuid,date,numeric) to authenticated;
-- Comprovantes privados, sem URL pública; abertura via URL assinada por 60 segundos.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('receipts','receipts',false,3145728,array['image/jpeg','image/png','image/webp','application/pdf']) on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;
drop policy if exists receipts_insert on storage.objects;
create policy receipts_insert on storage.objects for insert to authenticated with check(bucket_id='receipts' and (storage.foldername(name))[1]=(select auth.uid())::text);
drop policy if exists receipts_select on storage.objects;
create policy receipts_select on storage.objects for select to authenticated using(bucket_id='receipts' and (storage.foldername(name))[1]=(select auth.uid())::text);
drop policy if exists receipts_delete on storage.objects;
create policy receipts_delete on storage.objects for delete to authenticated using(bucket_id='receipts' and (storage.foldername(name))[1]=(select auth.uid())::text and not exists(select 1 from public.payments where receipt_path=name));
