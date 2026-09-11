-- ============================================================================
-- FITUR BARU: notifikasi push ke HP admin saat petugas mengajukan
-- pelunasan/perpanjangan.
--
-- Kolom ini menyimpan FCM device token milik admin yang sedang login (satu
-- token = satu HP/perangkat terakhir yang dipakai login sebagai admin).
-- Diisi otomatis oleh aplikasi Flutter lewat AuthRepository.saveFcmToken()
-- setiap kali admin login atau buka app dengan sesi yang masih aktif.
-- ============================================================================
-- Jalankan SELURUH isi file ini di Supabase SQL Editor. Aman diulang.
-- ============================================================================

alter table public.profiles
  add column if not exists fcm_token text;

-- Pastikan RLS policy "Admin can update own profile" (dari migrasi
-- 20260909_add_avatar_support.sql) masih ada — itu yang mengizinkan admin
-- update kolom fcm_token di baris miliknya sendiri lewat AuthRepository.
-- Tidak perlu policy baru karena policy ini sudah row-level (semua kolom
-- di baris tsb, bukan cuma avatar_url).

-- Verifikasi — harus muncul kolom fcm_token dengan tipe text
select column_name, data_type
from information_schema.columns
where table_schema = 'public'
  and table_name = 'profiles'
  and column_name = 'fcm_token';
