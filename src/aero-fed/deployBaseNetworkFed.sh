if [ -f .env ]; then
  export $(echo $(cat .env | sed 's/#.*//g'| xargs) | envsubst)
fi

gov=0x926dF14a23BE491164dCF93f4c468A50ef659D5B;
chair=0x8F97cCA30Dbe80e7a8B462F1dD1a51C32accDfC8;
aeroFed=0x0000000000000000000000000000000000000000;
maxDolaToUsdcSlip=30;
maxUsdcToDolaSlip=30;

forge create --rpc-url $RPC_MAINNET \
    --constructor-args $gov $chair $aeroFed $maxDolaToUsdcSlip $maxUsdcToDolaSlip \
    --private-key $PRIVATE_KEY \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --verify \
    src/aero-fed/BaseNetworkFed.sol:BaseNetworkFed

