#!/bin/bash

# Function to print usage and exit
print_usage_and_exit() {
    echo "Usage: $0 --network {goerli-1,goerli-2,mainnet}"
    exit 1
}

# Ensure there are exactly two arguments
if [ "$#" -ne 2 ]; then
    print_usage_and_exit
fi

# Parse the arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --network)
            NETWORK="$2"
            shift
            ;;
        *)
            echo "Unknown parameter passed: $1"
            print_usage_and_exit
            ;;
    esac
    shift
done

# Ensure network is valid
if [ "$NETWORK" != "goerli-1" -a "$NETWORK" != "goerli-2" -a "$NETWORK" != "mainnet" ]; then
    echo "Invalid network: $NETWORK"
    print_usage_and_exit
fi

declare_class_hash() {
    local class_name=$1
    starkli declare --network "$NETWORK" --compiler-version "2.0.1" "target/dev/ekubo_${class_name}.sierra.json"
}

CORE_CLASS_HASH=$(declare_class_hash Core)
POSITIONS_CLASS_HASH=$(declare_class_hash Positions)
QUOTER_CLASS_HASH=$(declare_class_hash Quoter)
ONCE_UPGRADEABLE=$(declare_class_hash OnceUpgradeable)

