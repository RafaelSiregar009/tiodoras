-- Migration: perbaiki tabrakan kode_nasabah untuk akun petugas BARU
--
-- LATAR BELAKANG (untuk dibaca sebelum menjalankan):
-- Error yang muncul: PostgrestException duplicate key value violates unique
-- constraint "nasabah_kode_nasabah_key" saat AJUKAN NASABAH.
--
-- Dugaan kuat akar masalahnya: kode_nasabah (mis. "NBS-001") dibuat oleh
-- trigger di database yang menghitung nomor berikutnya dengan query seperti
-- `select count(*) from nasabah` atau `select max(...) from nasabah`. Kalau
-- Row Level Security (RLS) aktif di tabel nasabah DAN trigger itu tidak
-- di-set SECURITY DEFINER + row_security off, maka query count/max di
-- dalam trigger ikut "disaring" oleh RLS sesuai siapa yang sedang login —
-- artinya petugas yang HANYA bisa melihat nasabah miliknya sendiri akan
-- selalu dapat hitungan mulai dari 0 walau nasabah lain (milik petugas
-- lain) sudah ada ratusan. Hasilnya: petugas BARU (baik dibuat lewat
-- dashboard admin maupun SQL editor) akan selalu mencoba membuat kode yang
-- sudah dipakai duluan oleh petugas pertama yang menguji aplikasi ini
-- (kode_nasabah unik untuk SELURUH tabel, bukan per-petugas) → tabrakan.
--
-- Ini BUKAN soal "akun dibuat admin vs SQL editor" secara langsung — kedua
-- cara pembuatan akun sama-sama menghasilkan baris profiles yang identik
-- (sudah dicek di kode Edge Function manage-petugas). Yang beda adalah
-- akun yang SUDAH LAMA dipakai untuk testing (sudah lebih dulu "mengambil"
-- nomor kode kecil) vs akun BARU (mulai dari hitungan nol lagi karena RLS)
-- — makanya akun baru yang paling sering kena.
--
-- CARA MENJALANKAN:
-- 1) (Opsional tapi disarankan) Jalankan dulu query diagnostik ini secara
--    terpisah untuk melihat definisi trigger lama, sekadar untuk konfirmasi:
--
--      select tgname, pg_get_triggerdef(oid)
--      from pg_trigger
--      where tgrelid = 'public.nasabah'::regclass and not tgisinternal;
--
-- 2) Jalankan migration di bawah ini di Supabase Dashboard → SQL Editor.
--    Aman dijalankan berulang. Migration ini TIDAK menghapus trigger lama
--    (karena namanya tidak diketahui dari sisi kode aplikasi) — sebagai
--    gantinya migration ini menambah SATU trigger baru bernama diawali
--    "zz_" supaya berjalan PALING TERAKHIR (trigger di Postgres berjalan
--    berurutan sesuai abjad nama) dan MENIMPA kode_nasabah dengan nomor
--    dari sequence global yang kebal RLS, apa pun yang dihasilkan trigger
--    lama sebelumnya.

-- 1) Sequence global, di-seed dari nomor kode tertinggi yang sudah ada
--    supaya tidak tabrakan dengan data lama.
do $$
declare
  v_next integer;
begin
  select coalesce(max(substring(kode_nasabah from '[0-9]+')::int), 0) + 1
    into v_next
    from public.nasabah
    where kode_nasabah ~ '[0-9]+';

  if not exists (
    select 1 from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where c.relkind = 'S' and c.relname = 'nasabah_kode_seq' and n.nspname = 'public'
  ) then
    execute format('create sequence public.nasabah_kode_seq start with %s', v_next);
  else
    perform setval('public.nasabah_kode_seq', v_next, false);
  end if;
end $$;

-- 2) Trigger function baru — SECURITY DEFINER supaya berjalan dengan hak
--    akses pemilik function (bukan hak akses petugas yang sedang login),
--    dan nextval() pada sequence sama sekali tidak bergantung pada baris
--    tabel nasabah sehingga kebal dari pembatasan RLS.
create or replace function public.zz_fix_kode_nasabah()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  new.kode_nasabah := 'NBS-' || lpad(nextval('public.nasabah_kode_seq')::text, 3, '0');
  return new;
end;
$$;

drop trigger if exists zz_fix_kode_nasabah on public.nasabah;
create trigger zz_fix_kode_nasabah
  before insert on public.nasabah
  for each row
  execute function public.zz_fix_kode_nasabah();

-- 3) Beri hak pakai sequence ke role yang dipakai aplikasi (authenticated)
--    supaya trigger tidak gagal karena masalah permission.
grant usage, select on sequence public.nasabah_kode_seq to authenticated;
