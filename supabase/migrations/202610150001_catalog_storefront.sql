-- Lakab Dashboard / GOBSTORE catalog access.
-- Matches the existing production UUID schema and adds the fields required by
-- dashboard uploads and storefront product cards. Safe to re-run.

-- Existing production stores already have id, name, slug, owner_whatsapp and
-- status. Keep those types and names; add dashboard ownership and optional
-- dashboard metadata without replacing existing data.
alter table public.stores
    add column if not exists owner_id uuid references auth.users(id) on delete set null,
    add column if not exists city text,
    add column if not exists manager text,
    add column if not exists phone text,
    add column if not exists created_at timestamptz not null default now();

-- Existing production garments have UUID id, UUID store_id referencing
-- stores(id), title/category text, price numeric, image_url/model_3d_url text,
-- and is_active boolean. Add the optional catalog and try-on fields used by
-- the dashboard/storefront. Preserve the legacy model_3d_url column.
alter table public.garments
    add column if not exists description text not null default '',
    add column if not exists image_urls jsonb not null default '[]'::jsonb,
    add column if not exists try_on_enabled boolean not null default true,
    add column if not exists ar_ready boolean not null default true,
    add column if not exists anywear_model_id text,
    add column if not exists shop_id uuid,
    add column if not exists name text,
    add column if not exists created_at timestamptz not null default now(),
    add column if not exists updated_at timestamptz not null default now();

update public.garments
set image_urls = jsonb_build_array(image_url)
where image_url is not null and image_urls = '[]'::jsonb;

update public.garments
set name = title
where name is null and title is not null;

update public.garments
set shop_id = store_id
where shop_id is null;

create index if not exists garments_store_active_created_idx
    on public.garments (store_id, is_active, created_at desc);

-- Public visitors can discover stores and read active catalog items. Store
-- owners can also read their own rows, including inactive garments.
alter table public.stores enable row level security;
alter table public.garments enable row level security;

drop policy if exists "stores public read" on public.stores;
create policy "stores public read" on public.stores
    for select to anon, authenticated using (true);

drop policy if exists "stores owner insert" on public.stores;
create policy "stores owner insert" on public.stores
    for insert to authenticated
    with check (owner_id = (select auth.uid()));

drop policy if exists "stores owner update" on public.stores;
create policy "stores owner update" on public.stores
    for update to authenticated
    using (owner_id = (select auth.uid()))
    with check (owner_id = (select auth.uid()));

drop policy if exists "stores owner delete" on public.stores;
create policy "stores owner delete" on public.stores
    for delete to authenticated
    using (owner_id = (select auth.uid()));

-- Restrictive write guards also prevent legacy permissive anon-write policies
-- from granting access. The dashboard must use a signed-in owner session.
drop policy if exists "stores insert requires owner auth" on public.stores;
create policy "stores insert requires owner auth" on public.stores as restrictive
    for insert to anon, authenticated
    with check (auth.uid() is not null and owner_id = (select auth.uid()));
drop policy if exists "stores update requires owner auth" on public.stores;
create policy "stores update requires owner auth" on public.stores as restrictive
    for update to anon, authenticated
    using (auth.uid() is not null and owner_id = (select auth.uid()))
    with check (auth.uid() is not null and owner_id = (select auth.uid()));
drop policy if exists "stores delete requires owner auth" on public.stores;
create policy "stores delete requires owner auth" on public.stores as restrictive
    for delete to anon, authenticated
    using (auth.uid() is not null and owner_id = (select auth.uid()));

drop policy if exists "garments active public read" on public.garments;
create policy "garments active public read" on public.garments
    for select to anon, authenticated using (is_active is true);

drop policy if exists "garments owner read" on public.garments;
create policy "garments owner read" on public.garments
    for select to authenticated
    using (exists (
        select 1 from public.stores s
        where s.id = garments.store_id and s.owner_id = (select auth.uid())
    ));

drop policy if exists "garments owner insert" on public.garments;
create policy "garments owner insert" on public.garments
    for insert to authenticated
    with check (exists (
        select 1 from public.stores s
        where s.id = garments.store_id and s.owner_id = (select auth.uid())
    ));

drop policy if exists "garments owner update" on public.garments;
create policy "garments owner update" on public.garments
    for update to authenticated
    using (exists (
        select 1 from public.stores s
        where s.id = garments.store_id and s.owner_id = (select auth.uid())
    ))
    with check (exists (
        select 1 from public.stores s
        where s.id = garments.store_id and s.owner_id = (select auth.uid())
    ));

drop policy if exists "garments owner delete" on public.garments;
create policy "garments owner delete" on public.garments
    for delete to authenticated
    using (exists (
        select 1 from public.stores s
        where s.id = garments.store_id and s.owner_id = (select auth.uid())
    ));

drop policy if exists "garments insert requires owner auth" on public.garments;
create policy "garments insert requires owner auth" on public.garments as restrictive
    for insert to anon, authenticated
    with check (
        auth.uid() is not null and exists (
            select 1 from public.stores s
            where s.id = garments.store_id and s.owner_id = (select auth.uid())
        )
    );

drop policy if exists "garments update requires owner auth" on public.garments;
create policy "garments update requires owner auth" on public.garments as restrictive
    for update to anon, authenticated
    using (
        auth.uid() is not null and exists (
            select 1 from public.stores s
            where s.id = garments.store_id and s.owner_id = (select auth.uid())
        )
    )
    with check (
        auth.uid() is not null and exists (
            select 1 from public.stores s
            where s.id = garments.store_id and s.owner_id = (select auth.uid())
        )
    );

drop policy if exists "garments delete requires owner auth" on public.garments;
create policy "garments delete requires owner auth" on public.garments as restrictive
    for delete to anon, authenticated
    using (
        auth.uid() is not null and exists (
            select 1 from public.stores s
            where s.id = garments.store_id and s.owner_id = (select auth.uid())
        )
    );

-- Public image delivery uses a public bucket. Upload/update/delete are limited
-- to the authenticated owner of the store folder: {store_id}/{filename}.
insert into storage.buckets (id, name, public)
values ('garment-images', 'garment-images', true)
on conflict (id) do update set public = excluded.public;

drop policy if exists "garment images public read" on storage.objects;
create policy "garment images public read" on storage.objects
    for select to anon, authenticated
    using (bucket_id = 'garment-images');

drop policy if exists "garment images owner insert" on storage.objects;
create policy "garment images owner insert" on storage.objects
    for insert to authenticated
    with check (
        bucket_id = 'garment-images' and exists (
            select 1 from public.stores s
            where s.id::text = split_part(name, '/', 1)
              and s.owner_id = (select auth.uid())
        )
    );

drop policy if exists "garment images owner update" on storage.objects;
create policy "garment images owner update" on storage.objects
    for update to authenticated
    using (
        bucket_id = 'garment-images' and exists (
            select 1 from public.stores s
            where s.id::text = split_part(name, '/', 1)
              and s.owner_id = (select auth.uid())
        )
    )
    with check (
        bucket_id = 'garment-images' and exists (
            select 1 from public.stores s
            where s.id::text = split_part(name, '/', 1)
              and s.owner_id = (select auth.uid())
        )
    );

drop policy if exists "garment images owner delete" on storage.objects;
create policy "garment images owner delete" on storage.objects
    for delete to authenticated
    using (
        bucket_id = 'garment-images' and exists (
            select 1 from public.stores s
            where s.id::text = split_part(name, '/', 1)
              and s.owner_id = (select auth.uid())
        )
    );
