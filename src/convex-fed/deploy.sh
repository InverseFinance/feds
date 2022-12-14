dola=0x865377367054516e17014CcdED1e7d814EDC9ce4;
cvx=0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
crvPool=0xE57180685E3348589E9521aa53Af0BCD497E884d;
booster=0xF403C135812408BFbE8713b5A23a04b3D48AAE31;
baseRewardPool=0x0404d05F3992347d2f0dC3a97bdd147D77C85c1c;
chair=0x8F97cCA30Dbe80e7a8B462F1dD1a51C32accDfC8;
gov=0x926dF14a23BE491164dCF93f4c468A50ef659D5B;
maxLossExpansion=10;
maxLossWithdraw=1;
maxLossTakeProfit=1;
forge create --rpc-url $1 \
    --constructor-args $dola $cvx $crvPool $booster $baseRewardPool $chair $gov $maxLossExpansion $maxLossWithdraw $maxLossTakeProfit\
    --private-key $3 src/convex-fed/ConvexFed.sol:ConvexFed \
    --etherscan-api-key $2 \
    --verify

