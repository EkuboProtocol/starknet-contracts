#!/bin/bash

# Install Scarb 2.11.4
curl --proto '=https' --tlsv1.2 -sSf https://docs.swmansion.com/scarb/install.sh | sh -s -- -v 2.11.4

# Add Scarb to PATH for this session
export PATH="$HOME/.local/bin:$PATH"

# Build the Cairo contracts
scarb build

# Install dependencies for integration tests
apt-get update
apt-get install -y libgmp3-dev

# Install starknet-devnet
pip3 install starknet-devnet

# Install npm dependencies for integration tests
cd integration-test
npm ci
