# Shared Supabase catalog setup

The Lakab dashboard and GOBSTORE storefront use the same Supabase project and
`public.garments` table. Apply
[`migrations/202610150001_catalog_storefront.sql`](migrations/202610150001_catalog_storefront.sql)
in the Supabase SQL Editor before deploying the app changes.

## Store owner access

Catalog uploads require a Supabase Auth user. Create the store administrator in
Supabase Auth, then assign existing store rows to that user's UUID from the SQL
Editor. For example:

```sql
select id, email from auth.users;
select id, name from public.stores;

update public.stores
set owner_id = 'AUTH_USER_UUID'
where id = 'STORE_UUID';
```

Each store owner signs into the dashboard under Settings. New stores created
there are assigned to the signed-in user. The migration restricts image uploads
and catalog writes to the owner of the selected store; public storefront reads
are limited to active garments.

## Catalog fields

The migration preserves the production `stores` columns (`id`, `name`, `slug`,
`owner_whatsapp`, `status`) and `garments` columns (`id`, `store_id`, `title`,
`category`, `price`, `image_url`, `model_3d_url`, `is_active`) with their
existing UUID and text/numeric/boolean types. It adds `stores.owner_id` for
dashboard authorization plus optional dashboard metadata. It adds `description`,
`image_urls` (JSON array), `try_on_enabled`, `ar_ready`, `anywear_model_id`,
`name`, `shop_id` (legacy compatibility), and timestamps to garments. Images
are uploaded to the public `garment-images` bucket under
`{store_id}/{filename}`.

RLS is enabled explicitly on `stores` and `garments`. Public and authenticated
visitors can read stores and active garments; authenticated owners can also
read their inactive garments and create, update, or delete rows for stores
assigned to their Auth user. Storage image writes use the same store-owner
check. Assign each existing store's `owner_id` before expecting that account
to manage its catalog.

The dashboard generates garment QR links to
`https://mo-hakiim.github.io/obstore-shop/store.html?shop={store_id}&garment={garment_id}`.
