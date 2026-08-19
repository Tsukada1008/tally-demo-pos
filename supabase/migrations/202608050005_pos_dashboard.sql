insert into public.products(store_id,category_id,name,price,display_order,staff_drink_enabled)
select c.store_id,c.id,v.name,v.price,v.ord,v.staff_drink
from public.categories c
join (values
  ('ビール','生ビール',700,10,false),('ビール','瓶ビール',800,20,false),
  ('ウイスキー','ハイボール',800,10,false),('ウイスキー','山崎ハイボール',1200,20,false),
  ('焼酎','レモンサワー',700,10,false),('焼酎','ウーロンハイ',700,20,false),
  ('カクテル','ジントニック',900,10,false),('カクテル','カシスオレンジ',900,20,false),
  ('セット料金','お通し',500,10,false),('フード','ミックスナッツ',600,10,false),
  ('従業員ドリンク','キャストドリンク',1000,10,true)
) as v(category,name,price,ord,staff_drink) on v.category=c.name
where c.store_id='7369b222-060b-4d44-ac95-1256b32c96c4'
on conflict(store_id,name) do nothing;

create or replace function public.get_pos_dashboard(target_store uuid,raw_token text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare result jsonb; target_day date;
begin
  if not public.validate_pos_session(target_store,raw_token) then raise exception 'invalid or expired device session'; end if;
  target_day:=public.business_date_for(target_store);
  update public.pos_sessions set last_seen_at=now()
  where store_id=target_store and token_hash=encode(extensions.digest(raw_token,'sha256'),'hex');
  select jsonb_build_object(
    'businessDate',target_day,
    'tables',(select coalesce(jsonb_agg(jsonb_build_object('id',t.id,'name',t.name,'tableNumber',t.table_number) order by t.display_order),'[]'::jsonb) from public.bar_tables t where t.store_id=target_store and t.enabled),
    'categories',(select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'name',c.name,'color',c.color) order by c.display_order),'[]'::jsonb) from public.categories c where c.store_id=target_store and c.enabled),
    'products',(select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',p.name,'category',c.name,'price',p.price,'color',c.color,'staffDrink',p.staff_drink_enabled) order by c.display_order,p.display_order),'[]'::jsonb) from public.products p join public.categories c on c.id=p.category_id where p.store_id=target_store and p.enabled),
    'staff',(select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'name',s.name) order by s.display_order,s.name),'[]'::jsonb) from public.staff s where s.store_id=target_store and s.enabled),
    'history',(select coalesce(jsonb_agg(x.item order by x.paid_at desc),'[]'::jsonb) from (select c.paid_at,jsonb_build_object('id',c.id,'number',c.check_number,'table',coalesce(t.name,''),'customer',c.customer_name,'guests',c.guest_count,'total',c.total_amount,'paidAt',c.paid_at,'method',p.method) item from public.checks c left join public.bar_tables t on t.id=c.table_id left join public.payments p on p.check_id=c.id where c.store_id=target_store and c.status='paid' order by c.paid_at desc limit 50)x),
    'summary',(select jsonb_build_object('sales',coalesce(sum(c.total_amount),0),'checks',count(*),'guests',coalesce(sum(c.guest_count),0),'cash',coalesce(sum(c.total_amount) filter(where p.method='cash'),0),'qr',coalesce(sum(c.total_amount) filter(where p.method='qr'),0),'receivable',coalesce(sum(c.total_amount) filter(where p.method='receivable'),0),'other',coalesce(sum(c.total_amount) filter(where p.method='other'),0)) from public.checks c left join public.payments p on p.check_id=c.id where c.store_id=target_store and c.business_date=target_day and c.status='paid')
  ) into result;
  return result;
end; $$;

revoke all on function public.get_pos_dashboard(uuid,text) from public;
grant execute on function public.get_pos_dashboard(uuid,text) to anon,authenticated;
