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
