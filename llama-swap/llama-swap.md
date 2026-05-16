# llama-swap — Setup 1

Single OpenAI-compatible endpoint (port **8014** on host) for embedding, STT, and chat with **QwQ-32B (thinking)** 65k + **Qwen3.5-9B** worker.

**Always-on**: `qwen3-embedding-8b` (Qwen3-Embedding-8B Q4_K_M), `whisper-large-v3-turbo`, `qwen3.5-32b` (QwQ-32B thinking, 65k context). **Worker (swap)**: `qwen3.5-9b` (Qwen3.5-9B Q4_K_M), TTL 600s. Embedding has TTL 300s and can unload when idle so the proxy can switch to whisper or worker LLM. Main chat model is QwQ-32B (reasoning/thinking); 9B loads on demand for lighter tasks.

## Setup 1 topology

| Role        | Model                    | Config key         | Notes                    |
|------------|---------------------------|--------------------|--------------------------|
| Always-on  | Qwen3-Embedding-8B Q4_K_M | `qwen3-embedding-8b` | ~5–6 GB VRAM             |
| Always-on  | Whisper large-v3-turbo   | `whisper-large-v3-turbo` | STT                      |
| Always-on  | QwQ-32B (thinking) 65k    | `qwen3.5-32b`      | Q4_K_M + KV q4_0, reasoning |
| Worker     | Qwen3.5-9B Q4_K_M        | `qwen3.5-9b`       | Swap on demand, TTL 600s |

**Total always-on VRAM**: ~21–23 GB (fits 32 GB GPU).

### Model layer counts (for `-ngl`)

`-ngl` is the **number of layers** to offload to GPU (not a percentage). Use these counts when tuning partial offload (e.g. `-ngl 48` for half of 32B):

| Model (config key) | Layers | Note |
|--------------------|--------|------|
| Qwen3-Embedding-8B | 32 | `qwen3-embedding-8b` |
| QwQ-32B / Qwen3.5-32B | 64 | `qwen3.5-32b` |
| Qwen3.5-9B | 40 | `qwen3.5-9b` |
| Whisper large-v3-turbo | — | Encoder; not layer-offload in the same way |

With **`-ngl 99`** (config default), all layers for embedding and LLMs are on GPU. To verify a GGUF: `python gguf-dump.py --no-tensors /path/to/model.gguf` and check `block_count` (or architecture-specific equivalent).

## Requirements

- Docker with NVIDIA runtime
- Network `mammoth-net` (created by `./start.sh` if missing)
- Models in `MODELS_MOUNT_PATH` (default **`../llama-models/models`** next to `llama-swap`, i.e. **`mammoth-lan/llama-models/models`**) — see below

## Required model files

Place these under the host path that is mounted as `/models` in the container (`MODELS_MOUNT_PATH`, default **`mammoth-lan/llama-models/models`**). **`./start.sh`** (default **swap.config4**) runs **`scripts/ensure-models-config4.sh`**. **`scripts/swap.start.local.sh`** runs the same ensure step, then **`docker-compose/swap-local.yaml`** (mounts **configs/config-4.yaml**).

| File | Download script | Source |
|------|-----------------|--------|
| `Qwopus3.5-27B-v3.5-Q4_K_M.gguf`, `mmproj.gguf` | `../llama-models/scripts/download-qwopus3_5-27b-v3_5-q4_k_m.sh` | Qwopus 27B v3.5 Q4_K_M |
| `Qwopus3.5-9B-v3-Q4_K_M.gguf` | `../llama-models/scripts/download-qwopus3_5-9b-v3-q4_k_m.sh` | Qwopus 9B v3 |
| `gemma-4-31B-it-UD-Q4_K_XL.gguf`, `mmproj-BF16.gguf`, `google-gemma-4-31B-it-interleaved.jinja` | `../llama-models/scripts/download-gemma-4-31b-it-ud-q4_k_xl.sh` | Gemma 4 31B IT |
| `Qwen3.5-27B-heretic.Q4_K_M.gguf`, `Qwen3.5-27B-heretic.mmproj-f16.gguf` | `../llama-models/scripts/download-qwen3_5-27b-heretic-q4_k_m.sh` | Qwen3.5 heretic 27B |
| `Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf`, `Qwen3.6-35B-A3B-mmproj-BF16.gguf` | `../llama-models/scripts/download-qwen36-35b-a3b-ud-q4_k_xl.sh` | Qwen3.6 35B-A3B |

