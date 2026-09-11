// Edge Function: notify-admin-pengajuan
//
// Dipanggil OTOMATIS oleh trigger database (lihat migrasi
// 20260911b_notify_admin_trigger.sql) setiap kali seorang petugas
// mengajukan pelunasan atau perpanjangan (status_pelunasan nasabah berubah
// jadi 'pengajuan_pelunasan' / 'pengajuan_perpanjangan'). Function ini
// mengirim push notification (Firebase Cloud Messaging) ke SEMUA admin
// yang device token-nya tersimpan di profiles.fcm_token — supaya admin
// dapat notifikasi di HP walau aplikasinya sedang tertutup.
//
// Kenapa harus lewat server (bukan dikirim langsung dari trigger Postgres
// ke Google): mengirim FCM v1 API butuh access token OAuth2 yang didapat
// dengan menandatangani JWT pakai PRIVATE KEY dari Service Account Firebase
// — private key ini rahasia, disimpan sebagai secret Edge Function
// (bukan di database ataupun di aplikasi Flutter).
//
// Cara deploy:
//   supabase functions deploy notify-admin-pengajuan
//
// Secret yang WAJIB di-set sebelum dipakai (lihat README.md di folder ini):
//   supabase secrets set FCM_PROJECT_ID=...
//   supabase secrets set FCM_CLIENT_EMAIL=...
//   supabase secrets set FCM_PRIVATE_KEY="..."

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// ── Helper: base64url encode ────────────────────────────────────────────
function base64url(input: ArrayBuffer | string): string {
  let bytes: Uint8Array;
  if (typeof input === "string") {
    bytes = new TextEncoder().encode(input);
  } else {
    bytes = new Uint8Array(input);
  }
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

// ── Helper: import PEM private key (PKCS8) untuk RS256 signing ─────────
async function importPrivateKey(pem: string): Promise<CryptoKey> {
  const cleaned = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s/g, "");
  const der = Uint8Array.from(atob(cleaned), (c) => c.charCodeAt(0));
  return crypto.subtle.importKey(
    "pkcs8",
    der.buffer,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
}

// ── Helper: dapatkan access token OAuth2 dari Service Account ──────────
// (menandatangani JWT sendiri lewat Web Crypto — tidak butuh library
// tambahan yang belum tentu kompatibel dengan Deno edge runtime)
async function getGoogleAccessToken(): Promise<string> {
  const clientEmail = Deno.env.get("FCM_CLIENT_EMAIL");
  const privateKeyRaw = Deno.env.get("FCM_PRIVATE_KEY");
  if (!clientEmail || !privateKeyRaw) {
    throw new Error(
      "Secret FCM_CLIENT_EMAIL / FCM_PRIVATE_KEY belum di-set (lihat README.md)",
    );
  }
  // Kalau di-set lewat `supabase secrets set FCM_PRIVATE_KEY="..."` dengan
  // newline literal "\n" (bukan newline asli), ganti balik di sini.
  const privateKey = privateKeyRaw.replace(/\\n/g, "\n");

  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "RS256", typ: "JWT" };
  const claims = {
    iss: clientEmail,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    exp: now + 3600,
    iat: now,
  };

  const unsigned = `${base64url(JSON.stringify(header))}.${
    base64url(JSON.stringify(claims))
  }`;
  const key = await importPrivateKey(privateKey);
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(unsigned),
  );
  const jwt = `${unsigned}.${base64url(signature)}`;

  const tokenRes = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  const tokenJson = await tokenRes.json();
  if (!tokenRes.ok || !tokenJson.access_token) {
    throw new Error(
      `Gagal ambil access token Google: ${JSON.stringify(tokenJson)}`,
    );
  }
  return tokenJson.access_token as string;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    if (req.method !== "POST") {
      throw new Error("Method not allowed");
    }

    const body = await req.json().catch(() => ({}));
    const jenis = (body.jenis ?? "").toString(); // 'pelunasan' | 'perpanjangan'
    const nasabahNama = (body.nasabah_nama ?? "-").toString();
    const petugasNama = (body.petugas_nama ?? "-").toString();

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const adminClient = createClient(supabaseUrl, serviceRoleKey);

    // Ambil semua admin yang punya device token tersimpan.
    const { data: admins, error: adminsErr } = await adminClient
      .from("profiles")
      .select("id, fcm_token")
      .eq("role", "admin")
      .not("fcm_token", "is", null);
    if (adminsErr) throw adminsErr;

    if (!admins || admins.length === 0) {
      return jsonResponse({ ok: true, sent: 0, note: "Tidak ada admin dengan fcm_token" });
    }

    const judul = jenis === "pelunasan"
      ? "Pengajuan Pelunasan Baru"
      : "Pengajuan Perpanjangan Baru";
    const pesan = `${petugasNama} mengajukan ${jenis} untuk nasabah ${nasabahNama}`;

    const accessToken = await getGoogleAccessToken();
    const projectId = Deno.env.get("FCM_PROJECT_ID");
    if (!projectId) throw new Error("Secret FCM_PROJECT_ID belum di-set");

    let sent = 0;
    const invalidTokenIds: string[] = [];

    for (const admin of admins) {
      const token = admin.fcm_token as string;
      const res = await fetch(
        `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
        {
          method: "POST",
          headers: {
            "Authorization": `Bearer ${accessToken}`,
            "Content-Type": "application/json; charset=UTF-8",
          },
          body: JSON.stringify({
            message: {
              token,
              notification: { title: judul, body: pesan },
              data: { jenis, nasabah_nama: nasabahNama },
              android: {
                priority: "high",
                notification: { channel_id: "pengajuan_channel" },
              },
            },
          }),
        },
      );

      if (res.ok) {
        sent++;
      } else {
        const errJson = await res.json().catch(() => ({}));
        // Token yang sudah tidak valid (uninstall/logout) — bersihkan dari
        // DB supaya tidak terus dicoba tiap kali ada pengajuan baru.
        const errStatus = errJson?.error?.status;
        if (errStatus === "NOT_FOUND" || errStatus === "UNREGISTERED") {
          invalidTokenIds.push(admin.id as string);
        }
      }
    }

    if (invalidTokenIds.length > 0) {
      await adminClient
        .from("profiles")
        .update({ fcm_token: null })
        .in("id", invalidTokenIds);
    }

    return jsonResponse({ ok: true, sent, total: admins.length });
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    return jsonResponse({ error: message }, 400);
  }
});
