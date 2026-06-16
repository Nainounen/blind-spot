# BlindSpot — TODO / Ideas

## Features

- **Smart image context**: When the user triggers the hotkey, detect where on screen the selected text is located (via AX API or cursor position), capture a screenshot of that region, and include it alongside the text in the AI request. This lets the model see the visual context (table, diagram, UI, etc.) instead of only the raw text. Requires multimodal providers (OpenAI, Anthropic, Gemini).
