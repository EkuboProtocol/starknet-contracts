#!/bin/bash

# Function to print usage and exit
print_usage_and_exit() {
    echo "Usage: $0 --network {goerli-1,mainnet}"
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
if [ "$NETWORK" != "goerli-1" -a "$NETWORK" != "mainnet" ]; then
    echo "Invalid network: $NETWORK"
    print_usage_and_exit
fi


scarb build

declare_class_hash() {
    local class_name=$1
    starkli declare --network "$NETWORK" --keystore-password "$STARKNET_KEYSTORE_PASSWORD" --compiler-version "2.1.0" "target/dev/ekubo_${class_name}.sierra.json"
}

echo "Declaring core"
CORE_CLASS_HASH=$(declare_class_hash Core)
echo "Declaring positions"
POSITIONS_CLASS_HASH=$(declare_class_hash Positions)
echo "Declaring Quoter"
QUOTER_CLASS_HASH=$(declare_class_hash Quoter)
echo "Declaring NFT"
NFT_CLASS_HASH=$(declare_class_hash EnumerableOwnedNFT)

echo "Declared core @ $CORE_CLASS_HASH"
echo "Declared positions @ $POSITIONS_CLASS_HASH"
echo "Declared quoter @ $QUOTER_CLASS_HASH"
echo "Declared nft @ $NFT_CLASS_HASH"

case $NETWORK in
    "goerli-1")
        METADATA_URL="0x68747470733a2f2f782e656b75626f2e6f72672f" # "https://x.ekubo.org/"
        ;;
    "mainnet")
        METADATA_URL="0x68747470733a2f2f7a2e656b75626f2e6f72672f" # "https://z.ekubo.org"
        ;;
    *)
        echo "Error: Unsupported network"
        exit 1
        ;;
esac

echo "Waiting 300 seconds for the classhashes to be indexed"
sleep 300;

CORE_ADDRESS=$(starkli deploy --watch --network "$NETWORK" --keystore-password "$STARKNET_KEYSTORE_PASSWORD" "$CORE_CLASS_HASH")

sleep 60;

POSITIONS_ADDRESS=$(starkli deploy --watch --network "$NETWORK" --keystore-password "$STARKNET_KEYSTORE_PASSWORD" "$POSITIONS_CLASS_HASH" "$CORE_ADDRESS" "$NFT_CLASS_HASH" "$METADATA_URL")

sleep 60;

QUOTER_ADDRESS=$(starkli deploy --watch --network "$NETWORK" --keystore-password "$STARKNET_KEYSTORE_PASSWORD" "$QUOTER_CLASS_HASH" "$CORE_ADDRESS")

echo "Core deployed @ $CORE_ADDRESS"
echo "Positions deployed @ $POSITIONS_ADDRESS"
echo "Quoter deployed @ $QUOTER_ADDRESS"