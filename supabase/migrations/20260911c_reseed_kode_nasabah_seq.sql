-- ============================================================================
-- Re-seed sequence kode_nasabah (Round D) — bug yang sama muncul lagi:
-- "duplicate key value violates unique constraint nasabah_kode_nasabah_key"
-- gagal di percobaan pertama, berhasil di percobaan/klik kedua.
--
-- PENYEBAB: sequence public.nasabah_kode_seq (lihat migrasi
-- 20260908b_fix_kode_nasabah_collision.sql & 20260908c) sudah "ketinggalan"
-- lagi dari data yang ada di tabel nasabah saat ini — kemungkinan besar
-- karena ada baris nasabah yang ditambahkan lewat SQL Editor secara manual
-- (untuk testing) dengan kode_nasabah eksplisit yang lebih tinggi dari
-- posisi sequence saat ini. App di sisi Flutter sebenarnya SUDAH otomatis
-- mencoba ulang sampai 5x kalau kena tabrakan begini (lihat
-- nasabah_repository.dart -> tambahNasabah()), tapi kalau ada beberapa
-- baris berurutan yang "menghalangi", 5x percobaan itu keburu habis
-- sebelum sequence-nya berhasil lewat dari semuanya — makanya klik pertama
-- tetap gagal, dan klik kedua (5 percobaan BARU lagi) baru berhasil.
--
-- Migrasi ini AMAN dijalankan berkali-kali kapan saja (idempotent) — cukup
-- menyamakan posisi sequence dengan kode_nasabah TERTINGGI yang benar-benar
-- ada di tabel saat ini.
-- ============================================================================

do $$
declare
  v_next integer;
begin
  select coalesce(max(substring(kode_nasabah from '[0-9]+')::int), 0) + 1
    into v_next
    from public.nasabah
    where kode_nasabah ~ '[0-9]+';

  perform setval('public.nasabah_kode_seq', v_next, false);
end $$;

-- Verifikasi — kolom "sequence_akan_pakai" harus LEBIH BESAR dari
-- "kode_tertinggi_saat_ini".
select
  (select coalesce(max(substring(kode_nasabah from '[0-9]+')::int), 0)
     from public.nasabah where kode_nasabah ~ '[0-9]+') as kode_tertinggi_saat_ini,
  last_value as sequence_akan_pakai
from public.nasabah_kode_seq;
