# Opencode Qwen Configuration for Command Execution

This configuration enables more permissive command execution capabilities similar to Claude's setup.

## Main Configuration File

Create `~/.config/opencode/opencode.jsonc` with:

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
  },
  "tools": {
    "enabled": true,
    "allowed": [
      "Bash",
      "Read",
      "Write",
      "WebSearch"
    ],
    "permissions": {
      "Bash": {
        "allow": [
          "cd",
          "ls",
          "pwd",
          "echo",
          "cat",
          "grep",
          "find",
          "python3",
          "npm",
          "git",
          "docker"
        ],
        "restrictions": {
          "maxExecutionTime": 30000,
          "maxOutputSize": 1048576,
          "allowedDirectories": [
            "/tmp",
            "/Users/kmomchil/IdeaProjects/lanbat/runpod-llm-fleet"
          ]
        }
      },
      "Read": {
        "allow": [
          "/Users/kmomchil/IdeaProjects/lanbat/runpod-llm-fleet/**"
        ]
      },
      "Write": {
        "allow": [
          "/tmp/**",
          "/Users/kmomchil/IdeaProjects/lanbat/runpod-llm-fleet/**"
        ]
      }
    }
  },
  "execution": {
    "sandbox": {
      "enabled": false,
      "allowFileAccess": true,
      "allowNetwork": true,
      "allowShell": true
    }
  }
}
```

## Environment Setup Script

Create `setup-opencode-qwen.sh`:

```bash
#!/bin/bash
# Setup script for opencode Qwen with command execution

echo "Setting up opencode Qwen with command execution..."

# Create configuration directory if it doesn't exist
mkdir -p ~/.config/opencode/

# Create the configuration file
cat > ~/.config/opencode/opencode.jsonc << 'EOF'
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
  },
  "tools": {
    "enabled": true,
    "allowed": [
      "Bash",
      "Read",
      "Write",
      "WebSearch"
    ],
    "permissions": {
      "Bash": {
        "allow": [
          "cd",
          "ls",
          "pwd",
          "echo",
          "cat",
          "grep",
          "find",
          "python3",
          "npm",
          "git",
          "docker"
        ],
        "restrictions": {
          "maxExecutionTime": 30000,
          "maxOutputSize": 1048576,
          "allowedDirectories": [
            "/tmp",
            "/Users/kmomchil/IdeaProjects/lanbat/runpod-llm-fleet"
          ]
        }
      },
      "Read": {
        "allow": [
          "/Users/kmomchil/IdeaProjects/lanbat/runpod-llm-fleet/**"
        ]
      },
      "Write": {
        "allow": [
          "/tmp/**",
          "/Users/kmomchil/IdeaProjects/lanbat/runpod-llm-fleet/**"
        ]
      }
    }
  },
  "execution": {
    "sandbox": {
      "enabled": false,
      "allowFileAccess": true,
      "allowNetwork": true,
      "allowShell": true
    }
  }
}
EOF

echo "Configuration created at ~/.config/opencode/opencode.jsonc"

# Verify the configuration
echo "Validating configuration..."
if command -v jq &> /dev/null; then
    jq . ~/.config/opencode/opencode.jsonc > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "✅ Configuration is valid JSON"
    else
        echo "❌ Configuration has invalid JSON"
    fi
else
    echo "jq not installed, skipping JSON validation"
fi

echo "Setup complete! Now you can use opencode with command execution capabilities."
echo "Remember to export your RUNPOD_API_KEY:"
echo "export RUNPOD_API_KEY=\"your-api-key-here\""