CREATE EXTENSION IF NOT EXISTS pgcrypto;
SET search_path = public, extensions;

-- Create coaches table (linked to auth.users)
CREATE TABLE public.coaches (
  id UUID PRIMARY KEY DEFAULT auth.uid(),
  email TEXT UNIQUE NOT NULL,
  name TEXT,
  avatar_url TEXT,
  locale TEXT DEFAULT 'it',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT coaches_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE
);

-- Enable RLS on coaches
ALTER TABLE public.coaches ENABLE ROW LEVEL SECURITY;

-- RLS policy: coaches can only see their own profile
CREATE POLICY "Coaches can view own profile"
  ON public.coaches
  FOR SELECT
  USING (id = auth.uid());

CREATE POLICY "Coaches can update own profile"
  ON public.coaches
  FOR UPDATE
  USING (id = auth.uid());

-- Create plans table
CREATE TABLE public.plans (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  coach_id UUID NOT NULL REFERENCES public.coaches(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  goal TEXT,
  duration_weeks INT CHECK (duration_weeks >= 1 AND duration_weeks <= 52),
  is_template BOOLEAN DEFAULT false,
  content_json JSONB NOT NULL DEFAULT '{"weeks":[]}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Enable RLS on plans
ALTER TABLE public.plans ENABLE ROW LEVEL SECURITY;

-- RLS policies for plans
CREATE POLICY "Coaches can view own plans"
  ON public.plans
  FOR SELECT
  USING (coach_id = auth.uid());

CREATE POLICY "Coaches can create plans"
  ON public.plans
  FOR INSERT
  WITH CHECK (coach_id = auth.uid());

CREATE POLICY "Coaches can update own plans"
  ON public.plans
  FOR UPDATE
  USING (coach_id = auth.uid());

CREATE POLICY "Coaches can delete own plans"
  ON public.plans
  FOR DELETE
  USING (coach_id = auth.uid());

-- Create plan_shares table
CREATE TABLE public.plan_shares (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  plan_id UUID NOT NULL REFERENCES public.plans(id) ON DELETE CASCADE,
  token TEXT UNIQUE NOT NULL DEFAULT encode(gen_random_bytes(32), 'base64'),
  expires_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Enable RLS on plan_shares
ALTER TABLE public.plan_shares ENABLE ROW LEVEL SECURITY;

-- RLS policies for plan_shares
CREATE POLICY "Coaches can view shares for own plans"
  ON public.plan_shares
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.plans
      WHERE plans.id = plan_shares.plan_id
      AND plans.coach_id = auth.uid()
    )
  );

CREATE POLICY "Coaches can create shares for own plans"
  ON public.plan_shares
  FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.plans
      WHERE plans.id = plan_shares.plan_id
      AND plans.coach_id = auth.uid()
    )
  );

CREATE POLICY "Coaches can delete shares for own plans"
  ON public.plan_shares
  FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM public.plans
      WHERE plans.id = plan_shares.plan_id
      AND plans.coach_id = auth.uid()
    )
  );

-- Create trigger function for updating plans.updated_at
CREATE OR REPLACE FUNCTION public.update_plan_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

-- Create trigger for plans.updated_at
CREATE TRIGGER update_plans_updated_at
  BEFORE UPDATE ON public.plans
  FOR EACH ROW
  EXECUTE FUNCTION public.update_plan_updated_at();

-- Create function to handle new user signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.coaches (id, email, name)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'name', '')
  );
  RETURN NEW;
END;
$$;

-- Create trigger for new user signup
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

-- Create public RPC function for read-only sharing
CREATE OR REPLACE FUNCTION public.get_shared_plan(share_token TEXT)
RETURNS TABLE (
  plan_name TEXT,
  goal TEXT,
  duration_weeks INT,
  content_json JSONB,
  coach_name TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    p.name,
    p.goal,
    p.duration_weeks,
    p.content_json,
    c.name as coach_name
  FROM public.plan_shares ps
  JOIN public.plans p ON ps.plan_id = p.id
  JOIN public.coaches c ON p.coach_id = c.id
  WHERE ps.token = share_token
  AND (ps.expires_at IS NULL OR ps.expires_at > now());
END;
$$;

-- Grant execute permission to anonymous users for the sharing function
GRANT EXECUTE ON FUNCTION public.get_shared_plan(TEXT) TO anon;
GRANT EXECUTE ON FUNCTION public.get_shared_plan(TEXT) TO authenticated;