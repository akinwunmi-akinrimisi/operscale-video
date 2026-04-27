-- ═══════════════════════════════════════════════════
-- Operscale Video Ads — Initial Schema (12 tables)
-- See docs/VISION_GRIDAI_FORK_MANUAL.md §5 for design rationale.
--
-- Schema isolation: all Operscale tables live in the `operscale` schema,
-- not `public`. The shared Supabase already has a VG-owned `public` schema
-- with collisions on `scenes`, `production_log`, `production_registers`,
-- and `prompt_configs`. See docs/foundation/infrastructure-state-day-3.md.
--
-- pipeline_stage CHECK constraint values are the canonical state names
-- from AGENT.md's LangGraph state machine. Do not deviate without
-- updating both the migration and AGENT.md atomically.
-- ═══════════════════════════════════════════════════

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

CREATE SCHEMA IF NOT EXISTS operscale;

-- ─── Customers ───────────────────────────────────────
CREATE TABLE IF NOT EXISTS operscale.customers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email TEXT NOT NULL UNIQUE,
  whatsapp_phone TEXT,
  full_name TEXT,
  business_name TEXT,
  website_or_handle TEXT,
  source TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  last_order_at TIMESTAMPTZ,
  marketing_opt_in BOOLEAN DEFAULT false
);
CREATE INDEX IF NOT EXISTS idx_customers_email ON operscale.customers(email);

-- ─── Briefs (raw form submissions) ───────────────────
CREATE TABLE IF NOT EXISTS operscale.briefs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id UUID REFERENCES operscale.customers(id) ON DELETE CASCADE,
  niche TEXT NOT NULL,
  business_name TEXT,
  website_url TEXT,
  product_or_service TEXT,
  ideal_customer TEXT,
  unique_value_prop TEXT,
  problem_solved TEXT,
  current_marketing TEXT,
  budget_for_ads_monthly_ngn INTEGER,
  preferred_tone TEXT,
  must_include TEXT,
  must_avoid TEXT,
  example_competitor TEXT,
  call_to_action TEXT,
  niche_specific_followup JSONB,
  raw_form_payload JSONB,
  save_token TEXT UNIQUE,
  submitted_at TIMESTAMPTZ DEFAULT now(),
  brand_colors_hex JSONB,
  logo_storage_url TEXT
);
CREATE INDEX IF NOT EXISTS idx_briefs_customer ON operscale.briefs(customer_id);
CREATE INDEX IF NOT EXISTS idx_briefs_save_token ON operscale.briefs(save_token);

-- ─── Orders ──────────────────────────────────────────
-- pipeline_stage values match the LangGraph state machine in AGENT.md.
CREATE TABLE IF NOT EXISTS operscale.orders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id UUID NOT NULL REFERENCES operscale.customers(id),
  brief_id UUID NOT NULL REFERENCES operscale.briefs(id),
  tier TEXT NOT NULL CHECK (tier IN ('pilot', 'standard', 'creative_pod')),
  amount_paid_kobo INTEGER NOT NULL,
  paystack_tx_ref TEXT UNIQUE,
  niche TEXT NOT NULL,
  production_register TEXT,
  pipeline_stage TEXT NOT NULL DEFAULT 'pending'
    CHECK (pipeline_stage IN (
      'pending',
      'brief_received',
      'gate_0_review',
      'generating_angles',
      'quote_delivery',
      'awaiting_payment',
      'generating_script',
      'gate_1_review',
      'gate_2_review',
      'avatar_consent_check',
      'avatar_quality_check',
      'production_documentary',
      'production_avatar',
      'render_complete',
      'gate_3_review',
      'deliver',
      'post_delivery_followup_scheduled',
      'delivered',
      'failed',
      'refunded',
      'archived'
    )),
  delivery_email_sent_at TIMESTAMPTZ,
  delivery_whatsapp_sent_at TIMESTAMPTZ,
  strategy_call_scheduled_for TIMESTAMPTZ,
  strategy_call_completed_at TIMESTAMPTZ,
  performance_checkin_email_sent_at TIMESTAMPTZ,
  performance_checkin_response JSONB,
  total_cost_usd DECIMAL(8,4),
  cost_breakdown JSONB,
  retry_count INTEGER DEFAULT 0,
  supervisor_alerted BOOLEAN DEFAULT false,
  last_error TEXT,
  last_processed_decision_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_orders_customer ON operscale.orders(customer_id);
