// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "ds-test/test.sol";
import "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IDola} from "src/interfaces/IDola.sol";
import "src/arbi-fed/ArbiGovMessengerL1.sol";
import {AuraFarmer} from "src/arbi-fed/AuraFarmer.sol";
import {IInbox} from "arbitrum-nitro/contracts/src/bridge/IInbox.sol";

contract ArbiGovMessengerL1Test is Test {
    //Tokens
    IDola public DOLA = IDola(0x865377367054516e17014CcdED1e7d814EDC9ce4);
    IERC20 public USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    address l1ERC20Gateway = 0xa3A7B6F88361F48403514059F1F16C8E78d60EeC;
    address delayedInbox = 0x4Dbd4fc535Ac27206064B68FfCf827b0A60BAB3f;
    //EOAs
    address chair = address(this);
    address l2Chair = address(0x69);
    address auraFarmerL2 = address(0x42);
    address gov = 0x926dF14a23BE491164dCF93f4c468A50ef659D5B;

    //Numbas
    uint dolaAmount = 100_000e18;
    // uint usdcAmount = 100_000e6;
    uint maxDailyDelta = 1_000_000e18;

    //Feds
    ArbiGovMessengerL1 messenger;

    
    error OnlyGov();
    error OnlyAllowed();
    error OnlyChair();
    error DeltaAboveMax();
    
    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"), 17228840); 

        vm.warp(block.timestamp + 1 days);

        messenger = new ArbiGovMessengerL1(gov, delayedInbox, chair, chair);
        
        // vm.prank(gov);
        // DOLA.addMinter(address(fed));
    }


    function test_sendMessage_changeL2Chair() public {
        address newChair = address(0x70);
        uint _l1CallValue = 0.16 ether;
        uint _l2CallValue = 0.1 ether;
        bytes memory _data = abi.encodeWithSelector(AuraFarmer.changeL2Chair.selector, newChair);
        
        ArbiGasManager.L2GasParams memory _l2GasParams = ArbiGasManager.L2GasParams(0.05 ether, 195000,300000000);
        payable(gov).transfer(2 ether);
        vm.prank(gov);
        messenger.sendMessage{value:0.16 ether}(chair, chair, chair, _l1CallValue, _l2CallValue, _l2GasParams, _data);

        vm.expectRevert(OnlyAllowed.selector); 
        messenger.sendMessage{value:0.16 ether}(chair, chair, chair, _l1CallValue, _l2CallValue, _l2GasParams, _data);
    }

    function test_sendMessageOverload_changeL2Chair() public {
        address newChair = address(0x70);
        bytes4 selector = AuraFarmer.changeL2Chair.selector;
        bytes memory _data = abi.encodeWithSelector(selector, newChair);
        
        payable(gov).transfer(2 ether);
        vm.startPrank(gov);
        messenger.sendMessage{value:messenger.getDefaultMinimumCallValue()}(chair, selector, _data);
        vm.stopPrank();
        vm.expectRevert(OnlyAllowed.selector); 
        messenger.sendMessage{value:0.16 ether}(chair, selector, _data);
    }

    function test_setInbox() public {
        address inboxBefore = address(messenger.inbox());
        vm.expectRevert(OnlyGov.selector);
        messenger.setInbox(address(0));

        vm.prank(gov);
        messenger.setInbox(address(0));
        assertEq(address(messenger.inbox()), address(0));
        assertFalse(inboxBefore == address(messenger.inbox()));
    }

    function test_setAllowed() public {
        vm.expectRevert(OnlyGov.selector);
        messenger.setAllowed(address(0), true);
        assertFalse(messenger.allowList(address(0)));

        vm.prank(gov);
        messenger.setAllowed(address(0), true);
        assertEq(messenger.allowList(address(0)), true);

        vm.prank(gov);
        messenger.setAllowed(address(0), false);
        assertFalse(messenger.allowList(address(0)));
    }
}
