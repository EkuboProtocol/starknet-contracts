#!/bin/bash

# Install Scarb 2.12.2
curl --proto '=https' --tlsv1.2 -sSf https://docs.swmansion.com/scarb/install.sh | sh -s -- -v 2.12.2

# Add Scarb to PATH for this session
export PATH="$HOME/.local/bin:$PATH"

# Persist Scarb on PATH for future shells
if ! grep -q 'export PATH="$HOME/.local/bin:$PATH"' ~/.bashrc; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
fi
