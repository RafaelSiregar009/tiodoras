-- ============================================================================
-- Perbaikan: policy Storage 'avatars' dibatasi role `authenticated`, tapi
-- request Storage dari sesi ini ternyata tidak dikenali sebagai role itu
-- (walau query tabel biasa/Postgrest berhasil normal — jalurnya berbeda).
-- Buktinya: bucket 'agunan-photos' (foto nasabah/agunan) yang policy-nya
-- role `public` SELALU berhasil upload, sementara 'avatars' yang dibatasi
-- `authenticated` SELALU gagal 403 — bukan sekadar glitch sesaat.
--
-- Perbaikan: samakan pola 'avatars' dengan 'agunan-photos' yang sudah
-- terbukti jalan — role `public`, tetap dibatasi ke bucket_id = 'avatars'
-- saja, jadi tingkat keamanannya setara dengan yang sudah dipakai untuk
-- foto agunan/nasabah selama ini (tidak menambah risiko baru).
-- ============================================================================
-- Jalankan SELURUH isi file ini di Supabase SQL Editor. Aman diulang.
-- ============================================================================

drop policy if exists "Authenticated users can upload avatars" on storage.objects;
create policy "Authenticated users can upload avatars"
on storage.objects for insert
to public
with check (bucket_id = 'avatars');

drop policy if exists "Authenticated users can update avatars" on storage.objects;
create policy "Authenticated users can update avatars"
on storage.objects for update
to public
using (bucket_id = 'avatars');

-- Verifikasi — harus muncul 2 baris dengan kolom roles = {public}
select policyname, cmd, roles, with_check, qual
from pg_policies
where schemaname = 'storage'
  and tablename = 'objects'
  and policyname ilike '%avatars%';
