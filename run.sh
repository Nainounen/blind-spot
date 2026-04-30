#!/bin/zsh
set -e
cd "$(dirname "$0")"

# Build
swift build -c release 2>&1

BINARY=".build/release/BlindSpot"

# ── Argument parsing ──────────────────────────────────────────────────────────
PROMPT_NAME=""
PROVIDER="openai"
MODEL=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --provider|-p)
            PROVIDER="$2"; shift 2 ;;
        --model|-m)
            MODEL="$2"; shift 2 ;;
        --help|-h)
            echo "Usage: ./run.sh [prompt-name] [--provider PROVIDER] [--model MODEL]"
            echo ""
            echo "  prompt-name          Name of a file in ~/.config/blind-spot/prompts/"
            echo "  --provider, -p       openai (default) | anthropic | gemini | deepseek | ollama"
            echo "  --model, -m          Override the default model for the chosen provider"
            echo ""
            echo "Provider defaults:"
            echo "  openai      →  gpt-4o"
            echo "  anthropic   →  claude-opus-4-5"
            echo "  gemini      →  gemini-2.5-flash"
            echo "  deepseek    →  deepseek-chat"
            echo "  ollama      →  llama3.2  (no API key needed, must be running locally)"
            echo ""
            echo "Examples:"
            echo "  ./run.sh"
            echo "  ./run.sh m165"
            echo "  ./run.sh --provider anthropic"
            echo "  ./run.sh m165 --provider anthropic --model claude-haiku-4-5"
            echo "  ./run.sh --provider ollama --model mistral"
            exit 0
            ;;
        -*)
            echo "Unknown flag: $1  (run ./run.sh --help for usage)"
            exit 1
            ;;
        *)
            [[ -z "$PROMPT_NAME" ]] && PROMPT_NAME="$1"
            shift ;;
    esac
done

# ── Validate provider ────────────────────────────────────────────────────────
case "$PROVIDER" in
    openai|anthropic|gemini|deepseek|ollama) ;;
    *)
        echo "Error: unknown provider '$PROVIDER'"
        echo "Supported providers: openai, anthropic, gemini, deepseek, ollama"
        exit 1 ;;
esac

export BLIND_SPOT_PROVIDER="$PROVIDER"
[[ -n "$MODEL" ]] && export BLIND_SPOT_MODEL="$MODEL"

# ── API key setup (skipped for Ollama) ───────────────────────────────────────
if [[ "$PROVIDER" != "ollama" ]]; then
    KEY_DIR="$HOME/.config/blind-spot/keys"
    KEY_FILE="$KEY_DIR/$PROVIDER"

    # Check whether a key is already available from any source
    HAS_KEY=false
    [[ -n "${BLIND_SPOT_API_KEY:-}" ]]                             && HAS_KEY=true
    [[ "$PROVIDER" == "openai" && -n "${OPENAI_API_KEY:-}" ]]     && HAS_KEY=true
    [[ -f "$KEY_FILE" ]]                                           && HAS_KEY=true
    # Legacy single-file location (openai only, backwards compat)
    [[ "$PROVIDER" == "openai" && -f "$HOME/.config/blind-spot/api-key" ]] && HAS_KEY=true

    if [[ "$HAS_KEY" == "false" ]]; then
        mkdir -p "$KEY_DIR"
        case "$PROVIDER" in
            openai)    LABEL="OpenAI" ;;
            anthropic) LABEL="Anthropic" ;;
            gemini)    LABEL="Gemini" ;;
            deepseek)  LABEL="DeepSeek" ;;
            *)         LABEL="$PROVIDER" ;;
        esac
        echo -n "Enter your $LABEL API key: "
        read -s KEY
        echo
        echo "$KEY" > "$KEY_FILE"
        chmod 600 "$KEY_FILE"
        echo "Saved to $KEY_FILE"
    fi
fi

# ── Prompt setup ──────────────────────────────────────────────────────────────
if [[ -n "$PROMPT_NAME" ]]; then
    PROMPT_FILE="$HOME/.config/blind-spot/prompts/${PROMPT_NAME}.txt"
    if [[ ! -f "$PROMPT_FILE" ]]; then
        echo "Error: prompt file not found: $PROMPT_FILE"
        exit 1
    fi
    export BLIND_SPOT_PROMPT="$PROMPT_NAME"
fi

# ── Launch ────────────────────────────────────────────────────────────────────
INFO="provider: $PROVIDER${MODEL:+, model: $MODEL}${PROMPT_NAME:+, prompt: $PROMPT_NAME}"
echo "Starting BlindSpot — $INFO"
echo "Press Cmd+Shift+Space over selected text."

exec "$BINARY"
