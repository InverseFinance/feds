dola=0x865377367054516e17014CcdED1e7d814EDC9ce4;
aura=0xC0c293ce456fF0ED870ADd98a0828Dd4d2903DBF;
vault=0xBA12222222228d8Ba445958a75a0704d566BF2C8;
baseRewardPool=0xa0E1D9619979f06Ff375251AfE90de2801B009d8;
booster=0xA57b8d98dAE62B26Ec3bcC4a365338157060B234;
chair=0x8F97cCA30Dbe80e7a8B462F1dD1a51C32accDfC8;
guardian=0xE3eD95e130ad9E15643f5A5f232a3daE980784cd;
gov=0x926dF14a23BE491164dCF93f4c468A50ef659D5B;
maxLossExpansion=10;
maxLossWithdraw=10;
maxLossTakeProfit=10;
poolId=0x5b3240b6be3e7487d61cd1afdfc7fe4fa1d81e6400000000000000000000037b;
forge create --rpc-url $1 \
    --constructor-args $dola $aura $vault $baseRewardPool $booster $chair $guardian $gov $maxLossExpansion $maxLossWithdraw $maxLossTakeProfit $poolId\
    --private-key $3 src/aura-fed/AuraFed.sol:AuraFed \
    --etherscan-api-key $2 \
    --verify
