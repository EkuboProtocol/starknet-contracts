#!/bin/bash

# Install Scarb 2.11.4
curl --proto '=https' --tlsv1.2 -sSf https://docs.swmansion.com/scarb/install.sh | sh -s -- -v 2.11.4

# Add Scarb to PATH for this session
export PATH="$HOME/.local/bin:$PATH"

# Persist Scarb on PATH for future shells
if ! grep -q 'export PATH="$HOME/.local/bin:$PATH"' ~/.bashrc; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
fi

# Build the Cairo contracts
scarb build

# Install dependencies for integration tests
if command -v sudo >/dev/null 2>&1; then
    sudo apt-get update
    sudo apt-get install -y libgmp3-dev
else
    apt-get update
    apt-get install -y libgmp3-dev
fi

# Install starknet-devnet
python3 -m pip install starknet-devnet

# Install npm dependencies for integration tests
(cd integration-test && npm ci)
