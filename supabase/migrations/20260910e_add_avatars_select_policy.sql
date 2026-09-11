-- ============================================================================
-- AKAR MASALAH KETEMU: upload foto avatar di kode Flutter pakai
-- `upsert: true`, yang membuat Storage mengirim query
--   INSERT INTO storage.objects (...) VALUES (...)
--   ON CONFLICT (name, bucket_id) DO UPDATE SET ...
-- (lihat query mentah di Postgres Logs, dikirim user).
--
-- Untuk query "upsert" (INSERT ... ON CONFLICT DO UPDATE), Postgres RLS
-- WAJIB bisa mengevaluasi baris lewat policy SELECT juga — bukan cuma
-- INSERT/UPDATE — karena sebelum memutuskan insert baris baru atau update
-- baris lama, Postgres perlu memeriksa dulu apakah baris dengan
-- (name, bucket_id) itu sudah ada.
--
-- Selama ini bucket 'avatars' HANYA punya policy INSERT & UPDATE, TIDAK
-- ADA policy SELECT sama sekali untuk bucket ini (satu-satunya policy
-- SELECT yang ada, "storage: baca foto public", scope-nya cuma untuk
-- bucket 'agunan-photos'). Makanya query upsert avatars SELALU ditolak
-- RLS, sementara upload ke 'agunan-photos' (yang TIDAK pakai upsert)
-- selalu berhasil.
--
-- Ini TIDAK berhubungan dengan tampilnya foto di aplikasi (itu lewat URL
-- publik yang bypass RLS karena bucket-nya public=true) — makanya
-- selama ini kelihatan "baik-baik saja" kecuali pas upload.
-- ============================================================================
-- Jalankan SELURUH isi file ini di Supabase SQL Editor. Aman diulang.
-- ============================================================================

drop policy if exists "Public can view avatars" on storage.objects;
create policy "Public can view avatars"
on storage.objects for select
to public
using (bucket_id = 'avatars');

-- Verifikasi — harus muncul 1 baris baru untuk SELECT di bucket avatars
select policyname, cmd, roles, qual
from pg_policies
where schemaname = 'storage'
  and tablename = 'objects'
  and policyname = 'Public can view avatars';
