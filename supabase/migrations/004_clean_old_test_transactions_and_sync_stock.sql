-- ============================================================================
-- MIGRATION: 004_clean_old_test_transactions_and_sync_stock.sql
-- DESCRIPTION: Reverse legacy pre-migration test transactions & link v_current_stock
-- APP: MSM One (Metaroll Steel Mart Operating System)
-- ============================================================================

-- STEP 1: Mark old pre-migration test transactions as reversed so only official Master Sheet opening stock is active
UPDATE public.transactions
SET is_reversed = true
WHERE remark = 'Opening Stock Reset 02/08/2026' OR remark IS NULL OR txn_id LIKE 'TXN-INIT-%' OR txn_id LIKE 'RESET-020826-%';

-- STEP 2: Ensure all 75 official Master Sheet Opening Stock transactions are active for location 'YARD'
INSERT INTO public.transactions (
    txn_id,
    txn_type,
    type,
    material_id,
    size_id,
    qty_mt,
    location,
    user_name,
    is_reversed,
    remark,
    created_at
)
SELECT 
    'OPENING-' || s.id::text || '-20260806' AS txn_id,
    'IN' AS txn_type,
    'OPENING' AS type,
    s.material_id,
    s.id AS size_id,
    s.current_stock_in AS qty_mt,
    'YARD' AS location,
    'SYSTEM_MIGRATION' AS user_name,
    false AS is_reversed,
    'Master Sheet Opening Stock Seeding (Location: YARD)' AS remark,
    now() AS created_at
FROM public.item_sizes s
WHERE s.current_stock_in > 0
ON CONFLICT (txn_id) DO UPDATE SET
    qty_mt = EXCLUDED.qty_mt,
    location = 'YARD',
    is_reversed = false,
    created_at = now();

-- STEP 3: Re-create v_current_stock View purely based on active transactions + base sizes
DROP VIEW IF EXISTS public.v_low_stock CASCADE;
DROP VIEW IF EXISTS public.v_non_moving_stock CASCADE;
DROP VIEW IF EXISTS public.v_current_stock CASCADE;

CREATE OR REPLACE VIEW public.v_current_stock 
WITH (security_invoker = true) AS
WITH base_sizes AS (
  SELECT 
    s.id AS size_id,
    s.material_id,
    COALESCE(m.item_name, 'General Material') AS item_name,
    s.size_label
  FROM public.item_sizes s
  LEFT JOIN public.materials m ON m.id = s.material_id
),
txn_totals AS (
  SELECT 
    t.material_id,
    t.size_id,
    COALESCE(UPPER(t.location), 'YARD') AS location,
    SUM(
      CASE 
        WHEN UPPER(t.txn_type) IN ('IN', 'RETURN', 'ADJUSTMENT', 'OPENING') OR UPPER(t.type) IN ('IN', 'RETURN', 'ADJUSTMENT', 'OPENING') THEN COALESCE(t.qty_mt, 0)
        WHEN UPPER(t.txn_type) IN ('OUT', 'RESERVE') OR UPPER(t.type) IN ('OUT', 'RESERVE') THEN -COALESCE(t.qty_mt, 0)
        ELSE 0
      END
    ) AS txn_net
  FROM public.transactions t
  WHERE COALESCE(t.is_reversed, false) = false
  GROUP BY t.material_id, t.size_id, COALESCE(UPPER(t.location), 'YARD')
)
SELECT 
  b.size_id,
  b.material_id,
  b.item_name,
  b.size_label,
  t.location,
  t.txn_net::numeric(12, 4) AS net_stock_mt,
  5.0::numeric(12, 4) AS min_stock
FROM base_sizes b
JOIN txn_totals t ON t.material_id = b.material_id AND t.size_id = b.size_id
WHERE t.txn_net <> 0;

-- STEP 4: Re-create Low Stock & Non-Moving Stock Views
CREATE OR REPLACE VIEW public.v_low_stock 
WITH (security_invoker = true) AS
SELECT *
FROM public.v_current_stock
WHERE net_stock_mt <= min_stock;

CREATE OR REPLACE VIEW public.v_non_moving_stock 
WITH (security_invoker = true) AS
SELECT *
FROM public.v_current_stock
WHERE net_stock_mt > 0;

-- STEP 5: Grant Read Permissions
GRANT SELECT ON public.v_current_stock TO anon, authenticated, postgres;
GRANT SELECT ON public.v_todays_summary TO anon, authenticated, postgres;
GRANT SELECT ON public.v_vendor_summary TO anon, authenticated, postgres;
GRANT SELECT ON public.v_low_stock TO anon, authenticated, postgres;
GRANT SELECT ON public.v_non_moving_stock TO anon, authenticated, postgres;
GRANT SELECT ON public.transactions TO anon, authenticated, postgres;

NOTIFY pgrst, 'reload schema';
