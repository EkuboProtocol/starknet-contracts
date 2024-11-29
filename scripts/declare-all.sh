#!/bin/bash

# Function to print usage and exit
print_usage_and_exit() {
    echo "Usage: $0 --network {sepolia,goerli-1,mainnet}"
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
if [ "$NETWORK" != "sepolia" -a "$NETWORK" != "mainnet" -a "$NETWORK" != "goerli-1" ]; then
    echo "Invalid network: $NETWORK"
    print_usage_and_exit
fi


scarb build

declare_class_hash() {
    local class_name=$1
    starkli declare --watch --network "$NETWORK" --keystore-password "$STARKNET_KEYSTORE_PASSWORD" --casm-file  "target/dev/ekubo_${class_name}.compiled_contract_class.json" "target/dev/ekubo_${class_name}.contract_class.json"
}

echo "Declaring Core"
CORE_CLASS_HASH=$(declare_class_hash Core)
echo "Declaring Positions"
POSITIONS_CLASS_HASH=$(declare_class_hash Positions)
echo "Declaring NFT"
NFT_CLASS_HASH=$(declare_class_hash OwnedNFT)
echo "Declaring TWAMM"
TWAMM_CLASS_HASH=$(declare_class_hash TWAMM)
echo "Declaring LimitOrders"
LIMIT_ORDERS_CLASS_HASH=$(declare_class_hash LimitOrders)
echo "Declaring Oracle"
ORACLE_CLASS_HASH=$(declare_class_hash Oracle)

# echo "Declaring Router"
# ROUTER_CLASS_HASH=$(declare_class_hash Router)
# echo "Declaring TokenRegistry"
# TOKEN_REGISTRY_CLASS_HASH=$(declare_class_hash TokenRegistry)

echo "Declared Core @ $CORE_CLASS_HASH"
echo "Declared Positions @ $POSITIONS_CLASS_HASH"
echo "Declared NFT @ $NFT_CLASS_HASH"
echo "Declared TWAMM @ $TWAMM_CLASS_HASH"
echo "Declared LimitOrders @ $LIMIT_ORDERS_CLASS_HASH"
echo "Declared Oracle @ $ORACLE_CLASS_HASH"

# echo "Declared router @ $ROUTER_CLASS_HASH"
# echo "Declared token registry @ $TOKEN_REGISTRY_CLASS_HASH"

