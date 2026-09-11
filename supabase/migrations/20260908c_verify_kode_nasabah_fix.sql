-- ============================================================================
-- Migrasi verifikasi & (re)perbaikan tabrakan kode_nasabah — Round C
-- ============================================================================
--
-- KENAPA MIGRASI INI ADA:
-- User melaporkan error "duplicate key value violates unique constraint
-- nasabah_kode_nasabah_key" MASIH terjadi setelah migrasi sebelumnya
-- (20260908b_fix_kode_nasabah_collision.sql) dibuat.
--
-- Migrasi 20260908b sudah tersimpan sebagai FILE di folder proyek, tapi
-- menyimpan file .sql di folder proyek TIDAK sama dengan menjalankannya —
-- Supabase tidak otomatis menjalankan file migrasi kecuali di-push lewat
-- Supabase CLI (`supabase db push`). Kemungkinan besar isi file itu belum
-- pernah benar-benar dieksekusi di database. Migrasi ini AMAN dijalankan
-- ulang berkali-kali (idempotent) — jalankan langsung di Supabase SQL
-- Editor, lalu lihat hasil query verifikasi di paling bawah.
--
-- PENTING — ini BUKAN bug khusus akun yang dibuat lewat dashboard admin:
-- kode_nasabah dibuat oleh TRIGGER di database (lihat tambahNasabah() di
-- nasabah_repository.dart — kolom kode_nasabah sengaja tidak dikirim dari
-- Flutter). Kalau trigger lama menghitung nomor berikutnya dengan query
-- yang ikut disaring Row Level Security, maka SIAPAPUN petugas (dibuat
-- lewat dashboard ATAUPUN SQL editor) bisa bertabrakan kode PERSIS di
-- nasabah PERTAMA yang mereka tambahkan — karena RLS membuat query itu
-- hanya melihat 0 baris milik petugas tsb. Akun yang dibuat lewat SQL
-- editor biasanya "kebetulan" tidak kena karena sudah py ada nasabah lain
-- di database saat diuji. Memperbaiki ini di sini menyelesaikan akar
-- masalahnya untuk SEMUA akun, bukan cuma yang dibuat lewat dashboard.
-- ============================================================================

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
    -- Samakan sequence dengan kondisi data TERKINI supaya tidak bertabrakan
    -- lagi kalau ternyata sequence lama sudah "ketinggalan" dari data.
    perform setval(
      'public.nasabah_kode_seq',
      greatest(v_next, (select last_value from public.nasabah_kode_seq)),
      false
    );
  end if;
end $$;

-- security definer + set search_path: fungsi ini jalan dengan hak akses
-- PEMILIK fungsi (bukan siapa yang memanggil), jadi nextval() di bawah
-- TIDAK disaring oleh RLS petugas manapun.
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

-- Prefix 'zz_' sengaja dipakai supaya trigger ini jalan PALING TERAKHIR di
-- antara semua trigger BEFORE INSERT pada tabel nasabah (Postgres menjalankan
-- trigger dengan timing sama secara URUT ABJAD nama trigger) — jadi kalau
-- masih ada trigger lama peninggalan yang juga mengisi kode_nasabah, trigger
-- ini akan menimpanya paling akhir dengan nilai yang benar.
drop trigger if exists zz_fix_kode_nasabah on public.nasabah;
create trigger zz_fix_kode_nasabah
  before insert on public.nasabah
  for each row
  execute function public.zz_fix_kode_nasabah();

grant usage, select on sequence public.nasabah_kode_seq to authenticated;

-- ============================================================================
-- VERIFIKASI — jalankan lalu lihat hasilnya:
-- ============================================================================

-- 1) Trigger ini harus muncul dengan action_timing = 'BEFORE'.
select trigger_name, event_manipulation, action_timing
from information_schema.triggers
where event_object_table = 'nasabah'
order by trigger_name;

-- 2) Nomor kode_nasabah berikutnya yang AKAN dipakai (harus > nomor
--    tertinggi yang sudah ada di tabel nasabah).
select
  (select coalesce(max(substring(kode_nasabah from '[0-9]+')::int), 0)
     from public.nasabah where kode_nasabah ~ '[0-9]+') as kode_tertinggi_saat_ini,
  last_value as sequence_akan_pakai
from public.nasabah_kode_seq;
