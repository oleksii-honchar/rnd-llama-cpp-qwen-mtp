# Qwopus3.6-27B MTP with llama.cpp

One-command MTP speculative decoding for Qwopus3.6-27B-v1-preview using llama.cpp PR #22673.

## What is MTP?

Multi-Token Prediction (MTP) allows the model to draft multiple tokens per forward pass. The draft tokens are verified in a single additional forward pass, yielding ~2.4× throughput speedup with ~72% draft acceptance rate — all with the same model weights and no extra GPU memory beyond the MTP layer overhead.

## Quick Start

```bash
git clone https://github.com/oleksii-honchar/rnd-llama-cpp-qwen-mtp.git
cd rnd-llama-cpp-qwen-mtp
./start.sh
```

This downloads ~66 GB of models, transplants MTP tensors, and starts the server on port 8014.

## Lifecycle

```bash
./start.sh          # Start (downloads models if missing)
./stop.sh           # Stop the container
./restart.sh        # Stop + start
./start.sh --re-build   # Rebuild Docker image from scratch
./start.sh --force      # Force re-download of all models
```

Optional flags:
- `--re-build` — force a full Docker image rebuild with `--no-cache`
- `--force` — force re-download of all models (including re-transplant)

## Bootstrap Pipeline

1. Download target GGUFs (Qwopus3.6-27B-v1-preview Q6_K ~22 GB + Q4_K_M ~16.5 GB)
2. Download source MTP GGUF (am17an Qwen3.6-27B-MTP Q8_0, ~30 GB)
3. Transplant MTP tensors using `transplant_mtp.py` (for both quantizations)
4. Download chat template
5. Build and start Docker container

## Requirements

- Docker + NVIDIA runtime
- GPU: 32 GB VRAM for Q6_K (RTX 5090 recommended), 24 GB for Q4_K_M (RTX 4090 sufficient)
- ~66 GB disk for models (both quantizations)
- Python 3 (for transplant)

## Model Aliases

Two quantizations, exclusive (one at a time):

**Q6_K** (higher quality, ~25 GB VRAM):
- `qwopus36-27b` — thinking on (default)
- `qwopus36-27b-precise` — thinking off
- `qwopus36-27b-instruct` — no thinking

**Q4_K_M** (lower VRAM, ~20 GB VRAM):
- `qwopus36-27b-q4` — thinking on (default)
- `qwopus36-27b-q4-precise` — thinking off
- `qwopus36-27b-q4-instruct` — no thinking

## Benchmarks

```bash
./llama-swap/scripts/benchmark.config9.sh
```

Runs three benchmark suites:
1. **Throughput** (`llama-bench`) — tokens/second, baseline only (no MTP speculative decoding)
2. **Perplexity** (`llama-perplexity`) — quality score on WikiText-2
3. **MTP live server** — measures MTP acceptance rate + tokens/second against the running server

For the MTP live server test, the server must be running on port 8014.

## Alternative Configuration: TQ3_4S TurboQuant (config-1)

