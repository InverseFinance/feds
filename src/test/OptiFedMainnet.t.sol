// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "ds-test/test.sol";
import "forge-std/Test.sol";
import { IERC20 } from "../interfaces/IERC20.sol";
import { IDola } from "../interfaces/velo/IDola.sol";
import {VeloFarmer} from "../velo-fed/VeloFarmer.sol";
import {OptiFed} from "../velo-fed/OptiFed.sol";
import "../interfaces/velo/ICurvePool.sol";

contract OptiFedMainnetTest is Test {
    //Tokens
    IDola public DOLA = IDola(0x865377367054516e17014CcdED1e7d814EDC9ce4);
    IERC20 public USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address public threeCrv = 0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490;
    address public crvFrax = 0x3175Df0976dFA876431C2E9eE6Bc45b65d3473CC;
    address public optiFedAddress = address(0xA);
    ICurvePool public immutable curvePool = ICurvePool(0xE57180685E3348589E9521aa53Af0BCD497E884d);

    address public threeCrvDolaPool = 0xAA5A67c256e27A5d80712c51971408db3370927D;

    address l1optiBridgeAddress = 0x99C9fc46f92E8a1c0deC1b1747d010903E884bE1;

    //EOAs
    address user = address(0x69);
    address chair = address(0xB);
    address gov = 0x926dF14a23BE491164dCF93f4c468A50ef659D5B;

    //Numbas
    uint dolaAmount = 1_000_00e18;
    uint usdcAmount = 1_000_00e6;

    //Feds
    OptiFed fed;

    error OnlyGov();
    error OnlyChair();
    error DeltaAboveMax();
    
    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"), 19512248);
        //vm.warp(block.timestamp + 1 days);
        
        vm.startPrank(chair);

        fed = new OptiFed(gov, chair, address(0x69), 25, 10);

        vm.stopPrank();
        vm.startPrank(gov);

        DOLA.addMinter(address(fed));

        vm.stopPrank();
    }

    function testL1_OptiFedExpansion() public {
        vm.startPrank(chair);

        uint prevBal = DOLA.balanceOf(l1optiBridgeAddress);

        fed.expansion(dolaAmount);

        assertEq(prevBal + dolaAmount, DOLA.balanceOf(l1optiBridgeAddress));
    }

    function testL1_OptiFedExpansionAndSwap_Half() public {
        vm.startPrank(chair);

        uint prevDolaBal = DOLA.balanceOf(l1optiBridgeAddress);
        uint prevUsdcBal = USDC.balanceOf(l1optiBridgeAddress);

        fed.expansionAndSwap(dolaAmount, dolaAmount / 2);

        uint estimatedUsdcAmount = dolaAmount / 2 / 1e12;

        assertEq(prevDolaBal + dolaAmount / 2, DOLA.balanceOf(l1optiBridgeAddress), "Bridge didn't receive correct amount of DOLA");
        assertEq(USDC.balanceOf(address(fed)),0, "CCTP Burn Failed");

        // assertGt(prevUsdcBal + estimatedUsdcAmount * 1001 / 1000, USDC.balanceOf(l1optiBridgeAddress), "Bridge didn't receive correct amount of USDC");
        // assertLt(prevUsdcBal + estimatedUsdcAmount, USDC.balanceOf(l1optiBridgeAddress) * 1001/1000, "Bridge didn't receive correct amount of USDC");
    }

    function testL1_OptiFedExpansionAndSwap(uint8 multi) public {
        uint256 multiplier = bound(uint(multi), 1, 10);
        uint dolaToSwap = dolaAmount * multiplier / 10;
        uint dolaToBridge = dolaAmount - dolaToSwap;

        vm.startPrank(chair);

        uint prevDolaBal = DOLA.balanceOf(l1optiBridgeAddress);
        uint prevUsdcBal = USDC.balanceOf(l1optiBridgeAddress);

        fed.expansionAndSwap(dolaAmount, dolaToSwap);

        uint estimatedUsdcAmount = dolaToSwap / 1e12;

        assertEq(prevDolaBal + dolaToBridge, DOLA.balanceOf(l1optiBridgeAddress), "Bridge didn't receive correct amount of DOLA");
        assertEq(USDC.balanceOf(address(fed)),0, "CCTP Burn Failed");

        // assertGt(prevUsdcBal + estimatedUsdcAmount * 1001 / 1000, USDC.balanceOf(l1optiBridgeAddress), "Bridge didn't receive correct amount of USDC");
        // assertLt(prevUsdcBal + estimatedUsdcAmount, USDC.balanceOf(l1optiBridgeAddress) * 1001/1000, "Bridge didn't receive correct amount of USDC");
    }

    function testL1_OptiFedExpansionAndSwap_Fails_IfSlippageRestraintUnmet() public {
        vm.startPrank(user);
        uint dolaDumpAmount = 200_000_000e18;
        gibDOLA(user, dolaDumpAmount);
        DOLA.approve(address(curvePool), type(uint).max);
        curvePool.add_liquidity([dolaDumpAmount, 0], 0);
        vm.stopPrank();

        vm.startPrank(chair);
        vm.expectRevert();
        fed.expansionAndSwap(dolaAmount, dolaAmount / 2);
    }

    function testL1_OptiFedSwapDOLAtoUSDC() public {
        vm.startPrank(chair);

        uint prevDolaBal = DOLA.balanceOf(address(fed));
        uint prevUsdcBal = USDC.balanceOf(address(fed));

        gibDOLA(address(fed), dolaAmount);
        fed.swapDOLAtoUSDC(dolaAmount);

        uint estimatedUsdcAmount = dolaAmount / 1e12;

        assertEq(prevDolaBal, DOLA.balanceOf(address(fed)), "DOLA didn't leave fed");
        assertGt(prevUsdcBal + estimatedUsdcAmount * 101 / 100, USDC.balanceOf(address(fed)), "Fed didn't receive correct amount of USDC");
        assertLt(prevUsdcBal + estimatedUsdcAmount, USDC.balanceOf(address(fed)) * 101/100, "Fed didn't receive correct amount of USDC");
    }

    function testL1_OptiFedSwapUSDCtoDOLA_Fails_IfSlippageRestraintUnmet_crvFrax() public {
        uint dumpAmount = 200_000_000e18;
        gibCrvFrax(user, dumpAmount);

        vm.startPrank(user);
        IERC20(crvFrax).approve(address(curvePool), type(uint).max);
        IERC20(crvFrax).balanceOf(user);
        curvePool.add_liquidity([0, dumpAmount], 0);
        vm.stopPrank();

        vm.startPrank(chair);
        gibUSDC(address(fed), usdcAmount);
        vm.expectRevert();
        fed.swapUSDCtoDOLA(usdcAmount);
    }

    function testL1_OptiFedSwapUSDCtoDOLA_Fails_IfSlippageRestraintUnmet_threeCrv() public {
        uint dumpAmount = 200_000_000e18;
        gib3crv(user, dumpAmount);

        vm.startPrank(gov);
        fed.changeCurvePool(threeCrvDolaPool);
        vm.stopPrank();
        
        vm.startPrank(user);
        IERC20(threeCrv).approve(address(threeCrvDolaPool), type(uint).max);
        ICurvePool(threeCrvDolaPool).add_liquidity([0, dumpAmount], 0);
        vm.stopPrank();

        vm.startPrank(chair);
        gibUSDC(address(fed), usdcAmount);
        vm.expectRevert();
        fed.swapUSDCtoDOLA(usdcAmount);
    }

    function testL1_OptiFedSwapDOLAtoUSDC_Fails_IfSlippageRestraintUnmet() public {
        vm.startPrank(user);
        uint dolaDumpAmount = 200_000_000e18;
        gibDOLA(user, dolaDumpAmount);
        DOLA.approve(address(curvePool), type(uint).max);
        curvePool.add_liquidity([dolaDumpAmount, 0], 0);
        vm.stopPrank();

        vm.startPrank(chair);
        gibDOLA(address(fed), dolaAmount);
        vm.expectRevert();
        fed.swapDOLAtoUSDC(dolaAmount);
    }

    function testL1_OptiFedSwapUSDCtoDOLA() public {
        vm.startPrank(chair);

        uint prevDolaBal = DOLA.balanceOf(address(fed));
        uint prevUsdcBal = USDC.balanceOf(address(fed));

        gibUSDC(address(fed), usdcAmount);
        USDC.balanceOf(address(fed));
        fed.swapUSDCtoDOLA(usdcAmount);

        uint estimatedDolaAmount = usdcAmount * 1e12;

        assertEq(prevUsdcBal, USDC.balanceOf(address(fed)), "USDC didn't leave fed");
        assertGt(prevDolaBal + estimatedDolaAmount * 101 / 100, DOLA.balanceOf(address(fed)), "Fed didn't receive correct amount of DOLA");
        assertLt(prevDolaBal + estimatedDolaAmount, DOLA.balanceOf(address(fed)) * 101/100, "Fed didn't receive correct amount of DOLA");
    }

    function testL1_changeVeloFarmer_fail_whenCalledByNonGov() public {
        vm.startPrank(chair);

        vm.expectRevert(OnlyGov.selector);
        fed.changeVeloFarmer(user);
    }

    function testL1_changeChair_fail_whenCalledByNonGov() public {
        vm.startPrank(user);

        vm.expectRevert(OnlyGov.selector);
        fed.changeChair(user);
    }

    function testL1_setPendingGov_fail_whenCalledByNonGov() public {
        vm.startPrank(user);

        vm.expectRevert(OnlyGov.selector);
        fed.setPendingGov(user);
    }

    function testL1_govChange() public {
        vm.startPrank(gov);

        fed.setPendingGov(user);
        vm.stopPrank();

        vm.startPrank(user);

        fed.claimGov();

        assertEq(fed.gov(), user, "user failed to be set as gov");
        assertEq(fed.pendingGov(), address(0), "pendingGov failed to be set as 0 address");
    }

    function testL1_setMaxSlippageDolaToUsdc_fail_whenCalledByNonGov() public {
        vm.startPrank(user);

        vm.expectRevert(OnlyGov.selector);
        fed.setMaxSlippageDolaToUsdc(500);
    }

    function testL1_setMaxSlippageUsdcToDola_fail_whenCalledByNonGov() public {
        vm.startPrank(user);

        vm.expectRevert(OnlyGov.selector);
        fed.setMaxSlippageUsdcToDola(500);
    }

    function testL1_resign_fail_whenCalledByNonChair() public {
        vm.startPrank(user);

        vm.expectRevert(OnlyChair.selector);
        fed.resign();
    }

    function testL1_swapDOLAtoUSDC_fail_whenCalledByNonChair() public {
        vm.startPrank(user);

        vm.expectRevert(OnlyChair.selector);
        fed.swapDOLAtoUSDC(1e18);
    }

    function testL1_swapUSDCtoDOLA_fail_whenCalledByNonChair() public {
        vm.startPrank(user);

        vm.expectRevert(OnlyChair.selector);
        fed.swapUSDCtoDOLA(1e6);
    }

    function testL1_contractAll_fail_whenCalledByNonChair() public {
        vm.startPrank(user);

        vm.expectRevert(OnlyChair.selector);
        fed.contractAll();
    }

    function testL1_contract_fail_whenCalledByNonChair() public {
        vm.startPrank(user);

        vm.expectRevert(OnlyChair.selector);
        fed.contraction(1e18);
    }

    //My loyal helpers

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

    function gib3crv(address _user, uint _amount) internal {
        bytes32 slot;
        assembly {
            mstore(0, 0x3)
            mstore(0x20, _user)
            slot := keccak256(0, 0x40)
        }

        vm.store(address(threeCrv), slot, bytes32(_amount));
    }

    function gibCrvFrax(address _user, uint _amount) internal {
        vm.stopPrank();
        vm.startPrank(0xDcEF968d416a41Cdac0ED8702fAC8128A64241A2);
        IERC20(crvFrax).mint(_user, _amount);
        vm.stopPrank();
    }

    function gibToken(address _token, address _user, uint _amount) public {
        bytes32 slot;
        assembly {
            mstore(0, _user)
            mstore(0x20, 0x0)
            slot := keccak256(0, 0x40)
        }

        vm.store(_token, slot, bytes32(uint256(_amount)));
    }
}
