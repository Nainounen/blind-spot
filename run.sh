#!/bin/zsh
set -e
cd "$(dirname "$0")"

# Build
swift build -c release 2>&1

BINARY=".build/release/BlindSpot"

# API key: prefer env var, else prompt once and store it
if [[ -z "$OPENAI_API_KEY" ]]; then
    KEY_FILE="$HOME/.config/blind-spot/api-key"
    if [[ ! -f "$KEY_FILE" ]]; then
        mkdir -p "$HOME/.config/blind-spot"
        echo -n "Enter your OpenAI API key: "
        read -s KEY
        echo
        echo "$KEY" > "$KEY_FILE"
        chmod 600 "$KEY_FILE"
        echo "Saved to $KEY_FILE"
    fi
fi

PROMPT_NAME="${1:-}"
if [[ -n "$PROMPT_NAME" ]]; then
    PROMPT_FILE="$HOME/.config/blind-spot/prompts/${PROMPT_NAME}.txt"
    if [[ ! -f "$PROMPT_FILE" ]]; then
        echo "Error: prompt file not found: $PROMPT_FILE"
        exit 1
    fi
    echo "Starting BlindSpot with prompt: $PROMPT_NAME"
    export BLIND_SPOT_PROMPT="$PROMPT_NAME"
else
    echo "Starting BlindSpot — press Cmd+Shift+Space over selected text."
fi

exec "$BINARY"
