-- Tally demo only: replace the old May-July sample with a complete 12-month sample.
-- Period: 2025-11-01 through 2026-10-31 / closed Sundays / 960 paid checks.
do $$
declare
  target_store constant uuid := 'e92756fd-5387-4682-b159-7db05425adf4';
  old_marker constant text := '[TALLY-SAMPLE-MAY-JUL-2026]';
  marker constant text := '[TALLY-SAMPLE-12M-2025-11-2026-10]';
  staff_ids uuid[];
  staff_names text[];
  staff_count integer;
  table_ids uuid[];
  table_count integer;
  charge_id uuid; charge_category text; charge_price integer;
  beer_id uuid; beer_name text; beer_category text; beer_price integer;
  whisky_id uuid; whisky_name text; whisky_category text; whisky_price integer;
  cocktail_id uuid; cocktail_name text; cocktail_category text; cocktail_price integer;
  food_id uuid; food_name text; food_category text; food_price integer;
  high_id uuid; high_category text; high_price integer; high_back integer;
  shot_id uuid; shot_category text; shot_price integer; shot_back integer;
  d date;
  first_open_day date;
  day_no integer := 0;
  sale_no integer := 0;
  sales_today integer;
  i integer;
  j integer;
  check_no bigint;
  check_id uuid;
  guests integer;
  beer_qty integer;
  whisky_qty integer;
  cocktail_qty integer;
  food_qty integer;
  high_qty integer;
  shot_qty integer;
  total integer;
  paid_time timestamptz;
  clock_in_time timestamptz;
  clock_out_time timestamptz;
  selected_staff integer;
