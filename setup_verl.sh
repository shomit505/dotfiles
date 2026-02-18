#!/bin/bash
# Setup script for verl (RL library) on RunPod GPU instances
# Usage: ./setup_verl.sh
#
# What this does:
#   1. Checks CUDA version (verl requires >= 12.8)
#   2. Installs Miniconda if not already present
#   3. Creates a conda environment 'verl' with Python 3.12
#   4. Clones the verl repo to ~/verl
#   5. Runs verl's dependency installer (vLLM, SGLang, FlashAttention, etc.)
#   6. Installs verl itself
#
# Note: Step 5 installs large packages and can take 20-40 minutes.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
VERL_DIR="$HOME/verl"
CONDA_ENV="verl"
PYTHON_VERSION="3.12"

echo "========================================="
echo "  verl Setup for RunPod"
echo "========================================="
echo ""

# --- Check CUDA ---
echo "--- Checking CUDA ---"
if command -v nvcc &> /dev/null; then
    CUDA_VERSION=$(nvcc --version | grep "release" | sed 's/.*release \([0-9.]*\).*/\1/')
    echo "CUDA version: $CUDA_VERSION"

    CUDA_MAJOR=$(echo "$CUDA_VERSION" | cut -d'.' -f1)
    CUDA_MINOR=$(echo "$CUDA_VERSION" | cut -d'.' -f2)

    if [ "$CUDA_MAJOR" -lt 12 ] || { [ "$CUDA_MAJOR" -eq 12 ] && [ "$CUDA_MINOR" -lt 8 ]; }; then
        echo ""
        echo "Warning: verl requires CUDA >= 12.8. Detected: $CUDA_VERSION"
        echo "On RunPod, select a template with CUDA 12.8+ (e.g. 'RunPod PyTorch 2.x' images)."
        read -p "Continue anyway? (y/n): " continue_anyway
        if [[ ! "$continue_anyway" =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        echo "CUDA version OK."
    fi
elif command -v nvidia-smi &> /dev/null; then
    echo "nvcc not found, but nvidia-smi is available."
    nvidia-smi --query-gpu=name --format=csv,noheader | head -1
    echo "Warning: Could not verify CUDA version. verl requires CUDA >= 12.8."
    read -p "Continue? (y/n): " continue_anyway
    if [[ ! "$continue_anyway" =~ ^[Yy]$ ]]; then
        exit 1
    fi
else
    echo "Warning: No GPU tools found. Make sure you are on a GPU instance."
    read -p "Continue anyway? (y/n): " continue_anyway
    if [[ ! "$continue_anyway" =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# --- Install Conda if missing ---
echo ""
echo "--- Checking for Conda ---"
if command -v conda &> /dev/null; then
    echo "Conda already installed: $(conda --version)"
elif [ -f "$HOME/miniconda3/bin/conda" ]; then
    echo "Miniconda found at ~/miniconda3. Adding to PATH..."
    export PATH="$HOME/miniconda3/bin:$PATH"
else
    echo "Conda not found. Installing Miniconda..."
    MINICONDA_INSTALLER="/tmp/miniconda_install.sh"
    curl -fsSL https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -o "$MINICONDA_INSTALLER"
    bash "$MINICONDA_INSTALLER" -b -p "$HOME/miniconda3"
    rm "$MINICONDA_INSTALLER"
    export PATH="$HOME/miniconda3/bin:$PATH"

    # Initialize conda for zsh and bash so future shells have it
    "$HOME/miniconda3/bin/conda" init bash
    "$HOME/miniconda3/bin/conda" init zsh 2>/dev/null || true
    echo "Miniconda installed."
fi

# Make conda available in this shell session
eval "$(conda shell.bash hook)"

# --- Create conda environment ---
echo ""
echo "--- Setting up conda environment '$CONDA_ENV' ---"
if conda env list | grep -q "^$CONDA_ENV "; then
    echo "Environment '$CONDA_ENV' already exists. Skipping creation."
else
    echo "Creating conda environment with Python $PYTHON_VERSION..."
    conda create -n "$CONDA_ENV" python="$PYTHON_VERSION" -y
    echo "Environment '$CONDA_ENV' created."
fi

conda activate "$CONDA_ENV"
echo "Activated: $CONDA_ENV (Python $(python --version))"

# --- Clone verl ---
echo ""
echo "--- Setting up verl repo ---"
if [ -d "$VERL_DIR/.git" ]; then
    echo "verl already cloned at $VERL_DIR. Pulling latest..."
    git -C "$VERL_DIR" pull
else
    echo "Cloning verl to $VERL_DIR..."
    git clone https://github.com/volcengine/verl.git "$VERL_DIR"
fi

# --- Run verl's dependency installer ---
echo ""
echo "--- Installing verl dependencies ---"
echo "This installs: vLLM, SGLang, FlashAttention, Megatron-LM, and other ML packages."
echo "This step can take 20-40 minutes on a fresh instance."
echo ""
cd "$VERL_DIR"
bash scripts/install_vllm_sglang_mcore.sh

# --- Install verl itself ---
echo ""
echo "--- Installing verl ---"
pip install --no-deps -e .

echo ""
echo "========================================="
echo "  verl Setup Complete!"
echo "========================================="
echo ""
echo "To use verl, activate the environment:"
echo "  conda activate $CONDA_ENV"
echo ""
echo "verl repo is at: $VERL_DIR"
echo ""
