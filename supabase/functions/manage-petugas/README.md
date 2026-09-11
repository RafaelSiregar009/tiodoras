# manage-petugas — cara deploy

Fungsi ini menangani create/update/delete akun login petugas (dipanggil dari
menu **Kelola Petugas** di aplikasi admin). Perlu di-deploy sekali via
Supabase CLI.

## 1. Install Supabase CLI (kalau belum ada)

```
npm install -g supabase
```

## 2. Login & hubungkan ke project

Dari folder root project ini (`tiodoras_app/`):

```
supabase login
supabase link --project-ref tzxfgaobjdcougdgvqwq
```

(`tzxfgaobjdcougdgvqwq` diambil dari `supabaseUrl` di `lib/supabase_config.dart`.)

## 3. Deploy

```
supabase functions deploy manage-petugas
```

Tidak perlu set secret manual — `SUPABASE_URL`, `SUPABASE_ANON_KEY`, dan
`SUPABASE_SERVICE_ROLE_KEY` otomatis tersedia untuk setiap Edge Function di
project Supabase.

## 4. Uji coba

Setelah deploy, login sebagai admin di aplikasi lalu buka menu **Kelola
Petugas** (kartu "Jumlah Petugas" di dashboard admin) dan coba tambah satu
akun petugas. Kalau ada error "Edge Function ... sudah di-deploy", cek log
function di Supabase Dashboard → Edge Functions → manage-petugas → Logs.
