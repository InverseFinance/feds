// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/velo-fed/VeloFarmerV3.sol";

contract VeloFarmerV3Deploy is Script {
    // UPDATE THIS
    address l2chair = address(0); // UPDATE
    address chair = address(0); // UPDATE
    address guardian = address(0); // UPDATE
    address optiFedAddress = address(0); // ADD ONCE DEPLOYED;

    // REVIEW THIS
    address gov = 0x926dF14a23BE491164dCF93f4c468A50ef659D5B; 
    address treasury = 0x926dF14a23BE491164dCF93f4c468A50ef659D5B;
    address cctpOpti = 0x2B4069517957735bE00ceE0fadAE88a26365528f; // OK
    address l2optiBridgeAddress = 0x4200000000000000000000000000000000000010; //OK

    // REVIEW THESE
    uint maxSlippageBpsDolaToUsdc = 100;
    uint maxSlippageBpsUsdcToDola = 100;
    uint maxSlippageBpsUsdcNativeToDola = 100;
    uint maxSlippageBpsDolaToUsdcNative = 100;
    uint maxSlippageBpsUsdcToUsdcNative = 100;
    uint maxSlippageBpsUsdcNativeToUsdc = 100;
    uint maxSlippageLiquidity = 1000;

    VeloFarmerV3 veloFarmer;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        uint[] memory maxSlippageBps = new uint[](6);
        maxSlippageBps[0] = maxSlippageBpsDolaToUsdc;
        maxSlippageBps[1] = maxSlippageBpsUsdcToDola;
        maxSlippageBps[2] = maxSlippageBpsUsdcNativeToDola;
        maxSlippageBps[3] = maxSlippageBpsDolaToUsdcNative;
        maxSlippageBps[4] = maxSlippageBpsUsdcToUsdcNative;
        maxSlippageBps[5] = maxSlippageBpsUsdcNativeToUsdc;

        vm.startBroadcast(deployerPrivateKey);
        veloFarmer = new VeloFarmerV3(
            gov,
            chair,
            l2chair,
            treasury,
            guardian,
            l2optiBridgeAddress,
            optiFedAddress,
            cctpOpti,
            maxSlippageBps,
            maxSlippageLiquidity
        );
        vm.stopBroadcast();
    }
}
