#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------
# 1. Ensure we’re running from the repo root
# ---------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ---------------------------------------------------
# 2. Install Homebrew (if missing) and packages
# ---------------------------------------------------
if ! command -v brew &>/dev/null; then
  echo "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

brew update
brew install git cmake llvm openblas wget coreutils

# ---------------------------------------------------
# 3. Set up pyenv so pip actually points at 3.11.10
# ---------------------------------------------------
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"

if command -v pyenv &>/dev/null; then
  eval "$(pyenv init --path)"
  eval "$(pyenv init -)"
else
  echo "pyenv not found; installing..."
  brew install pyenv
  eval "$(pyenv init --path)"
  eval "$(pyenv init -)"
fi

# ---------------------------------------------------
# 4. Install & activate Python 3.11.10
# ---------------------------------------------------
pyenv install -s 3.11.10
pyenv global 3.11.10
pyenv rehash

# ---------------------------------------------------
# 5. Swapfile: skip manual on Sonoma (read-only /)
# ---------------------------------------------------
if [[ ! -w / ]]; then
  echo "⚠️  Root is read-only on macOS Sonoma; skipping manual swapfile. macOS manages swap dynamically."
else
  echo "Creating 8 GB swapfile…"
  sudo dd if=/dev/zero of=/swapfile bs=1m count=8192
  sudo chmod 600 /swapfile
  echo "Note: macOS uses dynamic_pager for swap—no mkswap needed."
fi

# ---------------------------------------------------
# 6. Install Python deps (core + dev)
# ---------------------------------------------------
pip install --upgrade pip

if [[ -f requirements.txt ]]; then
  echo "Installing core dependencies..."
  pip install -r requirements.txt
else
  echo "❌  requirements.txt not found in $PWD; please place it here."
  exit 1
fi

# Install test/dev deps if present, but don't let failures kill the script
if [[ -f requirements-dev.txt ]]; then
  echo "Installing dev/test dependencies..."
  pip install -r requirements-dev.txt || {
    echo "⚠️  Some dev dependencies failed to install—core stack should still be OK."
  }
else
  echo "No requirements-dev.txt found; skipping test/dev deps."
fi

# ---------------------------------------------------
# 7. Build llama.cpp with Metal (CMake)
# ---------------------------------------------------
if [[ -d llama.cpp ]]; then
  echo "Removing existing llama.cpp directory…"
  rm -rf llama.cpp
fi

git clone https://github.com/ggerganov/llama.cpp.git
cd llama.cpp
mkdir -p build && cd build

cmake -DLLAMA_METAL=ON -DCMAKE_BUILD_TYPE=Release ..
cmake --build . -- -j"$(sysctl -n hw.ncpu)"
cd ../..

# point llama-cpp-python at our custom build
LIB_PATH="$SCRIPT_DIR/llama.cpp/build/libllama.dylib"
echo "export LLAMA_CPP_LIBRARY_PATH=\"$LIB_PATH\"" >> ~/.zshrc
export LLAMA_CPP_LIBRARY_PATH="$LIB_PATH"

# ---------------------------------------------------
# 8. Install Python binding for llama.cpp
# ---------------------------------------------------
pip install llama-cpp-python==0.2.72

echo "✅  Setup complete!"