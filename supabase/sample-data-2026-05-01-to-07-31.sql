-- Tally demo only: 2026-05-01 through 2026-07-31.
do $$
declare
  target_store constant uuid := 'e92756fd-5387-4682-b159-7db05425adf4';
  marker constant text := '[TALLY-SAMPLE-MAY-JUL-2026]';
  staff_ids uuid[];
  staff_names text[];
  staff_count integer;
  high_id uuid; high_category text; high_price integer; high_back integer;
  shot_id uuid; shot_category text; shot_price integer; shot_back integer;
  charge_id uuid; charge_category text; charge_price integer;
  drink_a_id uuid; drink_a_name text; drink_a_category text; drink_a_price integer;
  drink_b_id uuid; drink_b_name text; drink_b_category text; drink_b_price integer;
  d date;
  day_no integer := 0;
  sale_no integer := 0;
  shift_no integer;
  sales_today integer;
  i integer;
  j integer;
  check_no bigint;
  check_id uuid;
  table_id uuid;
  guests integer;
  high_qty integer;
  shot_qty integer;
  customer_drink_qty integer;
  total integer;
  paid_time timestamptz;
  clock_in_time timestamptz;
  clock_out_time timestamptz;
  selected_staff integer;
begin
  if not exists(select 1 from public.stores where id=target_store and name ilike '%demo%') then
    raise exception 'Tally demo store was not found; no data was changed';
  end if;

  -- Remove the two retired sample staff and their remaining attendance records.
  delete from public.attendance_records
  where store_id=target_store and staff_name=any(array['田中','佐藤']);
  delete from public.staff
  where store_id=target_store and name=any(array['田中','佐藤'])
    and not exists(select 1 from public.check_lines l where l.staff_id=staff.id)
    and not exists(select 1 from public.attendance_records a where a.staff_id=staff.id);

  if exists(select 1 from public.checks where store_id=target_store and memo=marker) then
    raise notice 'May-July sample data already exists; skipped';
    return;
  end if;

  select array_agg(id order by display_order,name),array_agg(name order by display_order,name),count(*)
    into staff_ids,staff_names,staff_count
  from public.staff where store_id=target_store and enabled;
  if staff_count <> 4 then
    raise exception 'Expected exactly 4 active staff, found %',staff_count;
  end if;

  select p.id,c.name,p.price,p.back_amount into high_id,high_category,high_price,high_back
  from public.products p join public.categories c on c.id=p.category_id
  where p.store_id=target_store and p.name='ハイ' and p.staff_drink_enabled and p.enabled limit 1;
  select p.id,c.name,p.price,p.back_amount into shot_id,shot_category,shot_price,shot_back
  from public.products p join public.categories c on c.id=p.category_id
  where p.store_id=target_store and p.name='ショット' and p.staff_drink_enabled and p.enabled limit 1;
  select p.id,c.name,p.price into charge_id,charge_category,charge_price
  from public.products p join public.categories c on c.id=p.category_id
  where p.store_id=target_store and p.name='チャージ' and p.enabled limit 1;
  select p.id,p.name,c.name,p.price into drink_a_id,drink_a_name,drink_a_category,drink_a_price
  from public.products p join public.categories c on c.id=p.category_id
  where p.store_id=target_store and p.name='ハイボール' and p.enabled limit 1;
  select p.id,p.name,c.name,p.price into drink_b_id,drink_b_name,drink_b_category,drink_b_price
  from public.products p join public.categories c on c.id=p.category_id
  where p.store_id=target_store and p.name='カシスオレンジ' and p.enabled limit 1;
  if high_id is null or shot_id is null or charge_id is null or drink_a_id is null or drink_b_id is null then
    raise exception 'Required products are missing; no sample data was created';
  end if;

  select coalesce(max(check_number),0) into check_no from public.checks where store_id=target_store;

  for d in select generate_series(date '2026-05-01',date '2026-07-31',interval '1 day')::date loop
    if extract(isodow from d) <> 7 then
      day_no := day_no + 1;
      sales_today := 3 + case when day_no <= 3 then 1 else 0 end;

      for i in 1..sales_today loop
        sale_no := sale_no + 1;
        check_no := check_no + 1;
        guests := 1 + ((sale_no+i) % 3);
        customer_drink_qty := guests + (sale_no % 3);
        high_qty := case sale_no % 4 when 0 then 0 when 1 then 2 when 2 then 1 else 3 end;
        shot_qty := case sale_no % 4 when 0 then 2 when 1 then 0 when 2 then 1 else 1 end;
        total := charge_price*guests
          + case when sale_no%2=0 then drink_a_price else drink_b_price end*customer_drink_qty
          + high_price*high_qty + shot_price*shot_qty;
        paid_time := ((d + time '20:10') + ((i-1)*interval '95 minutes')) at time zone 'Asia/Tokyo';

        select id into table_id from public.bar_tables
        where store_id=target_store and enabled
        order by display_order,name
        offset ((sale_no-1) % greatest(1,(select count(*) from public.bar_tables where store_id=target_store and enabled))) limit 1;

        insert into public.checks(
          store_id,table_id,check_number,business_date,status,customer_name,guest_count,memo,
          subtotal,discount_amount,tax_amount,total_amount,opened_at,paid_at
        ) values(
          target_store,table_id,check_no,d,'paid','来店客' || ((sale_no-1)%36+1),guests,marker,
          total,0,0,total,paid_time-interval '70 minutes',paid_time
        ) returning id into check_id;

        insert into public.check_lines(check_id,kind,product_id,product_name,category_name,unit_price,tax_rate,quantity,back_amount,created_at)
        values(check_id,'product',charge_id,'チャージ',charge_category,charge_price,0,guests,0,paid_time-interval '65 minutes');

        if sale_no%2=0 then
          insert into public.check_lines(check_id,kind,product_id,product_name,category_name,unit_price,tax_rate,quantity,back_amount,created_at)
          values(check_id,'product',drink_a_id,drink_a_name,drink_a_category,drink_a_price,0,customer_drink_qty,0,paid_time-interval '50 minutes');
        else
          insert into public.check_lines(check_id,kind,product_id,product_name,category_name,unit_price,tax_rate,quantity,back_amount,created_at)
          values(check_id,'product',drink_b_id,drink_b_name,drink_b_category,drink_b_price,0,customer_drink_qty,0,paid_time-interval '50 minutes');
        end if;

        if high_qty > 0 then
          selected_staff := ((sale_no-1)%4)+1;
          insert into public.check_lines(check_id,kind,product_id,staff_id,product_name,category_name,staff_name,unit_price,tax_rate,quantity,back_amount,created_at)
          values(check_id,'staff_drink',high_id,staff_ids[selected_staff],'ハイ',high_category,staff_names[selected_staff],high_price,0,high_qty,high_back,paid_time-interval '35 minutes');
        end if;
        if shot_qty > 0 then
          selected_staff := (sale_no%4)+1;
          insert into public.check_lines(check_id,kind,product_id,staff_id,product_name,category_name,staff_name,unit_price,tax_rate,quantity,back_amount,created_at)
          values(check_id,'staff_drink',shot_id,staff_ids[selected_staff],'ショット',shot_category,staff_names[selected_staff],shot_price,0,shot_qty,shot_back,paid_time-interval '20 minutes');
        end if;

        if sale_no=any(array[20,65,110,155,220]) then
          insert into public.payments(check_id,method,amount,recorded_at)
          values(check_id,'receivable',total,paid_time);
          insert into public.receivables(store_id,check_id,debtor_name,amount,memo,due_date,status,created_at,updated_at)
          values(target_store,check_id,'売掛客' || array_position(array[20,65,110,155,220],sale_no),total,marker,d+30,'unpaid',paid_time,paid_time);
        else
          insert into public.payments(check_id,method,amount,received_amount,change_amount,recorded_at)
          values(check_id,case when sale_no%7=0 then 'other'::public.payment_method when sale_no%3=0 then 'qr'::public.payment_method else 'cash'::public.payment_method end,total,total,0,paid_time);
        end if;
      end loop;

      shift_no := 2 + (day_no % 3);
      for j in 1..shift_no loop
        selected_staff := ((day_no+j-2)%4)+1;
        clock_in_time := ((d + time '19:00') + ((j-1)*interval '15 minutes')) at time zone 'Asia/Tokyo';
        clock_out_time := (((d+1) + time '01:20') + ((j-1)*interval '30 minutes')) at time zone 'Asia/Tokyo';
        insert into public.attendance_records(store_id,staff_id,staff_name,business_date,clock_in,clock_out,created_at,updated_at)
        values(target_store,staff_ids[selected_staff],staff_names[selected_staff],d,clock_in_time,clock_out_time,clock_in_time,clock_out_time);
      end loop;
    end if;
  end loop;

  if sale_no <> 240 then raise exception 'Expected 240 checks, generated %',sale_no; end if;
  update public.store_settings set next_check_number=greatest(next_check_number,check_no+1),updated_at=now()
  where store_id=target_store;