CREATE INDEX IF NOT EXISTS idx_orders_stage ON operscale.orders(pipeline_stage);
CREATE INDEX IF NOT EXISTS idx_orders_created ON operscale.orders(created_at DESC);

-- ─── Videos (1 per Pilot/Standard order; 3 per Creative Pod) ─
CREATE TABLE IF NOT EXISTS operscale.videos (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL REFERENCES operscale.orders(id) ON DELETE CASCADE,
  video_number INTEGER NOT NULL,
  approved_angle JSONB,
  script_json JSONB,
  scene_count INTEGER,
  duration_seconds INTEGER,
  drive_video_url TEXT,
  delivered_url TEXT,
  signed_url_expires_at TIMESTAMPTZ,
  thumbnail_url TEXT,
  audio_progress TEXT DEFAULT 'pending',
  images_progress TEXT DEFAULT 'pending',
  i2v_progress TEXT DEFAULT 'pending',
  assembly_status TEXT DEFAULT 'pending',
  caption_burn_status TEXT DEFAULT 'pending',
  revisions_used INT DEFAULT 0,
  revisions_max INT,
  total_cost_usd DECIMAL(6,4),
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE (order_id, video_number)
);
CREATE INDEX IF NOT EXISTS idx_videos_order ON operscale.videos(order_id);

-- ─── Scenes (column names cloned VERBATIM from VG) ───
-- Render workflows reference these by name; do not rename.
CREATE TABLE IF NOT EXISTS operscale.scenes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  video_id UUID NOT NULL REFERENCES operscale.videos(id) ON DELETE CASCADE,
  order_id UUID NOT NULL REFERENCES operscale.orders(id) ON DELETE CASCADE,
  scene_number INTEGER NOT NULL,
  scene_id TEXT NOT NULL,
  narration_text TEXT,
  image_prompt TEXT,
  visual_type TEXT,
  emotional_beat TEXT,
  chapter TEXT,
  audio_duration_ms INTEGER,
  audio_file_drive_id TEXT,
  audio_file_url TEXT,
  start_time_ms BIGINT,
  end_time_ms BIGINT,
  image_url TEXT,
  image_drive_id TEXT,
  video_url TEXT,
  video_drive_id TEXT,
  audio_status TEXT DEFAULT 'pending',
  image_status TEXT DEFAULT 'pending',
  video_status TEXT DEFAULT 'pending',
  clip_status TEXT DEFAULT 'pending',
  composition_prefix TEXT,
  color_mood TEXT,
  zoom_direction TEXT,
  transition_to_next TEXT,
  caption_highlight_word TEXT
    CHECK (caption_highlight_word IS NULL
           OR caption_highlight_word !~ '[`$|;<>&\\]'),
  selective_color_element TEXT,
  skipped BOOLEAN DEFAULT false,
  skip_reason TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_scenes_video ON operscale.scenes(video_id);
CREATE INDEX IF NOT EXISTS idx_scenes_order ON operscale.scenes(order_id);
CREATE INDEX IF NOT EXISTS idx_scenes_status ON operscale.scenes(video_id, audio_status);

-- ─── Production registers ────────────────────────────
CREATE TABLE IF NOT EXISTS operscale.production_registers (
  register_id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  short_description TEXT,
  accent_color_hex TEXT,
  config JSONB NOT NULL,
  version INTEGER DEFAULT 1,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- ─── Prompt configs ──────────────────────────────────
CREATE TABLE IF NOT EXISTS operscale.prompt_configs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  niche TEXT NOT NULL,
  prompt_type TEXT NOT NULL,
  prompt_text TEXT NOT NULL,
  version INTEGER DEFAULT 1,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE (niche, prompt_type, version)
);

-- ─── Production log ──────────────────────────────────
CREATE TABLE IF NOT EXISTS operscale.production_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID REFERENCES operscale.orders(id),
  video_id UUID REFERENCES operscale.videos(id),
  customer_id UUID REFERENCES operscale.customers(id),
  stage TEXT NOT NULL,
  action TEXT NOT NULL,
  details JSONB,
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_log_order ON operscale.production_log(order_id);
CREATE INDEX IF NOT EXISTS idx_log_video ON operscale.production_log(video_id);

