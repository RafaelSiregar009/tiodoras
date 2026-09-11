-- ============================================================================
-- Fitur baru: field profil tambahan untuk petugas (No. HP & NIK)
-- ============================================================================
-- Jalankan SELURUH isi file ini sekali di Supabase SQL Editor.
-- Aman dijalankan berulang (pakai IF NOT EXISTS).
-- ============================================================================

alter table public.profiles add column if not exists no_hp text;
alter table public.profiles add column if not exists nik text;
