# Live Stream Integration & Security Rules (TikTok & Kwai)

1. **Untrusted External Input**: Every payload received from TikTok Live, Kwai Live, WebSocket bridges, or webhooks (usernames, comment text, avatar URLs, gift IDs) is **untrusted input**.
   - Never pass chat strings into `Expression`, `OS.execute()`, BBCode (`RichTextLabel.bbcode_enabled` without escaping `[`), file paths, or SQL/shell commands.
   - Truncate display usernames to 24 characters and strip control/zero-width characters.
2. **Idempotency & Deduplication**: Every live event (`msg_id` / `event_id`) MUST pass through an LRU deduplication window (minimum 5,000 IDs / 10 minutes) so reconnect replays never double-trigger paid gift actions.
3. **Rate Limiting & Anti-Flood Queue**:
   - Coalesce high-frequency like/comment bursts into aggregated ticks (e.g., 100ms–250ms windows).
   - Cap concurrent physics/visual gift spawns per frame and queue high-tier gifts in a priority ring buffer.
4. **Simulator First**: Every gameplay mechanic triggered by TikTok/Kwai events MUST be testable offline using the built-in `MockLiveEventSimulator` without requiring an active live stream.
5. **Credential Hygiene**: Never hardcode API keys, session cookies, stream keys, or Tripo keys (`tsk_...`) in code, scenes, or markdown files. Store secrets exclusively in environment variables or gitignored `.env`.
