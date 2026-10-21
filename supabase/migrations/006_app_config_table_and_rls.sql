-- ============================================================================
-- MIGRATION: 006_app_config_table_and_rls.sql
-- DESCRIPTION: App configuration table for OTA / APK Update Management
-- APP: MSM One (Metaroll Steel Mart Operating System)
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.app_config (
    id bigint PRIMARY KEY DEFAULT 1,
    latest_version text NOT NULL DEFAULT '1.0.0',
    min_supported_version text NOT NULL DEFAULT '1.0.0',
    apk_url text NOT NULL DEFAULT '',
    release_notes text DEFAULT '',
    is_force_update boolean NOT NULL DEFAULT false,
    updated_at timestamptz DEFAULT now()
);

-- Seed default singleton row if missing
INSERT INTO public.app_config (id, latest_version, min_supported_version, apk_url, release_notes, is_force_update)
VALUES (
    1,
    '1.0.1',
    '1.0.0',
    'https://wztyczjrakjsoifwtdda.supabase.co/storage/v1/object/public/app-releases/msm_one_v1.0.1.apk',
    'In-app seamless updates, timezone date fixes, and real-time inventory synchronization.',
    false
)
ON CONFLICT (id) DO NOTHING;

-- RLS & Grants
ALTER TABLE public.app_config ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow public read access on app_config" ON public.app_config;
CREATE POLICY "Allow public read access on app_config" ON public.app_config FOR SELECT TO anon, authenticated, postgres USING (true);

GRANT SELECT ON public.app_config TO anon, authenticated, postgres;

NOTIFY pgrst, 'reload schema';
