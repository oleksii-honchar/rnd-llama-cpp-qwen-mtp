# Smoke-test samples (`llama-swap/smoke-samples`)

Default **`SMOKE_SAMPLES_DIR`** for **`scripts/smoke-config4.sh`** (under the `llama-swap` repo root). Same text fixtures as `../llama-cpp/smoke-samples`; keep them in sync when you change prompts.

## Audio (Whisper)

- **Default path:** `sample-uk-1.wav` in this directory (add locally; binary not always checked in). **`smoke-config4.sh`** does not send Whisper by default (config-4 is chat-focused); other stacks may use `language=uk` when the file basename is `sample-uk-1.*`.
- **Override:** `SMOKE_WHISPER_AUDIO=/path/to/file` or any `.wav` / `.webm` / `.mp3` / `.ogg` in this dir.

## Text (smoke-config4 chat)

| File | Purpose |
|------|---------|
| `chat-prompt.txt` | Full file → `/v1/chat/completions` user message |
