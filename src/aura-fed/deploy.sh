vault=0xBA12222222228d8Ba445958a75a0704d566BF2C8;
baseRewardPool=0xFdbd847B7593Ef0034C58258aD5a18b34BA6cB29;
booster=0xA57b8d98dAE62B26Ec3bcC4a365338157060B234;
chair=0x8F97cCA30Dbe80e7a8B462F1dD1a51C32accDfC8;
guardian=0xE3eD95e130ad9E15643f5A5f232a3daE980784cd;
gov=0x926dF14a23BE491164dCF93f4c468A50ef659D5B;
maxLossExpansion=13;
maxLossWithdraw=10;
maxLossTakeProfit=10;
pid=53;
poolId=0x133d241f225750d2c92948e464a5a80111920331000000000000000000000476;
forge create --rpc-url $1 \
    --constructor-args $vault $baseRewardPool $booster $chair $guardian $gov $maxLossExpansion $maxLossWithdraw $maxLossTakeProfit $pid $poolId\
    --private-key $3 src/aura-fed/AuraComposableStablepoolFed.sol:AuraComposableStablepoolFed \
    --etherscan-api-key $2 \
    --verify
