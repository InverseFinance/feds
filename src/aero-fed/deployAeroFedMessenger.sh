if [ -f .env ]; then
  export $(echo $(cat .env | sed 's/#.*//g'| xargs) | envsubst)
fi

gov=0x926dF14a23BE491164dCF93f4c468A50ef659D5B;
chair=0x8F97cCA30Dbe80e7a8B462F1dD1a51C32accDfC8;
guardian=0xE3eD95e130ad9E15643f5A5f232a3daE980784cd;
aeroFed=0x0000000000000000000000000000000000000000;
forge create --rpc-url $RPC_MAINNET \
    --constructor-args $gov $chair $guardian $aeroFed \
    --private-key $PRIVATE_KEY \
    --etherscan-api-key $BASESCAN_API_KEY \
    --verify \
    src/aero-fed/AeroFedMessenger.sol:AeroFedMessenger

