// Edge Function: manage-petugas
//
// Membuat, mengubah, dan menghapus akun login (Supabase Auth) petugas atas
// permintaan admin. Ini WAJIB berjalan di server (bukan di aplikasi Flutter)
// karena operasi ini butuh service_role key — key ini tidak boleh pernah
// dikirim ke aplikasi client, apalagi build web, karena siapa pun yang bisa
// membuka aplikasinya bisa membaca key tersebut dan mendapat akses penuh ke
// seluruh database (termasuk data nasabah).
//
// Cara deploy (lihat juga supabase/functions/manage-petugas/README.md):
//   supabase functions deploy manage-petugas
//
// SUPABASE_URL, SUPABASE_ANON_KEY, dan SUPABASE_SERVICE_ROLE_KEY otomatis
// tersedia sebagai environment variable untuk setiap Edge Function — tidak
// perlu di-set manual.

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

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    if (req.method !== "POST") {
      throw new Error("Method not allowed");
    }

    const authHeader = req.headers.get("Authorization");
    if (!authHeader) throw new Error("Missing Authorization header");

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    // Klien memakai JWT si pemanggil, dipakai untuk memverifikasi identitas
    // & role-nya. Anon key saja tidak cukup untuk operasi di bawah — sengaja.
    const callerClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });

    const { data: userRes, error: userErr } = await callerClient.auth
      .getUser();
    if (userErr || !userRes?.user) {
      throw new Error("Sesi tidak valid, silakan login ulang");
    }

    const { data: profile, error: profileErr } = await callerClient
      .from("profiles")
      .select("role")
      .eq("id", userRes.user.id)
      .single();
    if (profileErr || profile?.role !== "admin") {
      throw new Error("Hanya admin yang boleh mengelola akun petugas");
    }

    // Klien service_role — HANYA dipakai di server ini, tidak pernah dikirim
    // balik ke aplikasi.
    const adminClient = createClient(supabaseUrl, serviceRoleKey);

    const body = await req.json().catch(() => ({}));
    const action = body?.action;

    if (action === "create") {
      const nama = (body.nama ?? "").toString().trim();
      const email = (body.email ?? "").toString().trim();
      const password = (body.password ?? "").toString();
      // FIX (fitur baru): foto profil opsional, sudah di-upload ke Storage
      // dari sisi Flutter (lihat NasabahRepository.uploadAvatar) — di sini
      // cuma URL-nya yang disimpan ke baris profil yang baru dibuat.
      const avatarUrl = body.avatar_url != null
        ? body.avatar_url.toString().trim()
        : null;
      // FIX (fitur baru): field profil tambahan petugas — opsional, sama
      // seperti avatarUrl.
      const noHp = body.no_hp != null ? body.no_hp.toString().trim() : null;
      const nik = body.nik != null ? body.nik.toString().trim() : null;
      if (!nama || !email || !password) {
        throw new Error("Nama, email, dan password wajib diisi");
      }
      if (password.length < 6) {
        throw new Error("Password minimal 6 karakter");
      }

      const { data: created, error: createErr } = await adminClient.auth
        .admin.createUser({
          email,
          password,
          email_confirm: true,
        });
      if (createErr) throw createErr;

      const uid = created.user!.id;
      const { error: insertErr } = await adminClient.from("profiles").insert(
        {
          id: uid,
          nama,
          role: "petugas",
          avatar_url: avatarUrl,
          no_hp: noHp,
          nik: nik,
        },
      );
      if (insertErr) {
        // Rollback akun auth kalau insert profil gagal, supaya tidak ada
        // akun "hantu" tanpa profil.
        await adminClient.auth.admin.deleteUser(uid);
        throw insertErr;
      }

      return jsonResponse({ id: uid });
    }

    if (action === "update") {
      const id = (body.id ?? "").toString();
      if (!id) throw new Error("id wajib diisi");
      const nama = body.nama != null ? body.nama.toString().trim() : null;
      const email = body.email != null ? body.email.toString().trim() : null;
      const password = body.password != null
        ? body.password.toString()
        : null;
      // FIX (fitur baru): foto profil opsional — sama seperti create,
      // hanya menyimpan URL yang sudah di-upload dari sisi Flutter.
      const avatarUrl = body.avatar_url != null
        ? body.avatar_url.toString().trim()
        : null;
      // FIX (fitur baru): field profil tambahan petugas — opsional, sama
      // seperti avatarUrl. Dikirim string kosong ("") dari Flutter kalau
      // admin sengaja mengosongkan field itu (bukan cuma tidak diubah),
      // jadi di sini dibedakan: `undefined`/tidak dikirim = tidak diubah,
      // string (termasuk kosong) = ganti ke nilai itu.
      const noHp = body.no_hp != null ? body.no_hp.toString().trim() : null;
      const nik = body.nik != null ? body.nik.toString().trim() : null;
      const noHpProvided = Object.prototype.hasOwnProperty.call(
        body,
        "no_hp",
      );
      const nikProvided = Object.prototype.hasOwnProperty.call(body, "nik");

      if (nama || avatarUrl || noHpProvided || nikProvided) {
        const profileUpdate: Record<string, unknown> = {};
        if (nama) profileUpdate.nama = nama;
        if (avatarUrl) profileUpdate.avatar_url = avatarUrl;
        if (noHpProvided) profileUpdate.no_hp = noHp || null;
        if (nikProvided) profileUpdate.nik = nik || null;
        const { error } = await adminClient.from("profiles").update(
          profileUpdate,
        ).eq("id", id);
        if (error) throw error;
      }

      if (email || password) {
        if (password && password.length < 6) {
          throw new Error("Password minimal 6 karakter");
        }
        const attrs: Record<string, unknown> = {};
        if (email) attrs.email = email;
        if (password) attrs.password = password;
        const { error } = await adminClient.auth.admin.updateUserById(
          id,
          attrs,
        );
        if (error) throw error;
      }

      return jsonResponse({ ok: true });
    }

    if (action === "delete") {
      const id = (body.id ?? "").toString();
      if (!id) throw new Error("id wajib diisi");

      // Cegah hapus akun petugas yang masih memiliki data nasabah, supaya
      // riwayat nasabah tidak pernah kehilangan jejak petugas penanggung
      // jawabnya.
      const { count, error: countErr } = await adminClient
        .from("nasabah")
        .select("id", { count: "exact", head: true })
        .eq("petugas_id", id);
      if (countErr) throw countErr;
      if ((count ?? 0) > 0) {
        throw new Error(
          `Petugas ini masih memiliki ${count} data nasabah. ` +
            "Selesaikan atau pindahkan nasabahnya dahulu sebelum menghapus akun.",
        );
      }

      const { error: delProfileErr } = await adminClient.from("profiles")
        .delete().eq("id", id);
      if (delProfileErr) throw delProfileErr;

      const { error: delAuthErr } = await adminClient.auth.admin.deleteUser(
        id,
      );
      if (delAuthErr) throw delAuthErr;

      return jsonResponse({ ok: true });
    }

    throw new Error(`Aksi tidak dikenali: ${action}`);
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    return jsonResponse({ error: message }, 400);
  }
});
