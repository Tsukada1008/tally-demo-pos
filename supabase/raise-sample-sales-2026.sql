-- Raise only the May-July 2026 Tally demo sample sales. Safe to run once.
do $$
declare
  target_store constant uuid := 'e92756fd-5387-4682-b159-7db05425adf4';
  marker constant text := '[TALLY-SAMPLE-MAY-JUL-2026]';
  selected_check record;
  add_amount integer;
  add_name text;
begin
  if exists(
    select 1 from public.check_lines l
    join public.checks c on c.id=l.check_id
    where c.store_id=target_store and c.memo=marker and l.category_name='サンプル追加売上'
  ) then
    raise notice 'Additional sample sales already exist; skipped';
    return;
  end if;

  for selected_check in
    select id,check_number from public.checks
    where store_id=target_store and memo=marker
    order by business_date,check_number
  loop
    case selected_check.check_number % 3
      when 0 then add_amount:=12000; add_name:='スタンダードボトル';
      when 1 then add_amount:=18000; add_name:='プレミアムボトル';
      else add_amount:=25000; add_name:='シャンパン';
    end case;

    insert into public.check_lines(
      check_id,kind,product_name,category_name,unit_price,tax_rate,quantity,back_amount,created_at
    )
    select selected_check.id,'product',add_name,'サンプル追加売上',add_amount,0,1,0,
      coalesce(c.paid_at,c.opened_at)+interval '5 minutes'
    from public.checks c where c.id=selected_check.id;

    update public.checks
    set subtotal=subtotal+add_amount,total_amount=total_amount+add_amount,updated_at=now()
    where id=selected_check.id;

    update public.payments
    set amount=amount+add_amount,
      received_amount=case when received_amount is null then null else received_amount+add_amount end
    where check_id=selected_check.id;

    update public.receivables
    set amount=amount+add_amount,updated_at=now()
    where check_id=selected_check.id;
  end loop;
end $$;

select
  to_char(c.business_date,'YYYY-MM') month_key,
  count(*) checks,
  sum(c.total_amount) sales,
  round(avg(c.total_amount)) average_check
from public.checks c
where c.store_id='e92756fd-5387-4682-b159-7db05425adf4'
  and c.memo='[TALLY-SAMPLE-MAY-JUL-2026]'
group by to_char(c.business_date,'YYYY-MM')
order by month_key;
