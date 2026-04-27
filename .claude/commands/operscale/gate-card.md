Generate the Notion gate review card payload for a given gate transition.

Input: order_id, gate_number (0|1|2|3-bis|3), context (brief excerpt or render URL)
Output: Notion API request body with:
  - Title field: "[Gate N] <customer business name> — <tier>"
  - Status: pending
  - Decision dropdown options matching the gate
  - Brief context block
  - Direct link to the relevant render or script

For Gate 3-bis (avatar quality), include the photo URL and the 6 quality checkpoints.
For Gate 3, include the final render URL with a 7-day signed URL.
