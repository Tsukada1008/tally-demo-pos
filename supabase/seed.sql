-- Replace OWNER_USER_ID after creating the owner in Supabase Auth.
-- Run this once in the SQL editor with the service/database owner role.
do $$
declare
  new_store uuid := gen_random_uuid();
  owner_user uuid := '8ce71c36-c422-4415-a0be-967622f29067';
begin
  insert into public.stores(id,name,address,phone,business_day_cutoff)
  values(new_store,'TIPSY','','','06:00');
  insert into public.store_members(store_id,user_id,role) values(new_store,owner_user,'owner');
  insert into public.store_settings(store_id) values(new_store);
  -- Temporary initial PINs. Change both immediately in the app after first sign-in.
  insert into public.store_secrets(store_id,staff_pin_hash,admin_pin_hash)
  values(new_store,crypt('1234',gen_salt('bf',12)),crypt('5678',gen_salt('bf',12)));

  insert into public.categories(store_id,name,color,display_order) values
    (new_store,'ビール','#e2b93b',10),(new_store,'焼酎','#5c91c7',20),
    (new_store,'ウイスキー','#9a6c4a',30),(new_store,'カクテル','#d4679c',40),
    (new_store,'ソフトドリンク','#3a9b71',50),(new_store,'フード','#db7f39',60),
    (new_store,'セット料金','#8056a5',70),(new_store,'従業員ドリンク','#d5374b',80),
    (new_store,'その他','#737373',90);

  insert into public.bar_tables(store_id,name,table_number,display_order) values
    (new_store,'A卓','A',10),(new_store,'B卓','B',20),(new_store,'C卓','C',30),
    (new_store,'カウンター1','C1',40),(new_store,'カウンター2','C2',50);

  insert into public.discount_presets(store_id,name,kind,value,display_order) values
    (new_store,'500円引き','amount',500,10),(new_store,'1,000円引き','amount',1000,20),
    (new_store,'10％引き','percent',10,30),(new_store,'サービス','service',0,40);
end $$;
