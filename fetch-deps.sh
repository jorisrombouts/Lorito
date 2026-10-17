#!/bin/sh
# Downloads the whisper model, the VAD model, the Core ML encoder and the prebuilt whisper.cpp framework. All gitignored. Safe to re-run.
set -eu
cd "$(dirname "$0")"
WHISPER=v1.9.2
MODEL=Resources/ggml-large-v3-turbo.bin
VAD=Resources/ggml-silero-v6.2.0.bin

if [ ! -f "$MODEL" ]; then
  echo "downloading model (1.6 GB)"
  curl -L --progress-bar -o "$MODEL" https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin
fi
# A few-KB "model" is an HTML block page from a filtering proxy, not a model.
if [ "$(stat -f %z "$MODEL")" -lt 1000000000 ]; then
  rm -f "$MODEL"; echo "model download failed: huggingface.co unreachable or blocked"; exit 1
fi

# Silero VAD: whisper only decodes what this hears speech in, so silence cannot hallucinate.
if [ ! -f "$VAD" ]; then
  echo "downloading Silero VAD model (865 KB)"
  curl -L --progress-bar -o "$VAD" "https://huggingface.co/ggml-org/whisper-vad/resolve/main/$(basename "$VAD")"
fi
if [ "$(stat -f %z "$VAD")" -lt 500000 ]; then
  rm -f "$VAD"; echo "VAD download failed: huggingface.co unreachable or blocked"; exit 1
fi

# Core ML encoder: whisper runs the encoder on the Neural Engine when this sits next to the ggml model.
COREML=Resources/ggml-large-v3-turbo-encoder.mlmodelc
if [ ! -d "$COREML" ]; then
  echo "downloading Core ML encoder (1.2 GB)"
  TMP=$(mktemp -d)
  curl -L --progress-bar -o "$TMP/enc.zip" "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$(basename "$COREML").zip"
  if [ "$(stat -f %z "$TMP/enc.zip")" -lt 1000000000 ]; then
    rm -rf "$TMP"; echo "Core ML encoder download failed: huggingface.co unreachable or blocked"; exit 1
  fi
  unzip -q "$TMP/enc.zip" -d "$TMP"
  mv "$TMP/$(basename "$COREML")" "$COREML"
  rm -rf "$TMP"
fi

if [ ! -d Frameworks/whisper.xcframework ]; then
  echo "downloading whisper.cpp $WHISPER framework"
  TMP=$(mktemp -d)
  curl -L --progress-bar -o "$TMP/xc.zip" "https://github.com/ggml-org/whisper.cpp/releases/download/$WHISPER/whisper-$WHISPER-xcframework.zip"
  unzip -q "$TMP/xc.zip" -d "$TMP"
  mkdir -p Frameworks && mv "$TMP/build-apple/whisper.xcframework" Frameworks/
  rm -rf "$TMP"
fi
echo "deps ready"
