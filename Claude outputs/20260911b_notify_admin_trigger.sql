-- ============================================================================
-- FITUR BARU: trigger yang otomatis memanggil Edge Function
-- "notify-admin-pengajuan" setiap kali status_pelunasan nasabah berubah
-- jadi 'pengajuan_pelunasan' ATAU 'pengajuan_perpanjangan' — mencakup
-- KEDUA aksi petugas (ajukanPelunasan() & ajukanPerpanjangan() di
-- nasabah_repository.dart, keduanya menulis kolom yang sama).
--
-- PENTING — WAJIB dijalankan SEBELUM migration ini (kalau belum pernah):
-- Simpan Service Role Key project Anda ke Vault Supabase (supaya key-nya
-- TIDAK pernah tersimpan mentah di file SQL ini / repo Anda). Caranya:
--   1) Buka Project Settings -> API di Supabase Dashboard, salin
--      "service_role" key (bukan anon key!).
--   2) Di SQL Editor, jalankan SATU baris ini sendiri (ganti
--      <TEMPEL_SERVICE_ROLE_KEY_DI_SINI> dengan key yang disalin tadi):
--
--        select vault.create_secret('<TEMPEL_SERVICE_ROLE_KEY_DI_SINI>', 'service_role_key');
--
--      (Kalau sebelumnya sudah pernah dibuat dan mau ganti, pakai
--      vault.update_secret alih-alih create_secret — lihat dokumentasi
--      Supabase Vault kalau perlu.)
-- ============================================================================
-- Setelah langkah di atas, jalankan SELURUH isi file ini di SQL Editor.
-- ============================================================================

create extension if not exists pg_net with schema extensions;

create or replace function public.notify_admin_on_pengajuan()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_service_key text;
  v_project_url text := 'https://tzxfgaobjdcougdgvqwq.supabase.co';
  v_jenis text;
  v_petugas_nama text;
begin
  -- Hanya proses kalau status_pelunasan benar-benar BERUBAH jadi salah
  -- satu dari dua status pengajuan ini (bukan status lain, dan bukan
  -- update yang tidak mengubah kolom ini sama sekali).
  if (NEW.status_pelunasan is distinct from OLD.status_pelunasan)
     and NEW.status_pelunasan in ('pengajuan_pelunasan', 'pengajuan_perpanjangan') then

    v_jenis := case NEW.status_pelunasan
      when 'pengajuan_pelunasan' then 'pelunasan'
      else 'perpanjangan'
    end;

    select nama into v_petugas_nama
    from public.profiles
    where id = NEW.petugas_id;

    select decrypted_secret into v_service_key
    from vault.decrypted_secrets
    where name = 'service_role_key'
    limit 1;

    -- Kalau secret belum di-setup (lihat instruksi di atas file ini),
    -- diam saja (jangan sampai gagal setup secret membuat pengajuan
    -- petugas ikut gagal tersimpan).
    if v_service_key is not null then
      perform net.http_post(
        url := v_project_url || '/functions/v1/notify-admin-pengajuan',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || v_service_key
        ),
        body := jsonb_build_object(
          'jenis', v_jenis,
          'nasabah_id', NEW.id,
          'nasabah_nama', NEW.nama,
          'petugas_nama', coalesce(v_petugas_nama, '-')
        )
      );
    end if;
  end if;

  return NEW;
end;
$$;

drop trigger if exists trg_notify_admin_pengajuan on public.nasabah;
create trigger trg_notify_admin_pengajuan
after update of status_pelunasan on public.nasabah
for each row
execute function public.notify_admin_on_pengajuan();

-- Verifikasi — harus muncul 1 baris
select tgname, tgrelid::regclass, tgenabled
from pg_trigger
where tgname = 'trg_notify_admin_pengajuan';
