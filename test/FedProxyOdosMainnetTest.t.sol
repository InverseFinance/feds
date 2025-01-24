// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "src/interfaces/IERC20.sol";
import {IDola} from "src/interfaces/velo/IDola.sol";
import {MockExchangeProxy} from "test/mocks/MockExchangeProxy.sol";
import {Test} from "forge-std/Test.sol";
import {SuperChainCCTPFed} from "src/velo-fed/SuperChainCCTPFed.sol";
import {console} from "forge-std/console.sol";
contract FedProxyOdosMainnetTest is Test {
    //Tokens
    IDola public DOLA = IDola(0x865377367054516e17014CcdED1e7d814EDC9ce4);
    IERC20 public USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    address l1BridgeAddr;
    MockExchangeProxy exchangeProxy;

    //EOAs
    address user = address(0x69);
    address chair = address(0xB);
    address gov = 0x926dF14a23BE491164dCF93f4c468A50ef659D5B;

    //Numbas
    uint dolaAmount = 2_000_000e18;
    uint usdcAmount = 2_000_000e6;

    //Feds
    SuperChainCCTPFed fed;

    // Optimism config
    address public constant optiBridge =
        address(0x99C9fc46f92E8a1c0deC1b1747d010903E884bE1);
    address public constant DOLA_OPTI =
        0x8aE125E8653821E851F12A49F7765db9a9ce7384;
    address public constant USDC_OPTI =
        0x7F5c764cBc14f9669B88837ca1490cCa17c31607;
    uint32 public constant OPTIMISM_CCTP_DOMAIN = 2;

    address public constant ODOS =
        address(0xCf5540fFFCdC3d510B18bFcA6d2b9987b0772559);
    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"), 21695085);

        initialize(optiBridge, DOLA_OPTI, USDC_OPTI, OPTIMISM_CCTP_DOMAIN);
    }

    bytes swapData =
        hex"83bd37f90001865377367054516e17014ccded1e7d814edc9ce40001a0b86991c6218b36c1d19d4a2e9eb0ce3606eb480ad3c21bcecceda100000005e5f772a7260147ae0001B28Ca7e465C452cE4252598e0Bc96Aeba553CF82000000015615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f000000000c03040e014e32ea230a01000101020001011ebf1e354a020003020001000a030001040200010246000005060700044a010909070100060d01090a0b01004a03010c0701000257030100080d007fffffafff000000000000000000000000000000ff17dab22f1e61078aba2623c89ce6110e878b3c865377367054516e17014ccded1e7d814edc9ce48272e1a3dbef607c04aa6e5bd3a1a134c8ac063b744793b5110f6ca9cc7cdfe1ce16677c3eb192ef0655977feb2f289a4ab78af67bab0d17aab843670655977feb2f289a4ab78af67bab0d17aab84367f939e0a03fb07f59a73314e73794be0e57ac1b4e31373595f40ea48a7aab6cbcb0d377c6066e2dca390f3595bca2df7d23783dfd126427cceb997bf4867b321132b18b5bf3775c0d9040d1872979422e9d39a5de30e57443bff2a8307a4256c8797a34974dece678ceceb27446b35c672dc7d61f30bad69edac17f958d2ee523a2206206994597c13d831ec700000000000000000000000000000000000000000000000000000000";
    function initialize(
        address bridge,
        address dola_chain,
        address usdc_chain,
        uint32 domain
    ) public {
        l1BridgeAddr = bridge;

        fed = new SuperChainCCTPFed(
            gov,
            chair,
            address(0x69),
            ODOS,
            160,
            10,
            bridge,
            dola_chain,
            usdc_chain,
            domain
        );

        vm.startPrank(gov);
        DOLA.addMinter(address(fed));
        vm.stopPrank();
    }

    function testL1_ExpansionAndSwap_Half_CCTP() public {
        vm.startPrank(chair);

        uint prevDolaBal = DOLA.balanceOf(l1BridgeAddr);
        // Swap 1M DOLA to USDC
        fed.expansionAndSwap(dolaAmount, dolaAmount / 2, true, swapData);

        assertEq(
            prevDolaBal + dolaAmount / 2,
            DOLA.balanceOf(l1BridgeAddr),
            "Bridge didn't receive correct amount of DOLA"
        );
        assertEq(USDC.balanceOf(address(fed)), 0, "CCTP Burn Failed");
    }

    function testL1_ExpansionAndSwap_Half_NO_CCTP() public {
        vm.startPrank(chair);

        uint prevDolaBal = DOLA.balanceOf(l1BridgeAddr);
        uint prevUsdcBal = USDC.balanceOf(l1BridgeAddr);
        // Swap 1M DOLA to USDC
        fed.expansionAndSwap(dolaAmount, dolaAmount / 2, false, swapData);

        uint estimatedUsdcAmount = dolaAmount / 2 / 1e12;

        assertEq(
            prevDolaBal + dolaAmount / 2,
            DOLA.balanceOf(l1BridgeAddr),
            "Bridge didn't receive correct amount of DOLA"
        );

        assertGt(
            prevUsdcBal + (estimatedUsdcAmount * 1001) / 1000,
            USDC.balanceOf(l1BridgeAddr),
            "Bridge didn't receive correct amount of USDC"
        );
        assertLt(
            prevUsdcBal + estimatedUsdcAmount,
            (USDC.balanceOf(l1BridgeAddr) * 1001) / 1000,
            "Bridge didn't receive correct amount of USDC"
        );
    }

    function testL1_SwapDOLAtoUSDC() public {
        vm.startPrank(chair);

        uint prevDolaBal = DOLA.balanceOf(address(fed));
        uint prevUsdcBal = USDC.balanceOf(address(fed));

        gibDOLA(address(fed), dolaAmount);
        // Swap 2M DOLA to USDC
        bytes
            memory swapData = hex"83bd37f90001865377367054516e17014ccded1e7d814edc9ce40001a0b86991c6218b36c1d19d4a2e9eb0ce3606eb480b01a784379d99db420000000601cb1ed7585e2666660001B28Ca7e465C452cE4252598e0Bc96Aeba553CF82000000015615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f000000000c03040e015b3fb3a40a0100010102000101206f81d14a020003020001000a030001040200010246000005060700044a010909070100060d01090a0b01004a03010c0701000257030100080d007fffffafff000000000000000000000000000000ff17dab22f1e61078aba2623c89ce6110e878b3c865377367054516e17014ccded1e7d814edc9ce48272e1a3dbef607c04aa6e5bd3a1a134c8ac063b744793b5110f6ca9cc7cdfe1ce16677c3eb192ef0655977feb2f289a4ab78af67bab0d17aab843670655977feb2f289a4ab78af67bab0d17aab84367f939e0a03fb07f59a73314e73794be0e57ac1b4e31373595f40ea48a7aab6cbcb0d377c6066e2dca390f3595bca2df7d23783dfd126427cceb997bf4867b321132b18b5bf3775c0d9040d1872979422e9d39a5de30e57443bff2a8307a4256c8797a34974dece678ceceb27446b35c672dc7d61f30bad69edac17f958d2ee523a2206206994597c13d831ec700000000000000000000000000000000000000000000000000000000";
        fed.swapDOLAtoUSDC(dolaAmount, swapData);

        uint estimatedUsdcAmount = 1971907418206; // estimation from ODOS API

        assertEq(
            prevDolaBal,
            DOLA.balanceOf(address(fed)),
            "DOLA didn't leave fed"
        );
        assertGt(
            prevUsdcBal + (estimatedUsdcAmount * 101) / 100,
            USDC.balanceOf(address(fed)),
            "Fed didn't receive correct amount of USDC Gt"
        );
        assertLt(
            prevUsdcBal + estimatedUsdcAmount,
            (USDC.balanceOf(address(fed)) * 101) / 100,
            "Fed didn't receive correct amount of USDC Lt"
        );
    }

    function testL1_SwapUSDCtoDOLA() public {
        vm.startPrank(chair);

        uint prevDolaBal = DOLA.balanceOf(address(fed));
        uint prevUsdcBal = USDC.balanceOf(address(fed));

        // Swap 10M USDC to DOLA
        bytes
            memory swapData = hex"83bd37f90001a0b86991c6218b36c1d19d4a2e9eb0ce3606eb480001865377367054516e17014ccded1e7d814edc9ce40609184e72a0000b084bedfc14dc048000000000c49b0001B28Ca7e465C452cE4252598e0Bc96Aeba553CF82000000015615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f000000001b08071f0184bae1eb1901000102030101230aeb1f0702050205b819feef8f0fcdc268afe14162983a69f6bf179e000000000000000000000689016b6cd6970a03000106020100010a51e8620a040801080201000122bf04104b0509020102011dff75d0570500010a0201800000340152dffd810d05000b020101d14f1dd00d05000c0201018b34d7b41a050d02010057060f010f02008000000002460011110312010646011414150501080a030000071600010c0a0300000e170001040a061900040501000b545b14004a0300191a00010a0d01141b1a000c0a050100181c0100064a05011d1e0100000a05010010120100020a05010013050100ff00000000a188eec8f81263234da3622a406892f3d630f98ca0b86991c6218b36c1d19d4a2e9eb0ce3606eb48dc035d45d973e3ec169d2276ddab16f1e407384fd29f8980852c2c76fc3f6e96a7aa06e0bedcc1b19d39a5de30e57443bff2a8307a4256c8797a349702950460e2b9529d0e00284a5fa2d7bdf3fa4d72625e92624bc2d88619accc1788365a69767f6200383e6b4437b59fff47b619cba855ca29342a85591116898dda4015ed8ddefb84b6e8bc24528af2d831373595f40ea48a7aab6cbcb0d377c6066e2dca04c8577958ccc170eb3d2cca76f9d51bc6e42d8f3416cf6c708da44db2624d63ea0aaef7113527c6c9f93163c99695c6526b799ebca2207fdf7d61ad635ef0056a597d13863b73825cca29723657859514cf6d2fe3e1b326114b07d22a6f6bb59e346c678b83c4aa949254895507d09365229bc3a8c7f710a3931d71877c0e7a3148cb7eb4463524fec27fbda3931d71877c0e7a3148cb7eb4463524fec27fbd744793b5110f6ca9cc7cdfe1ce16677c3eb192ef9d39a5de30e57443bff2a8307a4256c8797a34974c9edd5852cd905f086c759e8383e09bff1e68b36c3ea9036406852006290770bedfcaba0e23a0e840d16fc0246ad3160ccc09b8d0d3a2cd28ae6c2fff17dab22f1e61078aba2623c89ce6110e878b3c390f3595bca2df7d23783dfd126427cceb997bf4dac17f958d2ee523a2206206994597c13d831ec7867b321132b18b5bf3775c0d9040d1872979422e0655977feb2f289a4ab78af67bab0d17aab843678272e1a3dbef607c04aa6e5bd3a1a134c8ac063bf939e0a03fb07f59a73314e73794be0e57ac1b4e0000000000000000";

        gibUSDC(address(fed), usdcAmount * 5);

        fed.swapUSDCtoDOLA(usdcAmount * 5, swapData);

        uint estimatedDolaAmount = 10029974085862834929926144; // estimation from ODOS API

        assertEq(
            prevUsdcBal,
            USDC.balanceOf(address(fed)),
            "USDC didn't leave fed"
        );
        assertGt(
            prevDolaBal + (estimatedDolaAmount * 101) / 100,
            DOLA.balanceOf(address(fed)),
            "Fed didn't receive correct amount of DOLA Gt"
        );
        assertLt(
            prevDolaBal + estimatedDolaAmount,
            (DOLA.balanceOf(address(fed)) * 101) / 100,
            "Fed didn't receive correct amount of DOLA Lt"
        );
    }

    // Helpers

    function gibDOLA(address _user, uint _amount) internal {
        bytes32 slot;
        assembly {
            mstore(0, _user)
            mstore(0x20, 0x6)
            slot := keccak256(0, 0x40)
        }

        vm.store(address(DOLA), slot, bytes32(_amount));
    }

    function gibUSDC(address _user, uint _amount) internal {
        bytes32 slot;
        assembly {
            mstore(0, _user)
            mstore(0x20, 0x9)
            slot := keccak256(0, 0x40)
        }

        vm.store(address(USDC), slot, bytes32(_amount));
    }
}
