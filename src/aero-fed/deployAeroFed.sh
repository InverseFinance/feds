if [ -f .env ]; then
  export $(echo $(cat .env | sed 's/#.*//g'| xargs) | envsubst)
fi

gov=0x257D2836c8f5797581740543F853403b81C44b5A;
chair=0x257D2836c8f5797581740543F853403b81C44b5A;
l2chair=;
treasury=0xa283139017a2f5BAdE8d8e25412C600055D318F8;
guardian=0x257D2836c8f5797581740543F853403b81C44b5A
baseNetworkFed=;
maxDolaToUsdcSlip=30;
maxUsdcToDolaSlip=30;
maxLiquiditySlip=55;
forge create --rpc-url $RPC_BASE \
    --constructor-args $gov $chair $l2chair $treasury $guardian $baseNetworkFed $maxDolaToUsdcSlip $maxUsdcToDolaSlip $maxLiquiditySlip \
    --private-key $PRIVATE_KEY \
    --etherscan-api-key $BASESCAN_API_KEY \
    --verify \
    src/aero-fed/AeroFed.sol:AeroFed