-- ─── Payments (Paystack) ─────────────────────────────
CREATE TABLE IF NOT EXISTS operscale.payments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL REFERENCES operscale.orders(id),
  customer_id UUID NOT NULL REFERENCES operscale.customers(id),
  paystack_tx_ref TEXT NOT NULL UNIQUE,
  amount_kobo INTEGER NOT NULL,
  currency TEXT DEFAULT 'NGN',
  status TEXT NOT NULL CHECK (status IN ('pending', 'paid', 'failed', 'refunded')),
  payment_method TEXT,
  webhook_payload JSONB,
  paid_at TIMESTAMPTZ,
  refunded_at TIMESTAMPTZ,
  refund_reason TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_payments_order ON operscale.payments(order_id);

-- ─── Gate decisions (founder audit) ──────────────────
CREATE TABLE IF NOT EXISTS operscale.gate_decisions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL REFERENCES operscale.orders(id),
  video_id UUID REFERENCES operscale.videos(id),
  gate_number TEXT NOT NULL CHECK (gate_number IN ('0', '1', '2', '3-bis', '3')),
  decision TEXT NOT NULL CHECK (decision IN ('approved', 'rejected', 'edit_requested', 'regenerate', 'refund', 'override_with_warning')),
  feedback TEXT,
  decided_by TEXT NOT NULL,
  decided_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_gates_order ON operscale.gate_decisions(order_id);
CREATE INDEX IF NOT EXISTS idx_gates_decided_at ON operscale.gate_decisions(decided_at DESC);

-- ─── Order consent (Creative Pod custom avatar + voice cloning) ─
CREATE TABLE IF NOT EXISTS operscale.order_consent (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL REFERENCES operscale.orders(id) ON DELETE CASCADE,
  consent_type TEXT NOT NULL CHECK (consent_type IN ('voice_clone', 'face_avatar', 'both')),
  photo_storage_url TEXT,
  voice_sample_storage_url TEXT,
  consent_text_version TEXT NOT NULL,
  consent_text_hash TEXT NOT NULL,
  signed_at TIMESTAMPTZ DEFAULT now(),
  signed_via TEXT DEFAULT 'notion_form',
  ip_address INET,
  revocation_at TIMESTAMPTZ,
  quality_check_status TEXT DEFAULT 'pending'
    CHECK (quality_check_status IN ('pending', 'passed', 'rejected', 'overridden_with_warning'))
);

-- ─── LLM call audit ──────────────────────────────────
CREATE TABLE IF NOT EXISTS operscale.llm_calls (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID REFERENCES operscale.orders(id),
  video_id UUID REFERENCES operscale.videos(id),
  node_name TEXT NOT NULL,
  model TEXT NOT NULL,
  input_tokens INTEGER,
  output_tokens INTEGER,
  cost_usd DECIMAL(8,6),
  duration_ms INTEGER,
  called_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_llm_calls_order ON operscale.llm_calls(order_id);

-- ─── Realtime publication ────────────────────────────
ALTER PUBLICATION supabase_realtime ADD TABLE operscale.orders;
ALTER PUBLICATION supabase_realtime ADD TABLE operscale.videos;
ALTER PUBLICATION supabase_realtime ADD TABLE operscale.scenes;
ALTER PUBLICATION supabase_realtime ADD TABLE operscale.production_log;
ALTER PUBLICATION supabase_realtime ADD TABLE operscale.gate_decisions;

-- ─── REPLICA IDENTITY FULL (gotcha #4 from fork manual) ─
ALTER TABLE operscale.orders REPLICA IDENTITY FULL;
ALTER TABLE operscale.videos REPLICA IDENTITY FULL;
ALTER TABLE operscale.scenes REPLICA IDENTITY FULL;
ALTER TABLE operscale.production_log REPLICA IDENTITY FULL;
ALTER TABLE operscale.gate_decisions REPLICA IDENTITY FULL;

-- ─── RLS lockdown ────────────────────────────────────
DO $$
DECLARE t TEXT;
BEGIN
  FOR t IN SELECT unnest(ARRAY[
    'customers','briefs','orders','videos','scenes','production_log',
    'payments','gate_decisions','order_consent','llm_calls',
    'production_registers','prompt_configs'
  ])
  LOOP
    EXECUTE format('ALTER TABLE operscale.%I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('CREATE POLICY %I_anon_deny ON operscale.%I AS RESTRICTIVE FOR ALL TO anon USING (false)', t, t);
    EXECUTE format('CREATE POLICY %I_service_role_all ON operscale.%I AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true)', t, t);
  END LOOP;
END $$;