`scripts/ensure-models-config4.sh` runs these from **`llama-models/scripts/`** (paths relative to **`llama-swap`**). Filenames must match the config (or edit **`configs/config-4.yaml`**).

**Config-1 (TQ3_4S TurboQuant):** `scripts/ensure-models-config1.sh` runs these from **`llama-models/scripts/`**.

| File | Download script | Source |
|------|-----------------|--------|
| `Qwen3.6-35B-A3B-MTP-TQ3_4S.gguf` | `../llama-models/scripts/download-qwen36-35b-a3b-mtp-tq3_4s.sh` | Qwen3.6 35B-A3B MTP TQ3_4S |
| `Qwen3.6-35B-A3B-TQ3_4S.gguf` | `../llama-models/scripts/download-qwen36-35b-a3b-tq3_4s.sh` | Qwen3.6 35B-A3B TQ3_4S |
| `chat_template-v13.jinja` | `../llama-models/scripts/download-qwen36-chat-template-v13.sh` | Qwen3.6 chat template v13 |

## Scripts & configs

| Config | Compose file | Dockerfile | Image |
|--------|--------------|------------|-----|
| **swap.config4** (default) | `docker-compose/swap-local-config4.yaml` | `docker-files/Dockerfile.llama-cpp` → **configs/config-4.yaml** | `llama-cpp:latest` |
| **swap.config1** (TQ3_4S) | `docker-compose/swap-local-config1.yaml` | `docker-files/Dockerfile.llama-cpp-tq3` → **configs/config-1.yaml** | `llama-cpp-tq3:latest` |
| **swap.config5** | `docker-compose/swap-local-config5.yaml` | `docker-files/Dockerfile.llama-cpp-tq3` → **configs/config-5.yaml** | `llama-cpp-tq3:latest` |
| **swap.local** | `docker-compose/swap-local.yaml` | `docker-files/Dockerfile.local` (base image + `whisper-server` binary; same **config-4.yaml** mount) | `llama-swap-local:latest` |

- `./start.sh` — **swap.config4** (ensure models + compose up)
- `./start.sh swap.config4` — explicit (same as default)
- **`scripts/swap.start.local.sh`** — **swap.local** + **`ensure-models-config4.sh`**
- `./start.sh --list` or `./start.sh -l` — list configs
- `./stop.sh` / `./restart.sh` — stop / stop then start default
- **`scripts/smoke-config4.sh`** — smoke **config-4** (chat models in catalog). Example: `LLAMA_SWAP_URL=http://host:8014 ./scripts/smoke-config4.sh`
- **`scripts/swap.start.config1.sh`** — **swap.config1** (TQ3_4S: Qwen3.6-35B-A3B) + **`ensure-models-config1.sh`**
- **`scripts/smoke-config1.sh`** — smoke **config-1** (qwen36-35b-tq3)

## Config files

- **configs/config-4.yaml** — **swap.config4**: matrix concurrency for Qwopus 27B/9B, Gemma 4 31B, Qwen3.5 heretic 27B, Qwen3.6 35B-A3B (see file header). Mounted by **swap-local-config4.yaml** and **swap-local.yaml**.
- **configs/config-1.yaml** — **swap.config1**: TQ3_4S TurboQuant single model — Qwen3.6-35B-A3B (see file header for VRAM constraints). Mounted by **swap-local-config1.yaml**.
- Add more `.yaml` files under **`configs/`** if needed; point the compose volume at the file you want.

## Healthcheck

Pattern similar to `mammoth-lan/mcp-gateway/healthcheck.sh`: query the API and optionally verify that `/v1/models` lists the models from a config.

