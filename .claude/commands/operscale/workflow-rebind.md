Take a Vision GridAI workflow JSON file path as input. Produce a rebound version for Operscale:

1. Webhook path: prefix with `/operscale/` (e.g., `/webhook/production/tts` → `/webhook/operscale/production/tts`)
2. Workflow name: prefix with `OPS_` (e.g., `WF_TTS_AUDIO` → `OPS_TTS_AUDIO`)
3. SQL FK rebind: `topic_id` → `video_id`, `topics` → `videos`, `project_id` → `order_id`, `projects` → `orders`
4. Path remap: `/tmp/production/` → `/tmp/operscale-production/`
5. Verify every Authorization header value starts with `=` (the missing-`=` expression trap)
6. Verify no inline credentials — must reference n8n credential by ID

Output the rebound JSON. Highlight any node that requires manual review.