end $$;

select
  (select count(*) from public.checks where store_id='e92756fd-5387-4682-b159-7db05425adf4' and memo='[TALLY-SAMPLE-MAY-JUL-2026]') sample_checks,
  (select min(business_date) from public.checks where store_id='e92756fd-5387-4682-b159-7db05425adf4' and memo='[TALLY-SAMPLE-MAY-JUL-2026]') date_from,
  (select max(business_date) from public.checks where store_id='e92756fd-5387-4682-b159-7db05425adf4' and memo='[TALLY-SAMPLE-MAY-JUL-2026]') date_to,
  (select count(*) from public.receivables where store_id='e92756fd-5387-4682-b159-7db05425adf4' and memo='[TALLY-SAMPLE-MAY-JUL-2026]' and status='unpaid') unpaid_receivables,
  (select count(*) from public.staff where store_id='e92756fd-5387-4682-b159-7db05425adf4' and enabled) active_staff,
  (select count(*) from public.staff where store_id='e92756fd-5387-4682-b159-7db05425adf4' and name=any(array['田中','佐藤'])) retired_staff,
  (select count(*) from public.attendance_records where store_id='e92756fd-5387-4682-b159-7db05425adf4' and business_date between date '2026-05-01' and date '2026-07-31') shifts,
  (select coalesce(sum(quantity),0) from public.check_lines l join public.checks c on c.id=l.check_id where c.store_id='e92756fd-5387-4682-b159-7db05425adf4' and c.memo='[TALLY-SAMPLE-MAY-JUL-2026]' and l.kind='staff_drink' and l.product_name='ハイ') high_count,
  (select coalesce(sum(quantity),0) from public.check_lines l join public.checks c on c.id=l.check_id where c.store_id='e92756fd-5387-4682-b159-7db05425adf4' and c.memo='[TALLY-SAMPLE-MAY-JUL-2026]' and l.kind='staff_drink' and l.product_name='ショット') shot_count;