- **./healthcheck.sh** — Check `LLAMA_SWAP_URL` (default `http://localhost:8014`) `/v1/models` returns 200 only.
- **./healthcheck.sh config-4** — Verify models listed **and** call each model (one request per model: embedding or chat) to warm and verify. Uses `WARMUP_TIMEOUT` (default 120s) per request; whisper is skipped.
- **./healthcheck.sh config-4 --no-warmup** — Verify models listed only, no model calls.
- **./healthcheck.sh --all** — For each `configs/*.yaml`, verify expected models and run warmup per config (service must be running).
- **./healthcheck.sh -v [config]** — Verbose. Override URL: `LLAMA_SWAP_URL=http://mammoth:8014 ./healthcheck.sh config-4`

## Debugging model load and execution

### 1. Container logs (load and runtime)

All model processes (llama-server, whisper-server) run inside the same container. **By default the proxy does not forward child stdout**, so you only see proxy lines (e.g. `[WARN] <qwen3.5-32b> ExitError`) and not the actual “loading model…” output from llama-server. To see **model load progress and backend errors**, set in your config (top-level, next to `healthCheckTimeout`):

```yaml
logToStdout: "both"   # proxy + upstream (llama-server / whisper-server stdout)
```

Options: **`proxy`** (default, proxy only), **`upstream`** (child stdout only), **`both`** (interleaved), **`none`**. Optional: **`logLevel: "debug"`** for more proxy-side detail. Then restart and run:

```bash
# Follow logs (Ctrl+C to stop)
docker logs -f llama-swap

# Last 200 lines (e.g. after a failed request)
docker logs --tail 200 llama-swap

# Only errors (if your runtime prefixes them)
docker logs llama-swap 2>&1 | grep -i -E "error|fail|panic|cannot|refused"
```

**What to look for**

- **Load**: Each model’s `llama-server` / `whisper-server` startup: “loading model”, “loaded”, “listening”, or “error opening”, “no such file”, “out of memory”. Match lines to a model by the **model path** (e.g. `/models/QwQ-32B-Q4_K_M.gguf`) or by the **port** if the proxy logs it.
- **Execution**: Requests are handled by the proxy; backend errors may appear as new log lines when you send a request. Use **verbose healthcheck** or **targeted curl** (below) to tie a failure to a specific model.

**Example log output (config-4)** — With **`logToStdout: "both"`**, follow `load_model` lines for each GGUF under `/models/…` as the matrix solver starts backends.

Optional: save full logs, e.g. `docker logs llama-swap > logs/config-4.logs 2>&1`.

### 2. Healthcheck: which model failed

Use the healthcheck to see which model fails on **load** (not listed) or **first request** (warmup):

```bash
# Verbose: list models then one request per model (embedding or chat); shows which model fails and HTTP + API error
./healthcheck.sh config-4
```

On failure you’ll see e.g. `qwen3.5-32b (chat) ... FAIL (HTTP 503)` and, in verbose mode, the API `error.message` (e.g. “model not loaded”, “timeout”). Increase timeout for slow or large models:

```bash
WARMUP_TIMEOUT=180 ./healthcheck.sh config-4
```

To only check that models are **listed** (no execution):

```bash
./healthcheck.sh config-4 --no-warmup
```

### 3. Targeted requests (curl) per model

Hit the proxy and force a specific model so you can see response and errors for that model only.

**List models** (confirm what the proxy sees):

```bash
curl -s http://localhost:8014/v1/models | jq '.data[].id'
```

**Embedding model** (replace `qwen3-embedding-8b` with your embedding id if different):

```bash
curl -s -w "\nHTTP %{http_code}\n" -X POST http://localhost:8014/v1/embeddings \
  -H "Content-Type: application/json" \
  -d '{"model":"qwen3-embedding-8b","input":"debug test"}' | tail -20
```

**Chat model** (replace `qwen3.5-9b` with the chat model id):

```bash
curl -s -w "\nHTTP %{http_code}\n" -X POST http://localhost:8014/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"qwen3.5-9b","messages":[{"role":"user","content":"Hi"}],"max_tokens":5}' | tail -30
```

Check the HTTP code and the JSON body (e.g. `error.message`) and correlate with `docker logs` at the same time.

### 4. Isolate one model (clean load logs)

To get **one process** in the logs and avoid interleaving:

