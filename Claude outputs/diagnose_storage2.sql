-- ============================================================================
-- Versi gabungan: satu query saja, hasilnya satu baris berisi semua info
-- diagnosa (klik tiap sel di hasil untuk lihat detail JSON-nya).
-- ============================================================================
select
  (select row_to_json(t) from (
    select relrowsecurity, relforcerowsecurity
    from pg_class where oid = 'storage.objects'::regclass
  ) t) as rls_status,
  (select jsonb_agg(row_to_json(p)) from (
    select policyname, cmd, permissive, roles, qual, with_check
    from pg_policies
    where schemaname = 'storage' and tablename = 'objects'
    order by cmd, policyname
  ) p) as policies,
  (select jsonb_agg(row_to_json(b)) from (
    select id, name, public, file_size_limit, allowed_mime_types
    from storage.buckets where id ilike '%avatar%'
  ) b) as buckets;
