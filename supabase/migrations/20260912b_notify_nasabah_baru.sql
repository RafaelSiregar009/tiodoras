-- ============================================================================
-- FITUR: notifikasi ke admin juga saat PETUGAS MENGAJUKAN NASABAH BARU
-- (sebelumnya hanya untuk pelunasan & perpanjangan). Jalankan di SQL Editor.
-- Prasyarat: service_role_key sudah tersimpan di Vault (lihat migrasi
-- 20260911b_notify_admin_trigger.sql) — pakai secret yang sama.
-- ============================================================================

create extension if not exists pg_net with schema extensions;

create or replace function public.notify_admin_on_nasabah_baru()
returns trigger language plpgsql security definer
set search_path = public, extensions as $$
declare
  v_service_key text;
  v_project_url text := 'https://tzxfgaobjdcougdgvqwq.supabase.co';
  v_petugas_nama text;
begin
  if NEW.status_approval = 'pending' then
    select nama into v_petugas_nama from public.profiles where id = NEW.petugas_id;
    select decrypted_secret into v_service_key
      from vault.decrypted_secrets where name = 'service_role_key' limit 1;
    if v_service_key is not null then
      perform net.http_post(
        url := v_project_url || '/functions/v1/notify-admin-pengajuan',
        headers := jsonb_build_object(
          'Content-Type','application/json',
          'Authorization','Bearer ' || v_service_key),
        body := jsonb_build_object(
          'jenis','nasabah_baru',
          'nasabah_id', NEW.id,
          'nasabah_nama', NEW.nama,
          'petugas_nama', coalesce(v_petugas_nama,'-'))
      );
    end if;
  end if;
  return NEW;
end; $$;

drop trigger if exists trg_notify_admin_nasabah_baru on public.nasabah;
create trigger trg_notify_admin_nasabah_baru
  after insert on public.nasabah
  for each row execute function public.notify_admin_on_nasabah_baru();