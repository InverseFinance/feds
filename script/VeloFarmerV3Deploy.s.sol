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
    address gov = address(0); // VeloFarmerMessengerV3
    address l1Treasury = 0x926dF14a23BE491164dCF93f4c468A50ef659D5B;
    address treasury = address(0); // ADD L2 TREASURY
    // REVIEW THIS
    
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

        address[] memory addresses = new address[](9);
        addresses[0] = gov;
        addresses[1] = chair;
        addresses[2] = l2chair;
        addresses[3] = treasury;
        addresses[4] = l1Treasury;
        addresses[5] = guardian;
        addresses[6] = l2optiBridgeAddress;
        addresses[7] = optiFedAddress;
        addresses[8] = cctpOpti;

        uint[] memory maxSlippageBps = new uint[](6);
        maxSlippageBps[0] = maxSlippageBpsDolaToUsdc;
        maxSlippageBps[1] = maxSlippageBpsUsdcToDola;
        maxSlippageBps[2] = maxSlippageBpsUsdcNativeToDola;
        maxSlippageBps[3] = maxSlippageBpsDolaToUsdcNative;
        maxSlippageBps[4] = maxSlippageBpsUsdcToUsdcNative;
        maxSlippageBps[5] = maxSlippageBpsUsdcNativeToUsdc;

        vm.startBroadcast(deployerPrivateKey);
        veloFarmer = new VeloFarmerV3(
            addresses,
            maxSlippageBps,
            maxSlippageLiquidity
        );
        vm.stopBroadcast();
    }
}
