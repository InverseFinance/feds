// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {AeroFarmer} from "src/velo-fed/AeroFarmer.sol";
import {AeroFarmerMessenger} from "src/velo-fed/AeroFarmerMessenger.sol";
import {SuperChainCCTPFed} from "src/velo-fed/SuperChainCCTPFed.sol";

contract AeroFarmerDeploy is Script {
    // UPDATE THIS
    address l2Chair = 0x7FD13dD8d653F32Bd5E2B6bAbb4978507960A0dA;
    address l1Chair = 0x8F97cCA30Dbe80e7a8B462F1dD1a51C32accDfC8;
    address governance = 0x926dF14a23BE491164dCF93f4c468A50ef659D5B;
    address l1Guardian = 0xE3eD95e130ad9E15643f5A5f232a3daE980784cd;
    address l2Treasury = 0x586CF50c2874f3e3997660c0FD0996B090FB9764;

    //Change to correspond with deployer private key
    address deployerAddress = 0x11EC78492D53c9276dD7a184B1dbfB34E50B710D;

    address cctpBase = 0x1682Ae6375C4E4A97e4B583BC394c861A46D8962;
    address l2baseBridgeAddress = 0x4200000000000000000000000000000000000010;

    address exchangeProxy = 0x111111125421cA6dc452d289314280a0f8842A65; // 1inch v6 Exchange Proxy
    uint maxSlippageBpsDolaToUsdc = 60;
    uint maxSlippageBpsUsdcToDola = 60;
    uint maxSlippageBpsUsdcNativeToDola = 60;
    uint maxSlippageBpsDolaToUsdcNative = 60;
    uint maxSlippageBpsUsdcToUsdcNative = 20;
    uint maxSlippageBpsUsdcNativeToUsdc = 20;
    uint maxSlippageLiquidity = 55;

    address public constant baseBridge =
        address(0x3154Cf16ccdb4C6d922629664174b904d80F2C35);
    address public constant DOLA_BASE =
        0x4621b7A9c75199271F773Ebd9A499dbd165c3191;
    address public constant USDC_BASE =
        0xd9aAEc86B65D86f6A7B5B1b0c42FFA531710b6CA;
    uint32 public constant BASE_CCTP_DOMAIN = 6;

    function run() external {
        string memory mainnetRPC = vm.envString("RPC_MAINNET");
        string memory baseRPC = vm.envString("RPC_BASE");
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        uint mainnetFork = vm.createSelectFork(mainnetRPC);
        //Deploy messenger without associated aeroFarmer and msg.sender as gov
        AeroFarmerMessenger messenger = AeroFarmerMessenger(
            0x09aF9E0D4932604913F7Cd77aD5e157F0BC700eA
        ); //deployAeroMessenger(deployerAddress, address(0));

        //Deploy BaseFedCCTP without associated aeroFarmer and msg.sender as gov
        SuperChainCCTPFed baseFed = deployBaseFed(deployerAddress, address(0));

        //Deploy AeroFarmer on network of choice
        AeroFarmer aeroFarmer = deployAeroFarmer(
            baseRPC,
            address(messenger),
            address(baseFed)
        );

        //Change network back to mainnet
        vm.selectFork(mainnetFork);

        //Set aeroFarmer in messenger and change gov to governance contract
        vm.startBroadcast(deployerPrivateKey);
        messenger.setAeroFed(address(aeroFarmer));
        messenger.setPendingMessengerGov(governance);

        //Set aeroFarmer in baseFed and change gov to governance contract
        baseFed.changeFarmer(address(aeroFarmer));
        baseFed.setPendingGov(governance);
        vm.stopBroadcast();
    }

    function deployBaseFed(
        address gov,
        address aeroFarmer
    ) public returns (SuperChainCCTPFed) {
        uint _maxSlippageBpsDolaToUsdc = 25;
        uint _maxSlippageBpsUsdcToDola = 10;

        SuperChainCCTPFed baseFed;

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        baseFed = new SuperChainCCTPFed(
            gov,
            l1Chair,
            aeroFarmer,
            exchangeProxy,
            _maxSlippageBpsDolaToUsdc,
            _maxSlippageBpsUsdcToDola,
            baseBridge,
            DOLA_BASE,
            USDC_BASE,
            BASE_CCTP_DOMAIN
        );

        vm.stopBroadcast();

        return baseFed;
    }

    function deployAeroMessenger(
        address gov,
        address aeroFarmer
    ) public returns (AeroFarmerMessenger) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        AeroFarmerMessenger messenger;

        messenger = new AeroFarmerMessenger(
            gov,
            l1Chair,
            l1Guardian,
            aeroFarmer
        );

        vm.stopBroadcast();

        return messenger;
    }

    function deployAeroFarmer(
        string memory network,
        address messenger,
        address baseFed
    ) public returns (AeroFarmer) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.createSelectFork(network);

        address[] memory addresses = new address[](9);
        addresses[0] = messenger;
        addresses[1] = messenger;
        addresses[2] = l2Chair;
        addresses[3] = l2Treasury;
        addresses[4] = governance;
        addresses[5] = messenger;
        addresses[6] = l2baseBridgeAddress;
        addresses[7] = baseFed;
        addresses[8] = cctpBase;

        uint[] memory maxSlippageBps = new uint[](6);
        maxSlippageBps[0] = maxSlippageBpsDolaToUsdc;
        maxSlippageBps[1] = maxSlippageBpsUsdcToDola;
        maxSlippageBps[2] = maxSlippageBpsUsdcNativeToDola;
        maxSlippageBps[3] = maxSlippageBpsDolaToUsdcNative;
        maxSlippageBps[4] = maxSlippageBpsUsdcToUsdcNative;
        maxSlippageBps[5] = maxSlippageBpsUsdcNativeToUsdc;

        AeroFarmer aeroFarmer;
        vm.startBroadcast(deployerPrivateKey);
        aeroFarmer = new AeroFarmer(
            addresses,
            maxSlippageBps,
            maxSlippageLiquidity
        );
        vm.stopBroadcast();

        return aeroFarmer;
    }
}
