# RunPod LLM Fleet Setup

This repository contains configuration and test suites for LLMs hosted on RunPod serverless endpoints, organized by purpose.

## Architecture

Each LLM purpose has its own directory under `models/`:
- `models/coding-agent` - Qwen3-Coder-30B-A3B-Instruct (AWQ)
- `models/home-assistant` - Qwen3-8B (AWQ)

## Installation Instructions

### Prerequisites

1. **Required Tools**
   - `curl`
   - `python3` 
   - `sqlite3`
   - `npm` (for opencode)

2. **Environment Variables**
   ```bash
   export RUNPOD_API_KEY="your-runpod-api-key-here"
   ```

### Setup Steps

1. **Clone Repository**
   ```bash
   git clone <repository-url>
   cd runpod-llm-fleet
   ```

2. **Install Dependencies**
   ```bash
   # Install opencode (if needed)
   npm install -g @opencode/cli
   
   # Install required npm packages for opencode
   cd ~/.config/opencode/
   npm install
   ```

3. **Configuration**
   
   Copy the configuration file to your opencode directory:
   ```bash
   mkdir -p ~/.config/opencode/
   cp opencode-config.jsonc ~/.config/opencode/
   ```
   
   Or create a new `opencode.jsonc` file with the following content:
   ```jsonc
   {
     "$schema": "https://opencode.ai/config.json",
     "provider": {
       "runpod": {
         "npm": "@ai-sdk/openai-compatible",
         "name": "RunPod (Qwen3-Coder-30B)",
         "options": {
           "baseURL": "https://api.runpod.ai/v2/h8ins1a7nls350/openai/v1",
           "apiKey": "{env:RUNPOD_API_KEY}",
           "timeout": 600000,
           "chunkTimeout": 180000
         },
         "models": {
           "qwen3-coder-30b": {
             "name": "Qwen3 Coder 30B-A3B (RunPod)",
             "limit": {
               "context": 262144,
               "output": 32768
             }
           }
         }
       }
     }
   }
   ```

## Configuring a new RunPod endpoint

See [`docs/runpod-setup.md`](docs/runpod-setup.md) for standing up a new RunPod
serverless endpoint from scratch (template + endpoint creation via the REST API) —
needed when adding a new purpose to the fleet or rebuilding an existing endpoint.

## Running Tests

Navigate to a specific model directory and run the test suite:

```bash
cd models/coding-agent
./run_tests.sh
```

## Fleet Overview

| Purpose | Directory | Current Model | Consumer | Scaling |
|---------|-----------|---------------|----------|---------|
| Coding assistant backend | `models/coding-agent` | Qwen3-Coder-30B-A3B-Instruct (AWQ) | opencode | Scale-to-zero |
| Home Assistant conversation agent | `models/home-assistant` | Qwen3-8B (AWQ) | Home Assistant | Scale-to-zero |

## Important Notes

- The RunPod endpoints are specific to this setup and may require different API keys
- All model test suites cost small amounts of RunPod GPU time
- The `RUNPOD_API_KEY` must be exported in your shell or environment
- For debugging agent behavior, check `~/.local/share/opencode/opencode.db`