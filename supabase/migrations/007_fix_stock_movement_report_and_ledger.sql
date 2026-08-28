-- ============================================================================
-- MIGRATION: 007_fix_stock_movement_report_and_ledger.sql
-- DESCRIPTION: Exclude IN_V_ vendor purchases, treat OPENING as baseline opening stock,
--              and left join master item_sizes to preserve all 10 yard stock categories.
-- APP: MSM One (Metaroll Steel Mart Operating System)
-- ============================================================================

-- 1. Redefine get_stock_movement_report
CREATE OR REPLACE FUNCTION public.get_stock_movement_report(
  start_date timestamp with time zone,
  end_date timestamp with time zone,
  loc_filter text DEFAULT 'ALL'::text
)
RETURNS TABLE(
  material_id bigint,
  item_name text,
  size_id bigint,
  size_label text,
  location text,
  opening_stock_mt numeric,
  period_in_mt numeric,
  period_out_mt numeric,
  closing_stock_mt numeric
)
LANGUAGE plpgsql
SECURITY INVOKER
AS $function$
BEGIN
  RETURN QUERY
  WITH base_sizes AS (
    SELECT 
      s.id AS size_id,
      s.material_id,
      COALESCE(m.item_name, 'General Material') AS item_name,
      s.size_label
    FROM public.item_sizes s
    JOIN public.materials m ON m.id = s.material_id
    WHERE m.item_name NOT IN ('Binding Wire', 'Nails', 'Barbed Wire', 'Heavy Structure ISMB')
  ),
  size_txns AS (
    SELECT
      t.size_id,
      COALESCE(UPPER(TRIM(t.location)), 'YARD') AS location,

      -- Opening Stock: baseline opening OR movements before start_date
      ROUND(SUM(
        CASE
          WHEN (t.created_at < start_date OR t.type = 'OPENING' OR t.txn_id LIKE 'OPENING-%') 
               AND UPPER(t.txn_type) IN ('IN','INWARD','OPENING_STOCK','OPENING','RETURN','ADJUSTMENT')
            THEN COALESCE(t.qty_mt, 0)
          WHEN t.created_at < start_date 
               AND UPPER(t.txn_type) IN ('OUT','OUTWARD','SALE','TRANSFER','RESERVE')
            THEN -COALESCE(t.qty_mt, 0)
          ELSE 0
        END
      )::numeric, 3) AS opening_stock_mt,

      -- Period Inward: movements during period (strictly physical receipts, excluding baseline opening and vendor purchase)
      ROUND(SUM(
        CASE
          WHEN t.created_at BETWEEN start_date AND end_date 
               AND t.type <> 'OPENING' AND t.txn_id NOT LIKE 'OPENING-%'
               AND UPPER(t.txn_type) IN ('IN','INWARD','RETURN','ADJUSTMENT')
            THEN COALESCE(t.qty_mt, 0)
          ELSE 0
        END
      )::numeric, 3) AS period_in_mt,

      -- Period Outward: physical outward during the period
      ROUND(SUM(
        CASE
          WHEN t.created_at BETWEEN start_date AND end_date 
               AND UPPER(t.txn_type) IN ('OUT','OUTWARD','SALE','TRANSFER','RESERVE')
            THEN COALESCE(t.qty_mt, 0)
          ELSE 0
        END
      )::numeric, 3) AS period_out_mt,

      -- Closing Stock: net physical stock up to end_date
      ROUND(SUM(
        CASE
          WHEN (t.created_at <= end_date OR t.type = 'OPENING' OR t.txn_id LIKE 'OPENING-%')
               AND UPPER(t.txn_type) IN ('IN','INWARD','OPENING_STOCK','OPENING','RETURN','ADJUSTMENT')
            THEN COALESCE(t.qty_mt, 0)
          WHEN t.created_at <= end_date 
               AND UPPER(t.txn_type) IN ('OUT','OUTWARD','SALE','TRANSFER','RESERVE')
            THEN -COALESCE(t.qty_mt, 0)
          ELSE 0
        END
      )::numeric, 3) AS closing_stock_mt

    FROM public.transactions t
    WHERE COALESCE(t.is_reversed, false) = false
      AND UPPER(COALESCE(t.txn_type, '')) <> 'PURCHASE'
      AND UPPER(COALESCE(t.type, ''))     <> 'PURCHASE'
      AND COALESCE(t.txn_id, '') !~~ 'IN_V_%'
      AND (loc_filter = 'ALL' OR UPPER(TRIM(t.location)) = UPPER(TRIM(loc_filter)))
    GROUP BY t.size_id, COALESCE(UPPER(TRIM(t.location)), 'YARD')
  )
  SELECT 
    b.material_id,
    b.item_name,
    b.size_id,
    b.size_label,
    COALESCE(st.location, CASE WHEN loc_filter = 'ALL' THEN 'YARD' ELSE UPPER(TRIM(loc_filter)) END) AS location,
    COALESCE(st.opening_stock_mt, 0.000) AS opening_stock_mt,
    COALESCE(st.period_in_mt, 0.000) AS period_in_mt,
    COALESCE(st.period_out_mt, 0.000) AS period_out_mt,
    COALESCE(st.closing_stock_mt, 0.000) AS closing_stock_mt
  FROM base_sizes b
  LEFT JOIN size_txns st ON st.size_id = b.size_id
  WHERE (COALESCE(st.opening_stock_mt, 0) <> 0 
      OR COALESCE(st.period_in_mt, 0) <> 0 
      OR COALESCE(st.period_out_mt, 0) <> 0 
      OR COALESCE(st.closing_stock_mt, 0) <> 0);