In addition to the MTP config (config-9), this repo includes **config-1** using **TQ3_4S TurboQuant** mixed-precision MoE compression from the [turbo-tan/llama.cpp-tq3](https://github.com/turbo-tan/llama.cpp-tq3) fork.

**Single model:**

| Model | Config ID | Aliases | Size |
|-------|-----------|---------|------|
| Qwen3.6-35B-A3B-TQ3_4S | `qwen36-35b-tq3` | `qwen36-35b-tq3-precise` | ~12.4 GiB |

**Start config-1:**

```bash
./llama-swap/scripts/swap.start.config1.sh
# Or with rebuild:
./llama-swap/scripts/swap.start.config1.sh --re-build
```

**Smoke test config-1:**

```bash
./llama-swap/scripts/smoke-config1.sh
```

**Benchmark config-1 (optional):**

```bash
./llama-swap/scripts/benchmark.config1.sh
```



## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `Unknown flag: config-9` | `start.sh` does not accept positional args. Use `./start.sh` or `./start.sh --re-build` |
| Docker build fails on GPU arch | Override CUDA arch: `docker build --build-arg GGML_CUDA_ARCHITECTURES=89 ...` (89 for Ada/RTX 40xx, 120 for Blackwell/RTX 50xx) |
| Transplant fails | Delete the output GGUF and re-run: `rm llama-models/models/Qwopus3.6-27B-v1-preview-MTP-Q6_K.gguf && ./start.sh --force` |
| Server not healthy on port 8014 | Check logs: `docker logs llama-swap` or `docker compose -f llama-swap/docker-compose/swap-local-config9.yaml logs` |
| `jq` not found (benchmark) | Install jq: `brew install jq` (macOS) or `apt install jq` (Linux) |

## Configuration

- Model config: `llama-swap/configs/config-9.yaml`
- Docker compose: `llama-swap/docker-compose/swap-local-config9.yaml`
- Dockerfile: `llama-swap/docker-files/Dockerfile.llama-cpp-beta`

### MTP Settings

- `--spec-type mtp` — native MTP speculative decoding (llama.cpp PR #22673)
- `--spec-draft-n-max 4` — up to 4 draft tokens per forward pass
- Expected: ~72% draft acceptance, ~2.4× throughput speedup

### Docker Build Args

| Arg | Default | Description |
|-----|---------|-------------|
| `GGML_CUDA_ARCHITECTURES` | `120` (Blackwell/RTX 5090) | CUDA GPU architecture |
| `GGML_NATIVE` | `ON` | Native CPU optimizations |
| `BUILD_JOBS` | auto (`nproc`) | Parallel build jobs |

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `MODELS_MOUNT_PATH` | `../llama-models/models` | Volume mount for model files |
| `LLAMA_SWAP_URL` | `http://localhost:8014` | Server URL (for benchmark) |
| `CURL_CONNECT` | `15` | Curl connect timeout (seconds) |
| `CURL_MAX_TIME` | `300` | Curl max time (seconds) |
| `MTP_BENCH_MAX_TOKENS` | `4096` | Max tokens for MTP benchmark samples |

## Smoke Test

After the server is running, test it:

```bash
curl http://localhost:8014/v1/models | jq '.data[].id'
```

Expected output: `qwopus36-27b` and `qwopus36-27b-q4`

## Directory Structure

```
rnd-llama-cpp-qwen-mtp/
├── start.sh                              # one-command entry point
├── .gitignore
├── llama-swap/
│   ├── configs/config-9.yaml             # model config (aliases, params, MTP settings)
│   ├── configs/config-1.yaml             # TQ3_4S TurboQuant model config (single model: Qwen3.6-35B-A3B)
│   ├── docker-compose/swap-local-config9.yaml  # Docker Compose
│   ├── docker-compose/swap-local-config1.yaml  # Docker Compose for TQ3_4S
│   ├── docker-files/Dockerfile.llama-cpp-beta   # custom Dockerfile (PR #22673)
│   ├── docker-files/Dockerfile.llama-cpp-tq3   # TQ3_4S Dockerfile (turbo-tan/llama.cpp-tq3)
│   ├── scripts/
│   │   ├── swap.start.config9.sh         # start orchestration
│   │   ├── ensure-models-config9.sh      # bootstrap (download + transplant)
│   │   ├── benchmark.config9.sh          # benchmark harness
│   │   ├── swap.start.config1.sh         # start orchestration for TQ3_4S
│   │   ├── ensure-models-config1.sh      # bootstrap for TQ3_4S models
│   │   ├── smoke-config1.sh              # smoke test for TQ3_4S
│   │   └── benchmark.config1.sh          # benchmark harness for TQ3_4S (optional)
│   └── smoke-samples/chat-prompt.txt     # smoke test prompt
└── llama-models/
    ├── models/                           # downloaded model files (gitignored)
    └── scripts/
        ├── transplant_mtp.py             # core MTP transplant tool
        ├── transplant-qwopus36-mtp-q6_k.sh    # transplant orchestrator (Q6_K)
        ├── transplant-qwopus36-mtp-q4_k_m.sh  # transplant orchestrator (Q4_K_M)
        ├── download-qwopus36-27b-v1-preview-q6_k.sh    # target GGUF download (Q6_K)
        ├── download-qwopus36-27b-v1-preview-q4_k_m.sh  # target GGUF download (Q4_K_M)
        ├── download-qwen36-27b-mtp-q8_0.sh         # source MTP GGUF download
        ├── download-better-qwen3.6-chat-template.sh # chat template download
        ├── download-qwen36-35b-a3b-tq3_4s.sh           # Qwen3.6 35B-A3B TQ3_4S
        ├── download-qwen36-35b-a3b-mtp-tq3_4s.sh       # Qwen3.6 35B-A3B MTP TQ3_4S
        ├── download-qwen36-35b-a3b-mmproj.sh           # Qwen3.6 35B-A3B mmproj
        └── download-qwen36-chat-template-v13.sh          # Qwen3.6 chat template v13
```

## Sources

- llama.cpp PR #22673 (native MTP): https://github.com/ggml-org/llama.cpp/pull/22673
- Target model: https://huggingface.co/Jackrong/Qwopus3.6-27B-v1-preview-GGUF
- Source MTP model: https://huggingface.co/am17an/Qwen3.6-27B-MTP-GGUF
- Chat template: https://github.com/oleksii-honchar/better-qwen3.6-chat-template.jinja
