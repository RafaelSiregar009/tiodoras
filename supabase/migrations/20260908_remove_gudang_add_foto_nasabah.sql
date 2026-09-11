-- Migration: hapus dependensi alur gudang, tambah foto_nasabah_url
--
-- Jalankan sekali di Supabase Dashboard → SQL Editor (atau `supabase db push`
-- kalau memakai Supabase CLI migrations). Aman dijalankan berulang (pakai
-- IF NOT EXISTS / WHERE guard).

-- 1) Kolom baru untuk foto nasabah (identitas/wajah peminjam), terpisah dari
--    kolom foto_url yang sudah ada (itu foto agunan/barang jaminan).
alter table public.nasabah
  add column if not exists foto_nasabah_url text;

-- 2) Alur gudang dihapus dari aplikasi. Lipat data yang sedang "nyangkut"
--    menunggu langkah gudang (kalau ada) supaya langsung masuk antrean
--    persetujuan admin yang baru, tidak hilang dari radar.
update public.nasabah
  set status_approval = 'pending'
  where status_approval = 'approved_gudang';

update public.nasabah
  set status_pelunasan = 'pengajuan_pelunasan'
  where status_pelunasan = 'konfirmasi_gudang';

-- 3) OPSIONAL — cek dulu apakah masih ada akun dengan role lama
--    'petugas_gudang'. Aplikasi sekarang mengarahkan role apa pun selain
--    'admin' ke dashboard petugas, jadi akun ini tetap bisa login seperti
--    petugas biasa walau tidak diubah. Kalau ingin akun ini juga muncul di
--    menu "Kelola Petugas" admin, jalankan UPDATE di bawah ini.
-- select id, nama, role from public.profiles where role = 'petugas_gudang';
-- update public.profiles set role = 'petugas' where role = 'petugas_gudang';

-- 4) Kalau Anda punya Row Level Security policy yang menyebut role
--    'petugas_gudang' (di tabel nasabah, profiles, atau storage bucket
--    agunan-photos), tinjau ulang di Supabase Dashboard → Authentication →
--    Policies. Migration ini tidak menyentuh RLS karena nama/isi policy
--    Anda tidak diketahui dari sisi kode aplikasi.