begin
  if not exists(select 1 from public.stores where id=target_store and name ilike '%demo%') then
    raise exception 'Tally demo store was not found; no data was changed';
  end if;

  select array_agg(id order by display_order,name),array_agg(name order by display_order,name),count(*)
    into staff_ids,staff_names,staff_count
  from public.staff where store_id=target_store and enabled;
  if staff_count <> 4 then
    raise exception 'Expected exactly 4 active staff, found %',staff_count;
  end if;
  if exists(select 1 from public.checks where store_id=target_store and memo=marker) then
    raise exception '12-month sample already exists; no data was changed';
  end if;

  select array_agg(id order by display_order,name),count(*)
    into table_ids,table_count
  from public.bar_tables where store_id=target_store and enabled;
  if table_count = 0 then raise exception 'No enabled tables found'; end if;

  select p.id,c.name,p.price into charge_id,charge_category,charge_price
  from public.products p join public.categories c on c.id=p.category_id
  where p.store_id=target_store and p.name='チャージ' and p.enabled limit 1;
  select p.id,p.name,c.name,p.price into beer_id,beer_name,beer_category,beer_price
  from public.products p join public.categories c on c.id=p.category_id
  where p.store_id=target_store and p.name='生ビール' and p.enabled limit 1;
  select p.id,p.name,c.name,p.price into whisky_id,whisky_name,whisky_category,whisky_price
  from public.products p join public.categories c on c.id=p.category_id
  where p.store_id=target_store and p.name='ハイボール' and p.enabled limit 1;
  select p.id,p.name,c.name,p.price into cocktail_id,cocktail_name,cocktail_category,cocktail_price
  from public.products p join public.categories c on c.id=p.category_id
  where p.store_id=target_store and p.name='カシスオレンジ' and p.enabled limit 1;
  select p.id,p.name,c.name,p.price into food_id,food_name,food_category,food_price
  from public.products p join public.categories c on c.id=p.category_id
  where p.store_id=target_store and p.name='ミックスナッツ' and p.enabled limit 1;
  select p.id,c.name,p.price,p.back_amount into high_id,high_category,high_price,high_back
  from public.products p join public.categories c on c.id=p.category_id
  where p.store_id=target_store and p.name='ハイ' and p.staff_drink_enabled and p.enabled limit 1;
  select p.id,c.name,p.price,p.back_amount into shot_id,shot_category,shot_price,shot_back
  from public.products p join public.categories c on c.id=p.category_id
  where p.store_id=target_store and p.name='ショット' and p.staff_drink_enabled and p.enabled limit 1;
  if charge_id is null or beer_id is null or whisky_id is null or cocktail_id is null
     or food_id is null or high_id is null or shot_id is null then
    raise exception 'Required products are missing; no sample data was created';
  end if;

  -- Remove only the prior generated sample and its dependent rows.
  delete from public.receivables r using public.checks c
    where r.check_id=c.id and c.store_id=target_store and c.memo=old_marker;
  delete from public.payments p using public.checks c
    where p.check_id=c.id and c.store_id=target_store and c.memo=old_marker;
  delete from public.check_lines l using public.checks c
    where l.check_id=c.id and c.store_id=target_store and c.memo=old_marker;
  delete from public.checks
    where store_id=target_store and memo=old_marker;
  -- Remove only attendance belonging to disabled staff from the old sample period.
  -- Current/enabled staff attendance and all attendance outside that period are preserved.
  delete from public.attendance_records a
    where a.store_id=target_store
      and a.business_date between date '2026-05-01' and date '2026-07-31'
      and exists (
        select 1 from public.staff s
        where s.store_id=target_store and not s.enabled
          and (s.id=a.staff_id or s.name=a.staff_name)
      );

  select coalesce(max(check_number),0) into check_no
  from public.checks where store_id=target_store;

  for d in select generate_series(date '2025-11-01',date '2026-10-31',interval '1 day')::date loop
    if extract(isodow from d) <> 7 then
      day_no := day_no + 1;
      sales_today := 3 + case when day_no <= 21 then 1 else 0 end;

      -- All currently enabled staff work, with slightly staggered 19:00-27:00 shifts.
      for j in 1..staff_count loop
        clock_in_time := ((d + time '19:00') + ((j-1)*interval '10 minutes')) at time zone 'Asia/Tokyo';
        clock_out_time := (((d+1) + time '02:00') + ((j-1)*interval '10 minutes')) at time zone 'Asia/Tokyo';
        insert into public.attendance_records(
          store_id,staff_id,staff_name,business_date,clock_in,clock_out,created_at,updated_at
        ) values(
          target_store,staff_ids[j],staff_names[j],d,clock_in_time,clock_out_time,clock_in_time,clock_out_time
        );
      end loop;

      first_open_day := date_trunc('month',d)::date;
      if extract(isodow from first_open_day)=7 then first_open_day:=first_open_day+1; end if;

      for i in 1..sales_today loop
        sale_no := sale_no + 1;
        check_no := check_no + 1;
        guests := 2 + ((sale_no+i) % 4);
        beer_qty := 1 + (sale_no % 4);
        whisky_qty := 2 + ((sale_no+i) % 5);
        cocktail_qty := 1 + ((sale_no+2*i) % 4);
        food_qty := 1 + (sale_no % 2);
        high_qty := case sale_no % 5 when 0 then 0 when 1 then 2 when 2 then 3 when 3 then 1 else 4 end;
        shot_qty := case sale_no % 6 when 0 then 3 when 1 then 0 when 2 then 1 when 3 then 2 when 4 then 0 else 1 end;
        total := charge_price*guests + beer_price*beer_qty + whisky_price*whisky_qty
          + cocktail_price*cocktail_qty + food_price*food_qty
          + high_price*high_qty + shot_price*shot_qty;
        paid_time := ((d + time '20:20') + ((i-1)*interval '105 minutes')) at time zone 'Asia/Tokyo';

        insert into public.checks(
          store_id,table_id,check_number,business_date,status,customer_name,guest_count,memo,
          subtotal,discount_amount,tax_amount,total_amount,opened_at,paid_at
        ) values(
          target_store,table_ids[((sale_no-1)%table_count)+1],check_no,d,'paid',
          '来店客' || ((sale_no-1)%80+1),guests,marker,total,0,0,total,
          paid_time-interval '85 minutes',paid_time
        ) returning id into check_id;

        insert into public.check_lines(
          check_id,kind,product_id,product_name,category_name,unit_price,tax_rate,quantity,back_amount,created_at
        ) values
          (check_id,'product',charge_id,'チャージ',charge_category,charge_price,0,guests,0,paid_time-interval '80 minutes'),
          (check_id,'product',beer_id,beer_name,beer_category,beer_price,0,beer_qty,0,paid_time-interval '70 minutes'),
          (check_id,'product',whisky_id,whisky_name,whisky_category,whisky_price,0,whisky_qty,0,paid_time-interval '55 minutes'),
          (check_id,'product',cocktail_id,cocktail_name,cocktail_category,cocktail_price,0,cocktail_qty,0,paid_time-interval '40 minutes'),
          (check_id,'product',food_id,food_name,food_category,food_price,0,food_qty,0,paid_time-interval '30 minutes');

        if high_qty > 0 then
          selected_staff := ((sale_no-1)%staff_count)+1;
          insert into public.check_lines(
            check_id,kind,product_id,staff_id,product_name,category_name,staff_name,
            unit_price,tax_rate,quantity,back_amount,created_at
          ) values(
            check_id,'staff_drink',high_id,staff_ids[selected_staff],'ハイ',high_category,
            staff_names[selected_staff],high_price,0,high_qty,high_back,paid_time-interval '25 minutes'
          );
        end if;
        if shot_qty > 0 then
          selected_staff := (sale_no%staff_count)+1;
          insert into public.check_lines(
            check_id,kind,product_id,staff_id,product_name,category_name,staff_name,
            unit_price,tax_rate,quantity,back_amount,created_at
          ) values(
            check_id,'staff_drink',shot_id,staff_ids[selected_staff],'ショット',shot_category,
            staff_names[selected_staff],shot_price,0,shot_qty,shot_back,paid_time-interval '15 minutes'
          );
        end if;

        -- One unpaid receivable on the first business day of each month.
        if d=first_open_day and i=1 then
          insert into public.payments(check_id,method,amount,recorded_at)
          values(check_id,'receivable',total,paid_time);
          insert into public.receivables(
            store_id,check_id,debtor_name,amount,memo,due_date,status,created_at,updated_at
          ) values(
            target_store,check_id,'月次売掛 '||to_char(d,'YYYY-MM'),total,marker,d+30,'unpaid',paid_time,paid_time
          );
        else
          insert into public.payments(check_id,method,amount,received_amount,change_amount,recorded_at)
          values(
            check_id,
            case when sale_no%11=0 then 'other'::public.payment_method
                 when sale_no%3=0 then 'qr'::public.payment_method
                 else 'cash'::public.payment_method end,
            total,total,0,paid_time
          );
        end if;
      end loop;
    end if;
  end loop;

  if sale_no <> 960 then raise exception 'Expected 960 checks, generated %',sale_no; end if;
  update public.store_settings
    set next_check_number=greatest(next_check_number,check_no+1),updated_at=now()
    where store_id=target_store;
end $$;

select
  count(*) sample_checks,
  min(business_date) date_from,
  max(business_date) date_to,
  sum(total_amount) total_sales,
  round(avg(total_amount)) average_check
from public.checks
where store_id='e92756fd-5387-4682-b159-7db05425adf4'
  and memo='[TALLY-SAMPLE-12M-2025-11-2026-10]';
