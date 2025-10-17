#!/bin/bash

# Ensure Scarb is on PATH
export PATH="$HOME/.local/bin:$PATH"

# Format Cairo code with Scarb
scarb fmt
