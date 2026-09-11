-- ============================================================================
-- Fitur baru: Ringkasan per-bulan di halaman detail petugas (admin)
-- ============================================================================
-- Jalankan SELURUH isi file ini sekali di Supabase SQL Editor.
--
-- Kenapa perlu ini: untuk menghitung "Storting" (total pelunasan + biaya
-- perpanjangan) PER BULAN secara akurat, aplikasi perlu tahu KAPAN sebuah
-- pinjaman benar-benar lunas dan KAPAN sebuah perpanjangan disetujui — bukan
-- cuma kapan diajukan. Kolom-kolom itu belum ada, jadi ditambahkan di sini.
--
-- CATATAN PENTING soal data LAMA (transaksi lunas/perpanjangan yang sudah
-- terjadi SEBELUM migrasi ini dijalankan): sesuai arahan, data lama diisi
-- dengan PERKIRAAN tanggal (bukan tanggal pasti, karena memang tidak pernah
-- dicatat) — nasabah yang sudah lunas diperkirakan lunas di tanggal_masuk-nya
-- sendiri, dan perpanjangan yang sudah disetujui diperkirakan disetujui di
-- tanggal pengajuannya (created_at). Akibatnya, laporan bulan-bulan LAMA bisa
-- sedikit meleset dari kejadian aslinya. Untuk transaksi BARU sejak migrasi
-- ini dijalankan, tanggalnya akan selalu akurat (dicatat otomatis oleh
-- aplikasi).
-- ============================================================================

-- 1) Kolom tanggal_lunas di tabel nasabah — diisi otomatis oleh aplikasi
--    (approveAdminPelunasan) saat admin menyetujui pelunasan.
alter table public.nasabah add column if not exists tanggal_lunas timestamptz;

-- Backfill PERKIRAAN untuk nasabah yang SUDAH lunas sebelum migrasi ini,
-- pakai tanggal_masuk sebagai perkiraan (lihat catatan di atas).
update public.nasabah
  set tanggal_lunas = tanggal_masuk
  where status = 'lunas' and tanggal_lunas is null;

-- 2) Kolom approved_at di tabel perpanjangan — diisi otomatis oleh aplikasi
--    (approveAdminPerpanjangan) saat admin menyetujui perpanjangan.
alter table public.perpanjangan add column if not exists approved_at timestamptz;

-- Backfill PERKIRAAN untuk perpanjangan yang SUDAH disetujui sebelum migrasi
-- ini, pakai created_at (tanggal pengajuan) sebagai perkiraan.
update public.perpanjangan
  set approved_at = created_at
  where status = 'approved' and approved_at is null;
