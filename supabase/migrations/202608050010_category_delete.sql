create or replace function public.update_pos_catalog(target_store uuid,catalog_kind text,items jsonb,admin_token text default null)
returns void language plpgsql security definer set search_path=public as $$
declare item jsonb; keep_names text[]:=array[]::text[]; category_id uuid; item_name text;
begin
  if not public.is_store_owner(target_store) and not public.validate_admin_session(target_store,admin_token) then raise exception 'admin authentication required'; end if;
  if catalog_kind not in ('categories','products','tables','staff') or jsonb_typeof(items)<>'array' then raise exception 'invalid catalog data'; end if;
  for item in select value from jsonb_array_elements(items) loop
    item_name:=left(trim(item->>'name'),120);
    if item_name='' then continue; end if;
    keep_names:=array_append(keep_names,item_name);
    if catalog_kind='categories' then
      insert into public.categories(store_id,name,color,display_order,enabled)
      values(target_store,item_name,left(coalesce(nullif(item->>'color',''),'#6b7280'),20),array_length(keep_names,1)*10,true)
      on conflict(store_id,name) do update set color=excluded.color,display_order=excluded.display_order,enabled=true,updated_at=now();
    elsif catalog_kind='products' then
      select id into category_id from public.categories where store_id=target_store and name=coalesce(nullif(trim(item->>'category'),''),'その他') limit 1;
      if category_id is null then select id into category_id from public.categories where store_id=target_store and enabled order by display_order limit 1; end if;
      insert into public.products(store_id,category_id,name,price,display_order,enabled)
      values(target_store,category_id,item_name,greatest(0,coalesce((item->>'price')::integer,0)),array_length(keep_names,1)*10,true)
      on conflict(store_id,name) do update set category_id=excluded.category_id,price=excluded.price,display_order=excluded.display_order,enabled=true,updated_at=now();
    elsif catalog_kind='tables' then
      insert into public.bar_tables(store_id,name,table_number,display_order,enabled)
      values(target_store,item_name,left(coalesce(item->>'tableNumber',''),40),array_length(keep_names,1)*10,true)
      on conflict(store_id,name) do update set table_number=excluded.table_number,display_order=excluded.display_order,enabled=true,updated_at=now();
    else
      insert into public.staff(store_id,name,display_order,enabled)
      values(target_store,left(item_name,80),array_length(keep_names,1)*10,true)
      on conflict(store_id,name) do update set display_order=excluded.display_order,enabled=true,updated_at=now();
    end if;
  end loop;
  if catalog_kind='categories' then
    update public.products p set enabled=false,updated_at=now()
    where p.store_id=target_store and p.enabled and exists(
      select 1 from public.categories c where c.id=p.category_id and not(c.name=any(keep_names))
    );
    update public.categories c set enabled=false,updated_at=now()
    where c.store_id=target_store and not(c.name=any(keep_names));
  elsif catalog_kind='products' then
    update public.products set enabled=false,updated_at=now() where store_id=target_store and not(name=any(keep_names));
  elsif catalog_kind='tables' then
    update public.bar_tables t set enabled=false,updated_at=now() where t.store_id=target_store and not(t.name=any(keep_names)) and not exists(select 1 from public.checks c where c.table_id=t.id and c.status='open');
  else
    update public.staff set enabled=false,updated_at=now() where store_id=target_store and not(name=any(keep_names));
  end if;
  insert into public.audit_logs(store_id,actor_type,actor_id,action,entity_type,after_data)
  values(target_store,'owner',coalesce(auth.uid()::text,'admin-session'),'catalog_updated',catalog_kind,jsonb_build_object('count',coalesce(array_length(keep_names,1),0)));
end; $$;

revoke all on function public.update_pos_catalog(uuid,text,jsonb,text) from public;
grant execute on function public.update_pos_catalog(uuid,text,jsonb,text) to anon,authenticated;