END;
$function$;

-- 2. Redefine get_stock_ledger to exclude IN_V_ vendor purchases and PURCHASE transactions
CREATE OR REPLACE FUNCTION public.get_stock_ledger(
  p_material_id bigint,
  p_size_id bigint DEFAULT NULL::bigint
)
RETURNS TABLE(
  txn_id bigint,
  created_at timestamp with time zone,
  txn_type text,
  qty_mt numeric,
  location text,
  remark text,
  running_balance_mt numeric
)
LANGUAGE plpgsql
SECURITY INVOKER
AS $function$
BEGIN
  RETURN QUERY
  SELECT
    t.id AS txn_id,
    t.created_at,
    t.txn_type,
    t.qty_mt,
    COALESCE(UPPER(TRIM(t.location)), 'YARD') AS location,
    t.remark,
    SUM(
      CASE
        WHEN UPPER(t.txn_type) IN ('IN','INWARD','OPENING_STOCK','OPENING','RETURN','ADJUSTMENT')
          THEN t.qty_mt
        WHEN UPPER(t.txn_type) IN ('OUT','OUTWARD','SALE','TRANSFER','RESERVE')
          THEN -t.qty_mt
        ELSE 0
      END
    ) OVER (ORDER BY t.created_at ASC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_balance_mt
  FROM public.transactions t
  WHERE t.material_id = p_material_id
    AND (p_size_id IS NULL OR t.size_id = p_size_id)
    AND COALESCE(t.is_reversed, false) = false
    AND UPPER(COALESCE(t.txn_type, '')) <> 'PURCHASE'
    AND UPPER(COALESCE(t.type, ''))     <> 'PURCHASE'
    AND COALESCE(t.txn_id, '') !~~ 'IN_V_%'
  ORDER BY t.created_at ASC;
END;
$function$;

-- 3. Grant Permissions Across Roles
GRANT EXECUTE ON FUNCTION public.get_stock_movement_report(timestamp with time zone, timestamp with time zone, text) TO anon, authenticated, postgres;
GRANT EXECUTE ON FUNCTION public.get_stock_ledger(bigint, bigint) TO anon, authenticated, postgres;

NOTIFY pgrst, 'reload schema';
