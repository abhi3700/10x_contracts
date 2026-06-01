#!/usr/bin/env bash

set -euo pipefail

if [ -f .env ]; then
	source .env
fi

: "${BSC_WS_RPC_URL:?BSC_WS_RPC_URL is missing in .env}"

PORT=8600
ANVIL_RPC_URL=http://localhost:$PORT

if lsof -i :$PORT >/dev/null 2>&1; then
	echo "Anvil already running on port $PORT"
else
	nohup anvil -p $PORT --fork-url "$BSC_WS_RPC_URL" > /tmp/10x-anvil.log 2>&1 &
	ANVIL_PID=$!
	echo "Started anvil with PID $ANVIL_PID"
	echo "Logs: /tmp/10x-anvil.log"
fi


for _ in {1..30}; do
	if cast chain-id --rpc-url $ANVIL_RPC_URL >/dev/null 2>&1; then
		break
	fi
	sleep 1
done

cast chain-id --rpc-url $ANVIL_RPC_URL >/dev/null

DEPLOYER_ADDRESS=0x028198237C166E723534e5B94782B1e11A3291c7
DEPLOYER_SK=0xf1b02874f7869f2bb3f33827d57de8af43ecdaecb0ee15cf8626be5f17fd82c0
FUNDER_SK=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

cast send "$DEPLOYER_ADDRESS" \
  --value 0.5ether \
  --rpc-url $ANVIL_RPC_URL \
  --private-key $FUNDER_SK


forge script script/Router.s.sol:RouterScript \
	--rpc-url $ANVIL_RPC_URL \
	--broadcast \
	--private-key $DEPLOYER_SK

echo "Anvil is still running on $ANVIL_RPC_URL"
echo "Stop it with: pkill -f 'anvil --fork-url'"
