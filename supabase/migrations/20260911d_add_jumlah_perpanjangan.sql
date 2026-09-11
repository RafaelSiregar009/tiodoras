-- ============================================================================
-- FITUR BARU: info "Pinjaman Ke berapa" di halaman detail nasabah.
--
-- Kolom jumlah_perpanjangan di tabel nasabah menyimpan berapa kali pinjaman
-- ini SUDAH disetujui admin untuk diperpanjang (bukan berapa kali diajukan
-- — pengajuan yang ditolak tidak dihitung). "Pinjaman Ke" yang ditampilkan
-- di aplikasi = jumlah_perpanjangan + 1 (lihat NasabahModel.pinjamanKe).
--
-- Nilainya di-increment OTOMATIS oleh trigger di bawah setiap kali status
-- baris di tabel perpanjangan berubah jadi 'approved' — Flutter tidak
-- pernah mengirim nilai ini secara langsung, sama seperti kode_nasabah.
-- ============================================================================
-- Jalankan SELURUH isi file ini di Supabase SQL Editor. Aman diulang.
-- ============================================================================

alter table public.nasabah
  add column if not exists jumlah_perpanjangan integer not null default 0;

-- Backfill: nasabah yang SUDAH punya riwayat perpanjangan approved dari
-- sebelum kolom ini ada, langsung dihitung dari data yang sudah ada —
-- supaya "Pinjaman Ke" langsung benar tanpa perlu perpanjangan baru dulu.
update public.nasabah n
set jumlah_perpanjangan = sub.cnt
from (
  select nasabah_id, count(*) as cnt
  from public.perpanjangan
  where status = 'approved'
  group by nasabah_id
) sub
where n.id = sub.nasabah_id;

create or replace function public.increment_jumlah_perpanjangan()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if NEW.status = 'approved' and (OLD.status is distinct from NEW.status) then
    update public.nasabah
    set jumlah_perpanjangan = jumlah_perpanjangan + 1
    where id = NEW.nasabah_id;
  end if;
  return NEW;
end;
$$;

drop trigger if exists trg_increment_jumlah_perpanjangan on public.perpanjangan;
create trigger trg_increment_jumlah_perpanjangan
after update of status on public.perpanjangan
for each row
execute function public.increment_jumlah_perpanjangan();

-- Verifikasi — lihat beberapa nasabah yang sudah pernah diperpanjang
-- (kalau ada), jumlah_perpanjangan-nya harus > 0.
select id, nama, jumlah_perpanjangan
from public.nasabah
where jumlah_perpanjangan > 0
order by jumlah_perpanjangan desc
limit 20;
