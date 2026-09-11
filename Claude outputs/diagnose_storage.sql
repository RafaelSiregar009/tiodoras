-- ============================================================================
-- Diagnosa lengkap kenapa upload ke bucket 'avatars' masih ditolak RLS
-- padahal policy-nya sudah benar. Semua query ini READ-ONLY (aman).
-- Jalankan SEMUA sekaligus, screenshot SEMUA hasilnya (mungkin perlu run
-- satu-satu kalau SQL Editor cuma menampilkan hasil query terakhir).
-- ============================================================================

-- 1) Apakah RLS aktif & di-force di tabel storage.objects?
select relrowsecurity, relforcerowsecurity
from pg_class
where oid = 'storage.objects'::regclass;

-- 2) SEMUA policy di storage.objects, lengkap dengan qual & with_check,
--    termasuk punya 'agunan-photos' untuk dibandingkan strukturnya.
select policyname, cmd, permissive, roles, qual, with_check
from pg_policies
where schemaname = 'storage' and tablename = 'objects'
order by cmd, policyname;

-- 3) Detail bucket 'avatars' — pastikan id-nya persis 'avatars' (bukan typo
--    kapital/spasi) dan tidak ada pembatasan ukuran/tipe file.
select id, name, public, file_size_limit, allowed_mime_types
from storage.buckets
where id ilike '%avatar%';

-- 4) Role admin yang sedang dipakai untuk login di app — pastikan baris
--    profilnya benar role='admin' (dipakai policy lain, buat perbandingan).
select id, nama, role from public.profiles where role = 'admin';