1. Copy your config (e.g. `configs/config-4.yaml`) to a new file (e.g. `configs/config-4-debug.yaml`).
2. Under `groups`, keep a single group and a single `members` entry (e.g. only `qwen3.5-9b`).
3. Under `models`, leave only that model’s block.
4. Mount the new file as `/app/config.yaml` in compose (or temporarily replace the mounted file), restart, then run:

   ```bash
   docker logs -f llama-swap
   ```

You’ll see only that model’s startup and its requests.

### 5. Common load/execution failures

| Symptom | Likely cause | What to do |
|--------|----------------|------------|
| Model not in `/v1/models` | Config typo, wrong mount, or process failed to start | Check `docker logs` for that model path; confirm config is mounted and model id matches. |
| “No such file” / 404 on backend | Model path in config doesn’t match files in `/models` | Check `MODELS_MOUNT_PATH` and volume mount; list files in container: `docker exec llama-swap ls -la /models`. |
| OOM / “out of memory” | GPU or host RAM too small for model + context | Reduce `-ngl` (e.g. 48 for 32B), or reduce `-c` / `-ub`; or disable `--no-mmap` to use mmap (trades RAM for disk). |
| **35B-A3B: `cudaMalloc failed` / `failed to allocate compute pp buffers`** | 35B needs ~24 GB VRAM; with embedding + 27B (or 9B) already loaded, total exceeds 32 GB (e.g. RTX 5090). | Reduce **`-ngl`** or **`-c`** for 35B; or run a config where 35B is the only LLM so VRAM is free when it starts. |
| Warmup timeout / 504 | Model slow to load or first inference | Increase `WARMUP_TIMEOUT` (healthcheck) and/or model `ttl` in config; watch `docker logs` during the request. |
| Wrong or empty response | Wrong model selected, or thinking/reasoning format | Ensure request `model` matches the id in config; for reasoning, see config header and [Unsloth: enable/disable thinking](https://unsloth.ai/docs/models/qwen3.5#how-to-enable-or-disable-reasoning-and-thinking). |

**Clients** — Use the **`model`** id from **`/v1/models`** that matches **`configs/config-4.yaml`** (and any **`aliases`** you defined there).

### 6. Run one backend outside Docker (deep debug)

To see a single model’s logs without the proxy or other processes:

1. From the model’s block in your config, copy the `cmd` (the `llama-server` or `whisper-server` line and its flags).
2. Replace `${PORT}` with a fixed port (e.g. `8015`), `--host 0.0.0.0`, and the same `--model` path (point to a local copy of the GGUF if needed).
3. Run that command on the host (with the same CUDA/runtime as in Docker). All load and inference logs will be for that model only.

Example (adjust paths and port):

```bash
llama-server --port 8015 --host 0.0.0.0 --model /path/to/Qwen3.5-9B-Q4_K_M.gguf -c 32768 -ngl 99
# In another terminal:
curl -X POST http://localhost:8015/v1/chat/completions -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"Hi"}],"max_tokens":5}'
```

This helps confirm whether a problem is with the model/backend or with the proxy/config.

## Run

```bash
# Optional: set models directory (default: mammoth-lan/llama-models/models)
export MODELS_MOUNT_PATH=/path/to/models
./start.sh
```

## API

- **Host**: `http://localhost:8014/v1` (container: `http://mammoth:8080/v1`)
- List models: `curl http://localhost:8014/v1/models`
- Unload worker: `curl -X POST http://localhost:8014/api/unload -H "Content-Type: application/json" -d '{"model": "qwen3.5-9b"}'`

## Scripts

No Infisical; scripts use plain `docker compose`.

- `./start.sh` — create network if needed, then `docker compose up -d --build` (mounts config per compose file)
- `./stop.sh` — stop the llama-swap container
- `./restart.sh` — stop then start default config
- `./healthcheck.sh [config-name]` — check API, validate models, and call each model (warmup); use `--no-warmup` to skip model calls. See **Debugging model load and execution** for per-model debugging.

## Config & image

- **configs/** — Currently **config-4.yaml** and **config-5.yaml**; compose mounts it as `/app/config.yaml`. Use **`logToStdout: "both"`** to forward child **llama-server** stdout into `docker logs`. Many blocks use **`--no-mmap`** and **`--mlock`** so weights stay resident; see **llama-server options** below.
- **Images**:
  - **swap.config4** uses `llama-cpp:latest` built from **Dockerfile.llama-cpp** (CUDA **llama-server** from ggml-org/llama.cpp source).
  - **swap.config5** uses `llama-cpp-tq3:latest` built from **Dockerfile.llama-cpp-tq3** (CUDA **llama-server** from turbo-tan/llama.cpp-tq3 fork with TQ3_4S support).
  - **swap.config1** uses `llama-cpp-tq3:latest` built from **Dockerfile.llama-cpp-tq3** (CUDA **llama-server** from turbo-tan/llama.cpp-tq3 fork with TQ3_4S TurboQuant support). Single model.
  - **swap.local** uses `llama-swap-local:latest` built from **Dockerfile.local** (official **llama-swap:cuda** + bundled **whisper-server**).

### llama-server options (config files)

| Option | Meaning | Use |
|--------|--------|-----|
| **`--no-mmap`** | Load the whole model into **host RAM** up front. **Without** this flag (default), the process uses **memory-mapping (mmap)**: the model file is mapped into virtual address space and the OS loads chunks from disk on demand into **RAM** (not VRAM—this is host memory). So mmap can lower RAM use but inference may touch disk. | Used in this setup so models live in RAM. **VRAM** is separate: controlled by `-ngl` (how many layers run on the GPU). |
| **`--mlock`** | Lock process memory so the OS **does not swap** it to disk. Requires sufficient host RAM (e.g. 96 GB on mammoth). | Used with `--no-mmap` to keep all model data in RAM and avoid disk I/O. |
| **`-ngl` / `--n-gpu-layers`** | Number of model layers to run on GPU; rest run on CPU. | **99** = all on GPU (default, max speed). **Lower** (e.g. **48** for 32B) = fewer layers on GPU → **saves VRAM**, slower. Use when VRAM is tight; edit the model `cmd` in the config file (e.g. change `-ngl 99` to `-ngl 48` for `qwen3.5-32b`). |

### Config parameter descriptions (llama-server)

Parameters used in `configs/config-4.yaml` and similar stacks:

| Param | Meaning | Example |
|-------|--------|---------------------|
| **`-c`** | Context size: max number of tokens the model can process. | Embedding: `8192`; 32B/9B: `65536` / `32768`. |
| **`-ub`** | Batch size for prompt processing (number of tokens to process in parallel when filling context). | `8192` (embedding); `65536` / `32768` for LLMs (often same as `-c`). |
| **`-ngl`** | Number of layers to run on GPU; rest on CPU. | **99** = all on GPU. See **Model layer counts** above for per-model values. |
| **`--no-mmap`** | Load full model into RAM (no memory-mapping). | Used on all llama-server models so data is in RAM. |
| **`--mlock`** | Lock memory so the OS does not swap it to disk. | Used on mammoth (96 GB RAM) to avoid disk I/O. |
| **`--cache-type-k`** / **`--cache-type-v`** | Quantization type for KV cache (keys / values). Reduces VRAM for long context. | `q4_0` on 32B for ~65k context. |
| **`--reasoning-format`** | How to expose reasoning/thinking output (e.g. `<think>`). Values: **`deepseek`** (reasoning in `message.reasoning_content`), **`hide`** (omit from response), **`none`** (return in main content). | **`deepseek`** for QwQ-32B so clients get reasoning and final answer separately. |
| **`--embedding`** | Run as embedding model (no chat completion). | Used for `qwen3-embedding-8b`. |
| **`--pooling last`** | Embedding pooling: use last token (or `mean`). | `last` for Qwen3 embedding. |
| **`--model`** | Path to GGUF (or whisper bin) in the container. | `/models/...` (mounted from host). |
| **`--warmup`** / **`--no-webui`** | Warm up model on load; disable web UI. | Typical for server use. |

Full doc (other topologies, memory, thinking options): see `Contexts/oLHo/qwen setup/1-llamacpp qwen.md` in the repo.
