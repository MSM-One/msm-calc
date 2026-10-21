-- ================================================================
-- MSM Calc: handle_new_user trigger function fix for Google OAuth
-- Run this in: Supabase Dashboard -> SQL Editor or via migrations
-- ================================================================

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger 
LANGUAGE plpgsql
SECURITY DEFINER -- Ensures function runs with bypass system privileges
AS $$
BEGIN
  INSERT INTO public.users (id, email, user_name, role, status)
  VALUES (
    new.id,
    new.email,
    COALESCE(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name', 'New User'), -- Fallback for name
    'staff',     -- Corrected to lowercase 'staff' to comply with check constraint: role = ANY (ARRAY['admin'::text, 'manager'::text, 'staff'::text])
    'PENDING'    -- Default validation status lock to prevent instant unapproved app usage
  );
  RETURN NEW;
END;
$$;
