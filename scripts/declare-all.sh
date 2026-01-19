#!/bin/bash

# Function to print usage and exit
print_usage_and_exit() {
    echo "Usage: $0 --network {sepolia,mainnet}"
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
if [ "$NETWORK" != "sepolia" -a "$NETWORK" != "mainnet" ]; then
    echo "Invalid network: $NETWORK"
    print_usage_and_exit
fi


scarb build

declare_class_hash() {
    # expects that there is an account set up named by the given network
    sncast --account $NETWORK --wait declare --network "$NETWORK" --contract-name $1
}

echo "Declaring Core"
declare_class_hash Core
echo "Declaring Positions"
declare_class_hash Positions
echo "Declaring NFT"
declare_class_hash OwnedNFT
echo "Declaring TWAMM"
declare_class_hash TWAMM
echo "Declaring LimitOrders"
declare_class_hash LimitOrders
echo "Declaring Oracle"
declare_class_hash Oracle

echo "Declaring Router"
declare_class_hash Router

# echo "Declaring TokenRegistry"
# declare_class_hash TokenRegistry

