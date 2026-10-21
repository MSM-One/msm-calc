-- Migration: Add freight_charge and freight_type to transactions ledger table
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS freight_charge numeric(12, 2) DEFAULT 0.00;
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS freight_type text DEFAULT 'PER_MT';
