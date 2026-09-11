-- ============================================================================
-- Fitur baru: foto profil untuk admin & petugas
-- ============================================================================
-- Jalankan SELURUH isi file ini sekali di Supabase SQL Editor.
-- ============================================================================

-- 1) Kolom foto profil di tabel profiles
alter table public.profiles add column if not exists avatar_url text;

-- 2) Bucket Storage 'avatars' — public supaya foto bisa langsung tampil
--    tanpa perlu token/signed URL (sama seperti 'agunan-photos').
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do update set public = true;

-- 3) Siapa saja yang boleh UPLOAD ke bucket 'avatars'. Upload SELALU
--    dilakukan dari sesi ADMIN yang sedang login (baik saat mengatur foto
--    petugas maupun foto dirinya sendiri) — jadi cukup izinkan semua user
--    yang sudah login (authenticated), sama seperti pola bucket
--    'agunan-photos' yang sudah ada.
drop policy if exists "Authenticated users can upload avatars" on storage.objects;
create policy "Authenticated users can upload avatars"
on storage.objects for insert
to authenticated
with check (bucket_id = 'avatars');

drop policy if exists "Authenticated users can update avatars" on storage.objects;
create policy "Authenticated users can update avatars"
on storage.objects for update
to authenticated
using (bucket_id = 'avatars');

-- 4) RLS: admin boleh mengubah baris profilnya SENDIRI secara langsung
--    (dipakai saat admin mengganti foto profil miliknya sendiri dari
--    dashboard). Foto profil PETUGAS tetap HANYA lewat Edge Function
--    manage-petugas (service_role) — bukan lewat policy ini — konsisten
--    dengan alasan kenapa akun petugas dikelola di server, bukan client.
--
--    Sengaja dibatasi `role = 'admin'` supaya petugas TIDAK BISA memakai
--    policy yang sama untuk mengubah baris profilnya sendiri (mis. nama
--    atau role) langsung dari client — itu tetap harus lewat jalur admin.
drop policy if exists "Admin can update own profile" on public.profiles;
create policy "Admin can update own profile"
on public.profiles for update
to authenticated
using (id = auth.uid() and role = 'admin')
with check (id = auth.uid() and role = 'admin');
