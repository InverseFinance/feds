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
        vm.createSelectFork(vm.rpcUrl("mainnet"), 21724600);

        initialize(optiBridge, DOLA_OPTI, USDC_OPTI, OPTIMISM_CCTP_DOMAIN);
    }

    bytes swapData =
        hex"83bd37f90001865377367054516e17014ccded1e7d814edc9ce40001a0b86991c6218b36c1d19d4a2e9eb0ce3606eb480ad3c21bcecceda100000005e66b33510a2666660001B28Ca7e465C452cE4252598e0Bc96Aeba553CF82000000015615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f000000000c03040e0160b954850a01000101020001012a74384f4a020003020001000a030001040200010246000005060700044a010909070100060d01090a0b01004a03010c0701000257030100080d007fffff9bff000000000000000000000000000000ff17dab22f1e61078aba2623c89ce6110e878b3c865377367054516e17014ccded1e7d814edc9ce48272e1a3dbef607c04aa6e5bd3a1a134c8ac063b744793b5110f6ca9cc7cdfe1ce16677c3eb192ef0655977feb2f289a4ab78af67bab0d17aab843670655977feb2f289a4ab78af67bab0d17aab84367f939e0a03fb07f59a73314e73794be0e57ac1b4e31373595f40ea48a7aab6cbcb0d377c6066e2dca390f3595bca2df7d23783dfd126427cceb997bf4867b321132b18b5bf3775c0d9040d1872979422e9d39a5de30e57443bff2a8307a4256c8797a34974dece678ceceb27446b35c672dc7d61f30bad69edac17f958d2ee523a2206206994597c13d831ec700000000000000000000000000000000000000000000000000000000";
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
        uint dolaAmount = 2_000_000 ether;
        gibDOLA(address(fed), dolaAmount);
        // Swap 2M DOLA to USDC
        bytes
            memory swapData = hex"83bd37f90001865377367054516e17014ccded1e7d814edc9ce40001a0b86991c6218b36c1d19d4a2e9eb0ce3606eb480b01a784379d99db420000000601cc3810b96a2666660001B28Ca7e465C452cE4252598e0Bc96Aeba553CF82000000015615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f000000000c03040e016328c32b0a010001010200010128dc1b4d4a020003020001000a030001040200010246000005060700044a010909070100060d01090a0b01004a03010c0701000257030100080d007fffff9bff000000000000000000000000000000ff17dab22f1e61078aba2623c89ce6110e878b3c865377367054516e17014ccded1e7d814edc9ce48272e1a3dbef607c04aa6e5bd3a1a134c8ac063b744793b5110f6ca9cc7cdfe1ce16677c3eb192ef0655977feb2f289a4ab78af67bab0d17aab843670655977feb2f289a4ab78af67bab0d17aab84367f939e0a03fb07f59a73314e73794be0e57ac1b4e31373595f40ea48a7aab6cbcb0d377c6066e2dca390f3595bca2df7d23783dfd126427cceb997bf4867b321132b18b5bf3775c0d9040d1872979422e9d39a5de30e57443bff2a8307a4256c8797a34974dece678ceceb27446b35c672dc7d61f30bad69edac17f958d2ee523a2206206994597c13d831ec700000000000000000000000000000000000000000000000000000000";
        fed.swapDOLAtoUSDC(dolaAmount, swapData);

        uint estimatedUsdcAmount = 1976625576298; // estimation from ODOS API

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
            memory swapData = hex"83bd37f90001a0b86991c6218b36c1d19d4a2e9eb0ce3606eb480001865377367054516e17014ccded1e7d814edc9ce40609184e72a0000b0848bb21eec4bb800000001999990001B28Ca7e465C452cE4252598e0Bc96Aeba553CF82000000015615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f000000003015092b019671bde719010001020301010609d6222702000204010538d238070200020479c58f70905f734641735bc61e45c19dd9ad60bc0000000000000000000004e70100da8974070200020406df3b2bbb68adc8b0e302443692037ed9f91b420000000000000000000000630103012a9b56020502040102010678589f4b02060201020101255f01560207020401020106b9800c57020001080201800000640106d1d2760d02000902010106c246cd0d02000a020101073765930d02000b02010101aa88020d02000c02010106d233621a020d02010103fdc29d07030f020f8353157092ed8be69a9df8f95af097bbf33cb2af0000000000000000000005d9011de2692457030f011002008000000001078965aa57030f0111020080000000010241353e0d030f1202000107f0459a07030f020f3932b187f440ce7703653b3908edc5bb7676c28300020000000000000000066401415175490704140214b819feef8f0fcdc268afe14162983a69f6bf179e00000000000000000000068901b28c38580a050001150201000173efc5400a0617011702010001dc7b0c160d0700180200017f9bf4390708000219c2aa60465bffa1a88f5ba471a59ca0435c3ec5c100020000000000000000062c0007080002192875f3effe9ec897d7e4c32680d77ca3e628f33a0002000000000000000006d10246001b1b031c010a46011e1e1f14010c0a05000016200001060a0500000e0f0001080a032200131401000f229cf3954a0500222300010e2c042423250002040d011e2604001007011e19148d93b853849b9884e2bb413444ec23eb5366ee910002000000000000000006b3060a08010021270100084a0801282501000a4a0801292a0100000a0801001a1c0100020a0801001d140100ff0000000000000000000000000000000000000000a188eec8f81263234da3622a406892f3d630f98ca0b86991c6218b36c1d19d4a2e9eb0ce3606eb48dc035d45d973e3ec169d2276ddab16f1e407384fdac17f958d2ee523a2206206994597c13d831ec7a5407eae9ba41422680e2e00537571bcc53efbfd1116898dda4015ed8ddefb84b6e8bc24528af2d83333333acdedbbc9ad7bda0876e60714195681c531373595f40ea48a7aab6cbcb0d377c6066e2dca04c8577958ccc170eb3d2cca76f9d51bc6e42d8f7858e59e0c01ea06df3af3d20ac7b0003275d4bf3416cf6c708da44db2624d63ea0aaef7113527c6fa6e8e97ececdc36302eca534f63439b1e79487bc9f93163c99695c6526b799ebca2207fdf7d61ad635ef0056a597d13863b73825cca29723657859540d16fc0246ad3160ccc09b8d0d3a2cd28ae6c2f14cf6d2fe3e1b326114b07d22a6f6bb59e346c67c8c9cfad493cffffd6684da0f45d141e33b6ef275c95d4b1c3321cf898d25949f41d50be2db5bc1dd29f8980852c2c76fc3f6e96a7aa06e0bedcc1b19d39a5de30e57443bff2a8307a4256c8797a349702950460e2b9529d0e00284a5fa2d7bdf3fa4d72625e92624bc2d88619accc1788365a69767f6200383e6b4437b59fff47b619cba855ca29342a8559c63b0708e2f7e69cb8a1df0e1389a98c35a76d52e07f9d810a48ab5c3c914ba3ca53af14e4491e8a8b83c4aa949254895507d09365229bc3a8c7f710a3931d71877c0e7a3148cb7eb4463524fec27fbda3931d71877c0e7a3148cb7eb4463524fec27fbd744793b5110f6ca9cc7cdfe1ce16677c3eb192ef9d39a5de30e57443bff2a8307a4256c8797a34974c9edd5852cd905f086c759e8383e09bff1e68b36c3ea9036406852006290770bedfcaba0e23a0e8ff17dab22f1e61078aba2623c89ce6110e878b3c0cd6f267b2086bea681e922e19d40512511be538853d955acef822db058eb8505911ed77f175b99edcef968d416a41cdac0ed8702fac8128a64241a23175df0976dfa876431c2e9ee6bc45b65d3473cc867b321132b18b5bf3775c0d9040d1872979422e0655977feb2f289a4ab78af67bab0d17aab84367e57180685e3348589e9521aa53af0bcd497e884d8272e1a3dbef607c04aa6e5bd3a1a134c8ac063bf939e0a03fb07f59a73314e73794be0e57ac1b4e000000000000000000000000000000000000000000000000";

        gibUSDC(address(fed), usdcAmount * 5);

        fed.swapUSDCtoDOLA(usdcAmount * 5, swapData);

        uint estimatedDolaAmount = 10014868929933388833357824; // estimation from ODOS API

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
