// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "ds-test/test.sol";
import "forge-std/Test.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IDola} from "src/interfaces/IDola.sol";
import {ArbiFed} from "src/arbi-fed/ArbiFed.sol";

contract ArbiFedTest is Test {
    //Tokens
    IDola public DOLA = IDola(0x865377367054516e17014CcdED1e7d814EDC9ce4);
    IERC20 public USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    // L1
    address gov = 0x926dF14a23BE491164dCF93f4c468A50ef659D5B;
    address chair = address(this); // we are the chair

    // L2
    address l2Chair = address(0x69);
    address auraFarmerL2 = address(0x420);
    

    //Numbas
    uint dolaAmount = 100_000e18;

    //Feds
    ArbiFed fed;

    error OnlyGov();
    error OnlyChair();
    error CantBurnZeroDOLA();
    error DeltaAboveMax();
    error ZeroGasPriceBid();
    
    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"), 17228840); 

        vm.warp(block.timestamp + 1 days);

        fed = new ArbiFed(gov, auraFarmerL2, chair, chair, chair);
        
        vm.prank(gov);
        DOLA.addMinter(address(fed));
    }


    function test_expansion() public {
        vm.startPrank(chair);
        uint256 gasPrice = 300000000;
        uint gasLimit = 275000;
        uint maxSubmissionCost = 0.05 ether;
        fed.setDefaultGasLimit(gasLimit);
        fed.setMaxSubmissionCost(maxSubmissionCost);
        fed.setGasPrice(gasPrice);
        vm.stopPrank();

        assertEq(DOLA.balanceOf(address(fed)),0);

        fed.expansion{value: maxSubmissionCost + gasLimit * gasPrice}(dolaAmount);

        assertEq(DOLA.balanceOf(address(fed)),0);


        vm.expectRevert(DeltaAboveMax.selector);
        fed.expansion{value: maxSubmissionCost + gasLimit * gasPrice}(dolaAmount * 10);
    }

    function test_contraction() public {
        vm.expectRevert(CantBurnZeroDOLA.selector);
        fed.contraction(0);

        assertEq(DOLA.balanceOf(address(fed)),0);

        // Mint some DOLA to check if contraction works
        vm.prank(gov);
        DOLA.mint(address(fed), dolaAmount);
        assertEq(DOLA.balanceOf(address(fed)),dolaAmount);

        fed.contraction(dolaAmount/2);

        assertEq(DOLA.balanceOf(address(fed)),dolaAmount/2);

        fed.contraction(dolaAmount/2);

        assertEq(DOLA.balanceOf(address(fed)),0);
    }

    function test_contractAll() public {
        // Mint some DOLA to check if contract all works
        vm.prank(gov);
        DOLA.mint(address(fed), dolaAmount);
      
        assertEq(DOLA.balanceOf(address(fed)),dolaAmount);

        fed.contractAll();

        assertEq(DOLA.balanceOf(address(fed)),0);
    }

    function test_resign() public {
        vm.expectRevert(OnlyChair.selector);
        vm.prank(gov);
        fed.resign();

        assertEq(fed.chair(), chair);

        fed.resign();

        assertEq(fed.chair(), address(0));        
    }

    function test_changeChair() public {
        assertEq(fed.chair(), chair);

        vm.prank(gov);
        fed.changeChair(address(0x699));

        assertEq(fed.chair(), address(0x699));
    }

    function test_AuraFarmer() public {
        assertEq(fed.auraFarmer(), auraFarmerL2);

        vm.prank(gov);
        fed.changeAuraFarmer(address(0x699));

        assertEq(fed.auraFarmer(), address(0x699));
    }
}
