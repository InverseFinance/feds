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
        vm.createSelectFork(vm.rpcUrl("mainnet"), 21724149);

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

        gibDOLA(address(fed), dolaAmount * 5);
        // Swap 2M DOLA to USDC
        bytes
            memory swapData = hex"83bd37f90001865377367054516e17014ccded1e7d814edc9ce40001a0b86991c6218b36c1d19d4a2e9eb0ce3606eb480b084595161401484a0000000608180ee79c482666660001B28Ca7e465C452cE4252598e0Bc96Aeba553CF82000000015615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f00000000411a123f01003fb9b10701000102441b8a1980f2f2e43a9397099d15cc2fe6d3625000020000000000000000035f01001df073030100010301001e0100e7bae70d0100040100010063572b030200010501011e016512ff7c0a0300010601000101001c108f4a040007010001010031356f4a040008010001012852f7604a050009010001010e40d8330a0600010a01000101ffad7cec0a0700010b010001000d08000c01010800000337f5cd21000402090900010d0201000f079946f400010f014695f50a0a00010e0f01000ffd617a170d0b00100f010e070c000f118d93b853849b9884e2bb413444ec23eb5366ee910002000000000000000006b30d02089e43460713131415000c0d0d0016140006460a0017181900055bf231ee060300040d06001a1b000b39e5c32d0a021d011d1901000b462f6e0a0a0e1f011f1901000bdbb8c7c80a0f0001201901000bbaee52f04a1000211901000a4a110022190100122708001b2317014d026a070800242379c58f70905f734641735bc61e45c19dd9ad60bc0000000000000000000004e7170169849e07080024238353157092ed8be69a9df8f95af097bbf33cb2af0000000000000000000005d91708cfaeb24b0825240201174cae5c1f570800012624007fffff9b1718d0f5bb0d08002724001701ec6abf0d080028240017f9d730990d08002924001709aead6f0d08002a2400161a082b2400020708000f23b819feef8f0fcdc268afe14162983a69f6bf179e000000000000000000000689144a08002c19010021942e8b6056082d2e230001200d08002f2e01040a0800001c3000011c0a0800001e310001065408322301000201a41fa5d52df057080001333401800000051fb479b25d570800013534018000000a1e07080034233932b187f440ce7703653b3908edc5bb7676c2830002000000000000000006640e570800001215007ffffffb1a0d0800363701220d08003839010c55083a3b2301000855083c02230200002b083d3e23011919d286b80708001123c2aa60465bffa1a88f5ba471a59ca0435c3ec5c100020000000000000000062c1807080011232875f3effe9ec897d7e4c32680d77ca3e628f33a0002000000000000000006d1100223ff00000000000000000000000000000000865377367054516e17014ccded1e7d814edc9ce441d5d79431a913c4ae7d69a668ecdfe5ff9dfb685ba61c0a8c4dcccc200cd0ccc40a5725a426d002bd1f921786e12a80f2184e4d6a5cacb25dc673c9ecfbe9b182f6477a93065c1c11271232147838e5ff17dab22f1e61078aba2623c89ce6110e878b3c9547429c0e2c3a8b88c6833b58fce962734c0e8caa5a67c256e27a5d80712c51971408db3370927d8272e1a3dbef607c04aa6e5bd3a1a134c8ac063b8b83c4aa949254895507d09365229bc3a8c7f710744793b5110f6ca9cc7cdfe1ce16677c3eb192ef7c082bf85e01f9bb343dbb460a14e51f67c58cfb6bd88c57523bf138a19b263e8ebc8661c836b17157064f49ad7123c92560882a45518374ad982e859d39a5de30e57443bff2a8307a4256c8797a3497867b321132b18b5bf3775c0d9040d1872979422ee07f9d810a48ab5c3c914ba3ca53af14e4491e8adf9c440111a17eafbecf5db37dd04c948e878878a3931d71877c0e7a3148cb7eb4463524fec27fbda3931d71877c0e7a3148cb7eb4463524fec27fbddc035d45d973e3ec169d2276ddab16f1e407384fd4e4e4020589dd0fe13c06373d25786af7a77ab30655977feb2f289a4ab78af67bab0d17aab843670655977feb2f289a4ab78af67bab0d17aab84367f939e0a03fb07f59a73314e73794be0e57ac1b4e4585fe77225b41b697c938b018e2ac67ac5a20c0c02aaa39b223fe8d0a0e5c4f27ead9083c756cc202950460e2b9529d0e00284a5fa2d7bdf3fa4d72f55b0f6f2da5ffddb104b58a60f2862745960442383e6b4437b59fff47b619cba855ca29342a8559625e92624bc2d88619accc1788365a69767f6200635ef0056a597d13863b73825cca2972365785950cd6f267b2086bea681e922e19d40512511be5389978c6b08d28d3b74437c917c5dd7c026df9d55ca0b86991c6218b36c1d19d4a2e9eb0ce3606eb48dac17f958d2ee523a2206206994597c13d831ec71116898dda4015ed8ddefb84b6e8bc24528af2d831373595f40ea48a7aab6cbcb0d377c6066e2dca04c8577958ccc170eb3d2cca76f9d51bc6e42d8f7858e59e0c01ea06df3af3d20ac7b0003275d4bf3416cf6c708da44db2624d63ea0aaef7113527c6fa6e8e97ececdc36302eca534f63439b1e79487bc9f93163c99695c6526b799ebca2207fdf7d61ad4dece678ceceb27446b35c672dc7d61f30bad69edcef968d416a41cdac0ed8702fac8128a64241a2853d955acef822db058eb8505911ed77f175b99ec63b0708e2f7e69cb8a1df0e1389a98c35a76d524c9edd5852cd905f086c759e8383e09bff1e68b36c3ea9036406852006290770bedfcaba0e23a0e8000000000000000000000000000000000000000014cf6d2fe3e1b326114b07d22a6f6bb59e346c6740d16fc0246ad3160ccc09b8d0d3a2cd28ae6c2fc8c9cfad493cffffd6684da0f45d141e33b6ef27893f503fac2ee1e5b78665db23f9c94017aae97d64aa3364f17a4d01c6f1751fd97c2bd3d7e7f1d54e0924d3a751be199c426d52fb1f2337fa96f7365f98805a4e8be255a32880fdec7f6728c6568ba07f86bf177dd4f3494b841a37e810a34dd56c829b2260fac5e5542a773aa44fbcfedf7c193bc2c5995426178799ee0a0181a89b4f57efddfab49941ecbebc44782c7db0a1a60cb6fe97d0b483032ff1c76c3f90f043a72fa612cbac8115ee7e52bde6e4900000000000000000";
        fed.swapDOLAtoUSDC(dolaAmount * 5, swapData);

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
            memory swapData = hex"83bd37f90001a0b86991c6218b36c1d19d4a2e9eb0ce3606eb480001865377367054516e17014ccded1e7d814edc9ce40609184e72a0000b08490c63a8f42c800000001999990001B28Ca7e465C452cE4252598e0Bc96Aeba553CF82000000015615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f000000002a1109280194ba53351901000102030101058aa52a070200020479c58f70905f734641735bc61e45c19dd9ad60bc0000000000000000000004e70102b31f2856020502040102010a2540be4b0206020102010ae78baf5702000107020180000064010b1b93510d0200080201010ac040c10d0200090201010c3e8cec0d02000a0201010c61132f1a020b0201013253f5dd07030d020db819feef8f0fcdc268afe14162983a69f6bf179e0000000000000000000006890184917a2f0a0400010e020100013b649dcd0a05100110020100014677ef1a5706120112020080000000015968e5015706120113020080000000011947f11007061202143932b187f440ce7703653b3908edc5bb7676c28300020000000000000000066401c6fdec970d0700150200017fc1bcb60708000216c2aa60465bffa1a88f5ba471a59ca0435c3ec5c100020000000000000000062c0007080002162875f3effe9ec897d7e4c32680d77ca3e628f33a0002000000000000000006d102460018180319010846011b1b1c0d010a0a0400000f1d00010c0a04000011140001060a061f000c0d01000f2d0a44de4a04001f2000010e2c032120220002040d011b2304001007011b160d8d93b853849b9884e2bb413444ec23eb5366ee910002000000000000000006b30c0a0801001e240100064a080125220100084a080126270100000a08010017190100020a0801001a0d0100ff0000000000000000000000000000000000000000a188eec8f81263234da3622a406892f3d630f98ca0b86991c6218b36c1d19d4a2e9eb0ce3606eb48dc035d45d973e3ec169d2276ddab16f1e407384fdac17f958d2ee523a2206206994597c13d831ec7a5407eae9ba41422680e2e00537571bcc53efbfd1116898dda4015ed8ddefb84b6e8bc24528af2d831373595f40ea48a7aab6cbcb0d377c6066e2dca04c8577958ccc170eb3d2cca76f9d51bc6e42d8f7858e59e0c01ea06df3af3d20ac7b0003275d4bf3416cf6c708da44db2624d63ea0aaef7113527c6c9f93163c99695c6526b799ebca2207fdf7d61add29f8980852c2c76fc3f6e96a7aa06e0bedcc1b19d39a5de30e57443bff2a8307a4256c8797a349702950460e2b9529d0e00284a5fa2d7bdf3fa4d72625e92624bc2d88619accc1788365a69767f6200383e6b4437b59fff47b619cba855ca29342a8559635ef0056a597d13863b73825cca29723657859514cf6d2fe3e1b326114b07d22a6f6bb59e346c67c8c9cfad493cffffd6684da0f45d141e33b6ef2740d16fc0246ad3160ccc09b8d0d3a2cd28ae6c2fc63b0708e2f7e69cb8a1df0e1389a98c35a76d52e07f9d810a48ab5c3c914ba3ca53af14e4491e8a8b83c4aa949254895507d09365229bc3a8c7f710a3931d71877c0e7a3148cb7eb4463524fec27fbda3931d71877c0e7a3148cb7eb4463524fec27fbd744793b5110f6ca9cc7cdfe1ce16677c3eb192ef9d39a5de30e57443bff2a8307a4256c8797a34974c9edd5852cd905f086c759e8383e09bff1e68b36c3ea9036406852006290770bedfcaba0e23a0e8ff17dab22f1e61078aba2623c89ce6110e878b3c0cd6f267b2086bea681e922e19d40512511be538853d955acef822db058eb8505911ed77f175b99edcef968d416a41cdac0ed8702fac8128a64241a23175df0976dfa876431c2e9ee6bc45b65d3473cc867b321132b18b5bf3775c0d9040d1872979422e0655977feb2f289a4ab78af67bab0d17aab84367e57180685e3348589e9521aa53af0bcd497e884d8272e1a3dbef607c04aa6e5bd3a1a134c8ac063bf939e0a03fb07f59a73314e73794be0e57ac1b4e0000000000000000000000000000000000000000";

        gibUSDC(address(fed), usdcAmount * 5);

        fed.swapUSDCtoDOLA(usdcAmount * 5, swapData);

        uint estimatedDolaAmount = 10027542987232821790113792; // estimation from ODOS API

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
