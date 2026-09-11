# notify-admin-pengajuan

Edge Function ini mengirim push notification (Firebase Cloud Messaging) ke
HP admin setiap kali petugas mengajukan pelunasan atau perpanjangan.
Dipanggil otomatis oleh trigger database — lihat
`supabase/migrations/20260911b_notify_admin_trigger.sql`.

## Deploy

```
supabase functions deploy notify-admin-pengajuan
```

## Setup secret (WAJIB, sekali saja)

Buka file Service Account JSON yang Anda download dari Firebase Console
(Project Settings → Service accounts → Generate new private key). Isinya
kira-kira begini:

```json
{
  "project_id": "nama-project-anda",
  "client_email": "firebase-adminsdk-xxxxx@nama-project-anda.iam.gserviceaccount.com",
  "private_key": "-----BEGIN PRIVATE KEY-----\nMII...banyak baris...\n-----END PRIVATE KEY-----\n",
  ...
}
```

Ambil 3 nilai itu (`project_id`, `client_email`, `private_key`), lalu
jalankan di terminal (folder project, tempat `supabase` CLI bisa
dipakai):

```
supabase secrets set FCM_PROJECT_ID="nama-project-anda"
supabase secrets set FCM_CLIENT_EMAIL="firebase-adminsdk-xxxxx@nama-project-anda.iam.gserviceaccount.com"
supabase secrets set FCM_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----
MII...banyak baris...
-----END PRIVATE KEY-----
"
```

Untuk `FCM_PRIVATE_KEY`, cara paling aman: copy-paste PERSIS nilai
`private_key` dari file JSON (termasuk semua `\n` di dalamnya) di antara
tanda kutip ganda — function ini sudah menangani baik format dengan
newline asli maupun literal `\n`.

Setelah secret di-set, tidak perlu di-deploy ulang functionnya — secret
langsung terpakai di pemanggilan berikutnya.
