# Opencode RunPod Environment Setup

This guide will walk you through setting up the complete environment to run opencode with RunPod integration.

## Prerequisites

### 1. Install Node.js and npm
```bash
# Check if Node.js is installed
node --version
npm --version

# If not installed, install Node.js (LTS version recommended)
# On macOS with Homebrew:
brew install node

# On Ubuntu/Debian:
sudo apt update
sudo apt install nodejs npm
```

### 2. Install Opencode CLI
```bash
# Install globally (recommended)
npm install -g @opencode/cli

# Verify installation
opencode --version
```

### 3. Set Up Configuration Directory
```bash
# Create the opencode configuration directory
mkdir -p ~/.config/opencode/

# Copy the configuration file we created
cp opencode-config.jsonc ~/.config/opencode/
```

### 4. Set Environment Variables
```bash
# Add to your shell profile (~/.zshrc or ~/.bashrc)
echo 'export RUNPOD_API_KEY="your-runpod-api-key-here"' >> ~/.zshrc
source ~/.zshrc
```

## Configuration Files

### Main Configuration: `~/.config/opencode/opencode.jsonc`
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

## Testing the Setup

### 1. Verify Configuration
```bash
# Test the configuration
opencode config validate
```

### 2. Test Connection to RunPod
```bash
# Test if you can connect to the RunPod endpoint
opencode chat --model runpod:qwen3-coder-30b "Hello, can you help with Python development?"
```

### 3. Run Models Tests
```bash
# Navigate to a model directory and run tests
cd models/coding-agent
./run_tests.sh
```

## Environment Validation Script

Create a validation script to ensure everything is configured correctly:

```bash
#!/bin/bash
# validate-opencode.sh

echo "Checking opencode installation..."
if command -v opencode &> /dev/null; then
    echo "✅ Opencode CLI is installed"
    opencode --version
else
    echo "❌ Opencode CLI is not installed"
    exit 1
fi

echo "Checking configuration..."
if [ -f ~/.config/opencode/opencode.jsonc ]; then
    echo "✅ Configuration file found"
    # Validate JSON structure
    jq . ~/.config/opencode/opencode.jsonc > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "✅ Configuration file is valid JSON"
    else
        echo "❌ Configuration file has invalid JSON"
    fi
else
    echo "❌ Configuration file not found"
fi

echo "Checking API key..."
if [ -n "$RUNPOD_API_KEY" ]; then
    echo "✅ RUNPOD_API_KEY is set"
else
    echo "⚠️  RUNPOD_API_KEY is not set. Please export it."
fi

echo "Setup validation complete!"
```

Make it executable:
```bash
chmod +x validate-opencode.sh
./validate-opencode.sh
```

## Troubleshooting

### Common Issues:
1. **API Key Errors** - Make sure RUNPOD_API_KEY is properly exported
2. **Network Issues** - Check connectivity to RunPod endpoints
3. **Permission Issues** - Ensure proper file permissions for config directory

### Debugging Commands:
```bash
# Check opencode logs
opencode debug

# List available models
opencode models list

# Show current configuration
opencode config show
```

## Usage Examples

Once everything is configured, you can use opencode in various ways:

### Interactive Chat:
```bash
opencode chat --model runpod:qwen3-coder-30b
```

### Run a specific prompt:
```bash
opencode run --model runpod:qwen3-coder-30b "Explain quantum computing in simple terms"
```

### Using with external directories:
```bash
# With a specific working directory
opencode run --model runpod:qwen3-coder-30b --working-dir /path/to/project
```

## Next Steps

1. Replace `"your-runpod-api-key-here"` with your actual RunPod API key
2. Test the connection with a simple query
3. Run the model tests to verify everything works correctly

This setup will allow you to use opencode with the RunPod LLM fleet as described in the original repository.