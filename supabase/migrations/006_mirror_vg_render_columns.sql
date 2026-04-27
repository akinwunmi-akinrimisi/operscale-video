-- ═══════════════════════════════════════════════════
-- Operscale Video Ads — 006: mirror VG public.topics + scenes columns
--
-- Day-6 Task 6.3 (real TTS render against fake-order-1) failed at
-- "Load Topic Drive Info" with `column videos.drive_subfolder_ids does
-- not exist`. Root cause: the original 001_initial.sql defined
-- operscale.videos with 21 columns chosen by the plan author, but VG's
-- inherited render-core workflows expect the full set of columns from
-- VG's public.topics (58 cols).
--
-- Per Foundation principle "inherit untouched": this migration mirrors
-- every column from VG public.topics into operscale.videos that we don't
-- already have, EXCLUDING:
--   - YouTube-specific fields (yt_*, youtube_*, published_at, review_*,
--     refinement_history, playlist_*, etc.)
--   - VG FK columns (project_id, topic_id) - we use order_id, video_id
--   - Columns we already have under the same name
--
-- Same approach for operscale.scenes: 11 columns (b_roll_insert,
-- pipeline_stage, has_video, video_placement_*, video_clip_*,
-- scene_classification + reasoning, production_register) that the
-- rebound workflows reference.
--
-- Idempotent: every ADD COLUMN uses IF NOT EXISTS.
--
-- Defaults preserved exactly so the rebound workflows see the same
-- state-machine starting values they did under VG (status='pending',
-- script_attempts=0, t2v_progress='pending', country_target='GENERAL',
-- video_ratio='100_0', etc.).
--
-- This is a Foundation-phase pragmatic completion of the schema, not
-- a final design. Customer-flow phase may prune unused columns once
-- we know which paths actually run for ad-generation.
-- ═══════════════════════════════════════════════════

-- 107 columns to add to operscale.videos

-- --- operscale.videos ---
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS seo_title text;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS narrative_hook text;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS key_segments text;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS estimated_cpm text;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS viral_potential text;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS status text DEFAULT 'pending'::text;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS last_status_change timestamptz DEFAULT now();
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS error_log text;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS script_metadata jsonb;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS word_count integer;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS script_attempts integer DEFAULT 0;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS script_force_passed boolean DEFAULT false;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS script_quality_score numeric;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS script_evaluation jsonb;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS script_pass_scores jsonb;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS script_review_status text DEFAULT 'pending'::text;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS script_review_feedback text;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS t2v_progress text DEFAULT 'pending'::text;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS drive_folder_id text;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS drive_subfolder_ids jsonb;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS video_review_status text DEFAULT 'pending'::text;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS video_review_feedback text;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS total_cost numeric;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS cost_breakdown jsonb;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS retry_count integer DEFAULT 0;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS supervisor_alerted boolean DEFAULT false;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS force_regenerate boolean DEFAULT false;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS pipeline_stage text DEFAULT 'pending'::text;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS core_domain_framework text;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS primary_problem_trigger text;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS target_audience_segment text;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS psychographics text;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS key_emotional_drivers text;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS video_style_structure text;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS content_angle_blue_ocean text;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS viewer_search_intent text;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS practical_takeaways text;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS script_metadata_extended jsonb;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS outlier_score integer DEFAULT 50;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS algorithm_momentum varchar DEFAULT 'stable'::character varying;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS competing_videos_count integer;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS outlier_ratio double precision;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS avg_views_top10 bigint;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS outlier_reasoning text;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS outlier_data_available boolean DEFAULT true;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS outlier_scored_at timestamptz;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS seo_score integer DEFAULT 50;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS seo_classification varchar;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS primary_keyword varchar;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS keyword_variants jsonb;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS search_volume_proxy integer;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS competition_level varchar;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS seo_opportunity_summary text;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS seo_scored_at timestamptz;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS title_options jsonb;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS selected_title varchar;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS title_ctr_score integer;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS title_recommended_index integer;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS title_ctr_reasoning text;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS title_variants_generated_at timestamptz;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS title_selected_at timestamptz;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS thumbnail_ctr_score integer;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS thumbnail_score_breakdown jsonb;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS thumbnail_decision varchar;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS thumbnail_primary_weakness text;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS thumbnail_improvement_suggestions jsonb;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS thumbnail_regen_attempts integer DEFAULT 0;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS thumbnail_regen_history jsonb;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS thumbnail_scored_at timestamptz;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS predicted_performance_score integer;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS pps_light varchar;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS pps_recommendation text;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS pps_breakdown jsonb;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS pps_missing_inputs jsonb;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS pps_calculated_at timestamptz;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS viral_moments jsonb;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS top_3_viral_moments_idx jsonb;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS viral_tagged_at timestamptz;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS hook_scores jsonb;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS avg_hook_score integer;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS weak_hook_count integer;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS hook_analyzed_at timestamptz;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS production_cost_usd numeric;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS cost_breakdown_snapshot jsonb;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS estimated_revenue_30d numeric;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS roi_pct numeric;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS break_even_views integer;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS revenue_attributed_at timestamptz;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS video_ratio text DEFAULT '100_0'::text;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS estimated_image_cost numeric;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS estimated_video_cost numeric;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS estimated_total_media_cost numeric;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS cost_option_selected_at timestamptz;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS production_mode text;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS production_register text;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS register_recommendations jsonb;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS register_selected_at timestamptz;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS register_era_detected text;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS register_analyzed_at timestamptz;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS niche_variant text;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS country_target text DEFAULT 'GENERAL'::text;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS gap_score numeric;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS gap_score_modifiers jsonb;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS required_disclaimers text[];
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS demonetization_audit_result jsonb;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS compliance_review_status text DEFAULT 'not_required'::text;
ALTER TABLE operscale.videos ADD COLUMN IF NOT EXISTS next_video_directives jsonb;

-- --- operscale.scenes ---
-- 11 columns to add to operscale.scenes

ALTER TABLE operscale.scenes ADD COLUMN IF NOT EXISTS b_roll_insert text;
ALTER TABLE operscale.scenes ADD COLUMN IF NOT EXISTS pipeline_stage text DEFAULT 'pending'::text;
ALTER TABLE operscale.scenes ADD COLUMN IF NOT EXISTS has_video boolean DEFAULT false;
ALTER TABLE operscale.scenes ADD COLUMN IF NOT EXISTS video_placement_start_ms integer;
ALTER TABLE operscale.scenes ADD COLUMN IF NOT EXISTS video_placement_end_ms integer;
ALTER TABLE operscale.scenes ADD COLUMN IF NOT EXISTS video_clip_url text;
ALTER TABLE operscale.scenes ADD COLUMN IF NOT EXISTS video_clip_duration_ms integer;
ALTER TABLE operscale.scenes ADD COLUMN IF NOT EXISTS video_upscaled_url text;
ALTER TABLE operscale.scenes ADD COLUMN IF NOT EXISTS scene_classification text;
ALTER TABLE operscale.scenes ADD COLUMN IF NOT EXISTS classification_reasoning text;
ALTER TABLE operscale.scenes ADD COLUMN IF NOT EXISTS production_register text;
