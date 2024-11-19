// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {VeloFarmerV3} from "src/velo-fed/VeloFarmerV3.sol";
import {VeloFarmerMessengerV3} from "src/velo-fed/VeloFarmerMessengerV3.sol";
import {OptiFedCCTP} from "src/velo-fed/OptiFedCCTP.sol";

contract VeloFarmerV3Deploy is Script {
    // UPDATE THIS
    address l2Chair = 0x9f9Fa2C6b432689Dcd4E3ad55f86FdE6c03694EE;
    address l1Chair = 0x8F97cCA30Dbe80e7a8B462F1dD1a51C32accDfC8;
    address l2Guardian = 0x257D2836c8f5797581740543F853403b81C44b5A;
    address l1Guardian = 0xE3eD95e130ad9E15643f5A5f232a3daE980784cd;
    address governance = 0x926dF14a23BE491164dCF93f4c468A50ef659D5B;
    address l2Treasury = 0xa283139017a2f5BAdE8d8e25412C600055D318F8;

    //Change to correspond with private key
    address deployerAddress = 0x11EC78492D53c9276dD7a184B1dbfB34E50B710D;

    address cctpOpti = 0x2B4069517957735bE00ceE0fadAE88a26365528f; // OK
    address l2optiBridgeAddress = 0x4200000000000000000000000000000000000010; //OK

    address exchangeProxy = 0x111111125421cA6dc452d289314280a0f8842A65; // 1inch v6 Exchange Proxy

    uint maxSlippageBpsDolaToUsdc = 60;
    uint maxSlippageBpsUsdcToDola = 60;
    uint maxSlippageBpsUsdcNativeToDola = 60;
    uint maxSlippageBpsDolaToUsdcNative = 60;
    uint maxSlippageBpsUsdcToUsdcNative = 20;
    uint maxSlippageBpsUsdcNativeToUsdc = 20;
    uint maxSlippageLiquidity = 55;

    function run() external {
        string memory mainnetRPC = vm.envString("RPC_MAINNET");
        string memory baseRPC = vm.envString("RPC_OPTI");
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        uint mainnetFork = vm.createSelectFork(mainnetRPC);
        //Deploy messenger without associated veloFarmer and msg.sender as gov
        VeloFarmerMessengerV3 messenger = deployVeloMessengerV3(
            deployerAddress,
            address(0)
        );

        //Deploy OptiFedCCTP without associated veloFarmer and msg.sender as gov
        OptiFedCCTP optiFed = deployOptiFed(deployerAddress, address(0));

        //Deploy VeloFarmer on network of choice
        VeloFarmerV3 veloFarmer = deployVeloFarmer(
            baseRPC,
            address(messenger),
            address(optiFed)
        );

        //Change network back to mainnet
        vm.selectFork(mainnetFork);

        //Set veloFarmer in messenger and change gov to governance contract
        vm.startBroadcast(deployerPrivateKey);
        messenger.setVeloFed(address(veloFarmer));
        messenger.setPendingMessengerGov(governance);

        //Set veloFarmer in optiFed and change gov to governance contract
        optiFed.changeVeloFarmer(address(veloFarmer));
        optiFed.setPendingGov(governance);
        vm.stopPrank();
    }

    function deployOptiFed(
        address gov,
        address veloFarmer
    ) public returns (OptiFedCCTP) {
        uint _maxSlippageBpsDolaToUsdc = 25;
        uint _maxSlippageBpsUsdcToDola = 10;

        OptiFedCCTP optiFed;

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        optiFed = new OptiFedCCTP(
            gov,
            l1Chair,
            veloFarmer,
            exchangeProxy,
            _maxSlippageBpsDolaToUsdc,
            _maxSlippageBpsUsdcToDola
        );

        vm.stopBroadcast();

        return optiFed;
    }

    function deployVeloMessengerV3(
        address gov,
        address veloFarmer
    ) public returns (VeloFarmerMessengerV3) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        VeloFarmerMessengerV3 messenger;

        messenger = new VeloFarmerMessengerV3(
            gov,
            l1Chair,
            l1Guardian,
            veloFarmer
        );

        vm.stopBroadcast();

        return messenger;
    }

    function deployVeloFarmer(
        string memory network,
        address messenger,
        address optiFed
    ) public returns (VeloFarmerV3) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.createSelectFork(network);

        address[] memory addresses = new address[](9);
        addresses[0] = messenger;
        addresses[1] = l1Chair;
        addresses[2] = l2Chair;
        addresses[3] = l2Treasury;
        addresses[4] = governance;
        addresses[5] = l2Guardian;
        addresses[6] = l2optiBridgeAddress;
        addresses[7] = optiFed;
        addresses[8] = cctpOpti;

        uint[] memory maxSlippageBps = new uint[](6);
        maxSlippageBps[0] = maxSlippageBpsDolaToUsdc;
        maxSlippageBps[1] = maxSlippageBpsUsdcToDola;
        maxSlippageBps[2] = maxSlippageBpsUsdcNativeToDola;
        maxSlippageBps[3] = maxSlippageBpsDolaToUsdcNative;
        maxSlippageBps[4] = maxSlippageBpsUsdcToUsdcNative;
        maxSlippageBps[5] = maxSlippageBpsUsdcNativeToUsdc;

        VeloFarmerV3 veloFarmer;
        vm.startBroadcast(deployerPrivateKey);
        veloFarmer = new VeloFarmerV3(
            addresses,
            maxSlippageBps,
            maxSlippageLiquidity
        );
        vm.stopBroadcast();

        return veloFarmer;
    }
}
