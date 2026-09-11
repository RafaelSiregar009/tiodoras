-- ============================================================================
-- Diagnosa & perbaikan: bucket + policy Storage 'avatars' sering rollback
-- kalau dijalankan bersamaan dengan statement lain yang error, jadi file
-- ini SENGAJA dipisah supaya bisa dipastikan berhasil sendiri.
-- ============================================================================
-- Jalankan SELURUH isi file ini di Supabase SQL Editor. Aman diulang.
-- ============================================================================

-- 1) Pastikan bucket 'avatars' ada & public.
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do update set public = true;

-- 2) Pastikan policy upload/update ada (drop dulu supaya tidak duplikat).
drop policy if exists "Authenticated users can upload avatars" on storage.objects;
create policy "Authenticated users can upload avatars"
on storage.objects for insert
to authenticated
with check (bucket_id = 'avatars');

drop policy if exists "Authenticated users can update avatars" on storage.objects;
create policy "Authenticated users can update avatars"
on storage.objects for update
to authenticated
using (bucket_id = 'avatars');

-- ============================================================================
-- 3) VERIFIKASI — jalankan bagian ini juga, lalu screenshot/salin hasilnya
--    kalau masih error setelah ini. Harus muncul 1 baris di masing-masing.
-- ============================================================================

-- Harus muncul 1 baris: avatars | avatars | true
select id, name, public from storage.buckets where id = 'avatars';

-- Harus muncul 2 baris (upload & update)
select policyname, cmd, roles, with_check, qual
from pg_policies
where schemaname = 'storage'
  and tablename = 'objects'
  and policyname ilike '%avatars%';

-- Cek juga apakah ada policy LAIN (bukan buatan kita) di storage.objects yang
-- mungkin ikut membatasi/menolak. Kalau muncul baris dengan
-- permissive = 'RESTRICTIVE', itu kemungkinan penyebabnya.
select policyname, cmd, permissive, roles
from pg_policies
where schemaname = 'storage' and tablename = 'objects';
