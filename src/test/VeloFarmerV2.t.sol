// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import { IERC20 } from "src/interfaces/IERC20.sol";
import { IDola } from "src/interfaces/IDola.sol";
import "src/interfaces/opti/IL2CrossDomainMessenger.sol";
import { VeloFarmerV2, IRouter, IGauge} from "src/velo-fed/VeloFarmerV2.sol";
import {OptiFed} from "src/velo-fed/OptiFed.sol";

contract VeloFarmerV2Test is Test {
    IRouter public router = IRouter(payable(0xa062aE8A9c5e11aaA026fc2670B0D65cCc8B2858));
    //IGauge public dolaGauge = IGauge(0xAFD2c84b9d1cd50E7E18a55e419749A6c9055E1F);
    IGauge public dolaGauge = IGauge(0xa1034Ed2C9eb616d6F7f318614316e64682e7923);
    IDola public DOLA = IDola(0x8aE125E8653821E851F12A49F7765db9a9ce7384);
    IERC20 public VELO = IERC20(0x9560e827aF36c94D2Ac33a39bCE1Fe78631088Db);
    IERC20 public USDC = IERC20(0x7F5c764cBc14f9669B88837ca1490cCa17c31607);
    address public l2optiBridgeAddress = 0x4200000000000000000000000000000000000010;
    //address public dolaUsdcPoolAddy = 0x6C5019D345Ec05004A7E7B0623A91a0D9B8D590d;
    address public dolaUsdcPoolAddy = 0xB720FBC32d60BB6dcc955Be86b98D8fD3c4bA645;
    address public veloTokenAddr = 0x9560e827aF36c94D2Ac33a39bCE1Fe78631088Db;
    address public optiFedAddress = address(0xA);
    IL2CrossDomainMessenger public l2CrossDomainMessenger = IL2CrossDomainMessenger(0x4200000000000000000000000000000000000007);
    address public l1CrossDomainMessenger = 0x36BDE71C97B33Cc4729cf772aE268934f7AB70B2;
    address public treasury = 0xa283139017a2f5BAdE8d8e25412C600055D318F8;

    uint nonce;

    //EOAs
    address user = address(69);
    address chair = address(0xB);
    address l2chair = address(0xC);
    address gov = address(0x607);
    address guardian = address(0xD);

    //Numbas
    uint dolaAmount = 1_000e18;
    uint usdcAmount = 1_000e6;

    uint maxSlippageBpsDolaToUsdc = 100;
    uint maxSlippageBpsUsdcToDola = 100;
    uint maxSlippageLiquidity = 1000;

    //Feds
    VeloFarmerV2 fed;

    error OnlyGov();
    error OnlyChair();
    error OnlyGovOrGuardian();
    error PercentOutOfRange();
    error LiquiditySlippageTooHigh();

    function relayGovMessage(bytes memory message) public {
        l2CrossDomainMessenger.relayMessage(address(fed), gov, message, nonce++);
    }

    function relayChairMessage(bytes memory message) public {
        l2CrossDomainMessenger.relayMessage(address(fed), chair, message, nonce++);
    }

    function relayUserMessage(bytes memory message) public {
        l2CrossDomainMessenger.relayMessage(address(fed), user, message, nonce++);
    }
    
    function setUp() public {
        vm.label(veloTokenAddr, "VELO");

        vm.startPrank(chair);
        fed = new VeloFarmerV2(gov, chair, l2chair, treasury, guardian, l2optiBridgeAddress, optiFedAddress, maxSlippageBpsDolaToUsdc, maxSlippageBpsUsdcToDola, maxSlippageLiquidity);
        vm.makePersistent(address(fed));

        vm.stopPrank();
        address voter = dolaGauge.voter();
        deal(address(VELO), address(voter), 1000 ether);
        vm.startPrank(voter);
        VELO.approve(address(dolaGauge), 1000 ether);
        dolaGauge.notifyRewardAmount(1000 ether);
        vm.stopPrank();
    }

    // L2

    function testL2_DepositAndClaimVeloRewards() public {
        gibDOLA(address(fed), dolaAmount * 3);
        gibUSDC(address(fed), usdcAmount * 3);

        uint initialVelo = VELO.balanceOf(address(treasury));

        vm.startPrank(address(l2CrossDomainMessenger));
        mockXDomainMessageSender(gov);
        fed.setMaxSlippageLiquidity(5000);
        vm.stopPrank();

        vm.startPrank(l2chair);
        fed.deposit(dolaAmount / 2, usdcAmount / 2);

        vm.roll(block.number + 100000);
        vm.warp(block.timestamp + (10_0000 * 60));
        fed.claimVeloRewards();

        assertGt(VELO.balanceOf(address(treasury)), initialVelo, "No rewards claimed");
    }

    function testL2_SwapAndClaimVeloRewards() public {
        gibDOLA(address(fed), dolaAmount * 3);
        gibUSDC(address(fed), usdcAmount * 3);

        uint initialVelo = VELO.balanceOf(address(treasury));

        vm.startPrank(address(l2CrossDomainMessenger));
        mockXDomainMessageSender(gov);
        fed.setMaxSlippageLiquidity(5000);
        vm.stopPrank();

        vm.startPrank(l2chair);
        fed.deposit(dolaAmount, usdcAmount);
        vm.roll(block.number + 10000);
        vm.warp(block.timestamp + (10_000 * 60));
        fed.claimVeloRewards();

        assertGt(VELO.balanceOf(address(treasury)), initialVelo, "No rewards claimed");
    }

    function testL2_SwapAndClaimRewards() public {
        gibDOLA(address(fed), dolaAmount * 3);
        gibUSDC(address(fed), usdcAmount * 3);

        uint initialVelo = VELO.balanceOf(address(treasury));

        vm.startPrank(address(l2CrossDomainMessenger));
        mockXDomainMessageSender(gov);
        fed.setMaxSlippageLiquidity(5000);
        vm.stopPrank();

        vm.startPrank(l2chair);
        fed.depositAll();
        vm.roll(block.number + 10000);
        vm.warp(block.timestamp + (10_000 * 60));
        address[] memory addr = new address[](1);
        addr[0] = 0x3c8B650257cFb5f272f799F5e2b4e65093a11a05;
        fed.claimVeloRewards();

        assertGt(VELO.balanceOf(address(treasury)), initialVelo, "No rewards claimed");
    }

    function testL2_Deposit_Succeeds_WhenSlippageLtMaxLiquiditySlippage() public {
        gibDOLA(address(fed), dolaAmount);
        gibUSDC(address(fed), usdcAmount * 2);

        uint initialPoolTokens = dolaGauge.balanceOf(address(fed));

        vm.prank(address(l2CrossDomainMessenger));
        mockXDomainMessageSender(gov);
        fed.setMaxSlippageLiquidity(100);

        vm.prank(l2chair);
        fed.depositAll();

        assertGt(dolaGauge.balanceOf(address(fed)), initialPoolTokens, "depositAll failed");
    }

    function testL2_SwapDolaToUsdc_Fails_WhenSlippageGtMaxDolaToUsdcSlippage() public {
        gibDOLA(address(fed), dolaAmount  * 3);

        vm.startPrank(address(l2CrossDomainMessenger));
        mockXDomainMessageSender(gov);
        fed.setMaxSlippageLiquidity(50);
        fed.setMaxSlippageDolaToUsdc(1);
        vm.stopPrank();

        vm.startPrank(l2chair);
        vm.expectRevert(abi.encodeWithSelector(IRouter.InsufficientOutputAmount.selector));
        fed.swapDOLAtoUSDC(dolaAmount * 3);
    }

    function testL2_SwapUsdcToDola_Fails_WhenSlippageGtMaxUsdcToDolaSlippage() public {
        gibUSDC(address(fed), usdcAmount*5);

        uint usdcToSwap = usdcAmount*5;
        gibUSDC(address(user), usdcToSwap);
        vm.startPrank(user);
        USDC.approve(address(router), type(uint).max);
        router.swapExactTokensForTokens(usdcToSwap, 0, getRoute(address(USDC), address(DOLA)), address(user), block.timestamp);
        vm.stopPrank();

        vm.startPrank(address(l2CrossDomainMessenger));
        mockXDomainMessageSender(gov);
        fed.setMaxSlippageUsdcToDola(1);
        vm.stopPrank();

        vm.startPrank(l2chair);
        vm.expectRevert(abi.encodeWithSelector(IRouter.InsufficientOutputAmount.selector));
        fed.swapUSDCtoDOLA(usdcAmount*5);
    }

    function testL2_Withdraw() public {
        vm.startPrank(l2optiBridgeAddress);
        DOLA.mint(address(fed), dolaAmount);
        USDC.mint(address(fed), dolaAmount / 1e12);
        vm.stopPrank();

        vm.startPrank(address(l2CrossDomainMessenger));
        mockXDomainMessageSender(gov);
        fed.setMaxSlippageLiquidity(1000);
        vm.stopPrank();

        vm.startPrank(l2chair);
        fed.depositAll();
        fed.withdrawLiquidity(dolaAmount);
        
        fed.withdrawToL1OptiFed(DOLA.balanceOf(address(fed)), USDC.balanceOf(address(fed)));
    }

    function testL2_Withdraw_FromL1Chair(uint amountDola) public {
        amountDola = bound(amountDola, 10_000e18, 1_000_000_000e18);    

        vm.startPrank(l2optiBridgeAddress);
        DOLA.mint(address(fed), amountDola);
        USDC.mint(address(fed), amountDola / 1e12);
        vm.stopPrank();

        vm.startPrank(address(l2CrossDomainMessenger));
        mockXDomainMessageSender(gov);
        fed.setMaxSlippageLiquidity(4000);
        vm.stopPrank();

        uint prevLiquidity = dolaGauge.balanceOf(address(fed));

        vm.startPrank(address(l2CrossDomainMessenger));
        mockXDomainMessageSender(chair);
        fed.depositAll();
        vm.stopPrank();

        assertLt(prevLiquidity, dolaGauge.balanceOf(address(fed)), "depositAll failed");
        prevLiquidity = dolaGauge.balanceOf(address(fed));

        vm.startPrank(address(l2CrossDomainMessenger));
        mockXDomainMessageSender(chair);
        fed.withdrawLiquidity(amountDola);
        vm.stopPrank();

        assertGt(prevLiquidity, dolaGauge.balanceOf(address(fed)), "withdrawLiquidity failed");

        uint prevDola = DOLA.balanceOf(address(fed));
        uint prevUsdc = USDC.balanceOf(address(fed));

        vm.startPrank(address(l2CrossDomainMessenger));
        mockXDomainMessageSender(chair);
        fed.withdrawToL1OptiFed(DOLA.balanceOf(address(fed)), USDC.balanceOf(address(fed)));
        vm.stopPrank();

        assertGt(prevDola, DOLA.balanceOf(address(fed)), "Withdraw to L1 failed");
        assertGt(prevUsdc, USDC.balanceOf(address(fed)), "Withdraw to L1 failed");
    }

    function testL2_WithdrawAndSwap() public {
        vm.startPrank(l2optiBridgeAddress);
        DOLA.mint(address(fed), dolaAmount);
        gibUSDC(address(fed), usdcAmount);
        vm.stopPrank();

        vm.startPrank(address(l2CrossDomainMessenger));
        mockXDomainMessageSender(gov);
        fed.setMaxSlippageLiquidity(1000);
        vm.stopPrank();

        vm.startPrank(l2chair);
        fed.depositAll();

        uint dolaBal = DOLA.balanceOf(address(fed));
        uint usdcBal = USDC.balanceOf(address(fed)) * fed.DOLA_USDC_CONVERSION_MULTI();
        uint withdrawAmount = dolaAmount - dolaBal - usdcBal;

        fed.withdrawLiquidityAndSwapToDOLA(withdrawAmount);
    }

    function testL2_onlyChair_fail_whenCalledByBridge_NonChairSender() public {

        address prevChair = fed.chair();

        vm.startPrank(address(l2CrossDomainMessenger));
        mockXDomainMessageSender(address(0x999));
        vm.expectRevert();
        fed.resign();
        vm.stopPrank();

        assertEq(prevChair, fed.chair(), "onlyChair function did not revert properly");
        assertTrue(fed.chair() != address(0), "onlyChair function did not revert properly");
    }

    function testL2_resign_fromChair() public {

        address prevChair = fed.chair();

        vm.startPrank(address(l2CrossDomainMessenger));
        mockXDomainMessageSender(chair);
        fed.resign();
        vm.stopPrank();

        assertTrue(prevChair != fed.chair(), "onlyChair function did not revert properly");
        assertEq(fed.chair(), address(0), "onlyChair function did not revert properly");
    }

    function testL2_resign_fromL2Chair() public {
        vm.startPrank(l2chair);

        address prevChair = fed.l2chair();
        fed.resign();

        assertTrue(prevChair != fed.l2chair(), "onlyChair function did not revert properly");
        assertEq(fed.l2chair(), address(0), "onlyChair function did not revert properly");
    }

    function testL2_resign_fail_whenCalledByNonChair() public {
        vm.startPrank(user);

        vm.expectRevert(OnlyChair.selector);
        fed.resign();
    }

    function testL2_setMaxSlippageDolaToUsdc_fail_whenCalledByNonGov() public {
        vm.startPrank(user);

        vm.expectRevert(OnlyGovOrGuardian.selector);
        fed.setMaxSlippageDolaToUsdc(500);
    }

    function testL2_setMaxSlippageUsdcToDola_fail_whenCalledByNonGov() public {
        vm.startPrank(user);

        vm.expectRevert(OnlyGovOrGuardian.selector);
        fed.setMaxSlippageUsdcToDola(500);
    }

    function testL2_setMaxSlippageLiquidity_fail_whenCalledByNonGov() public {
        vm.startPrank(user);

        vm.expectRevert(OnlyGovOrGuardian.selector);
        fed.setMaxSlippageLiquidity(500);
    }

    function testL2_setPendingGov_fail_whenCalledByNonGov() public {
        vm.startPrank(user);

        vm.expectRevert(OnlyGov.selector);
        fed.setPendingGov(user);
    }

    function testL2_govChange() public {
        vm.startPrank(address(l2CrossDomainMessenger));
        mockXDomainMessageSender(gov);
        fed.setPendingGov(user);
        vm.stopPrank();

        vm.startPrank(address(l2CrossDomainMessenger));
        mockXDomainMessageSender(user);
        fed.claimGov();
        vm.stopPrank();

        assertEq(fed.gov(), user, "user failed to be set as gov");
        assertEq(fed.pendingGov(), address(0), "pendingGov failed to be set as 0 address");
    }
    
    function testL2_changeChair_fail_whenCalledByNonGov() public {
        vm.startPrank(user);

        vm.expectRevert(OnlyGov.selector);
        fed.changeChair(user);
    }

    function testL2_changeOptiFed_fail_whenCalledByNonGov() public {
        vm.startPrank(user);

        vm.expectRevert(OnlyGov.selector);
        fed.changeOptiFed(user);
    }

    //My loyal helpers

    function mockXDomainMessageSender(address sender) internal {
        vm.mockCall(
            0x4200000000000000000000000000000000000007,
            abi.encodeWithSelector(ICrossDomainMessenger.xDomainMessageSender.selector),
            abi.encode(sender)
        );
    }

    function getRoute(address from, address to) internal pure returns(IRouter.Route[] memory){
        address factory = address(0x25CbdDb98b35ab1FF77413456B31EC81A6B6B746); //Change to real factory
        IRouter.Route memory route = IRouter.Route(from, to, true, factory);
        IRouter.Route[] memory routeArray = new IRouter.Route[](1);
        routeArray[0] = route;
        return routeArray;
    }


    function gibDOLA(address _user, uint _amount) internal {
        bytes32 slot;
        assembly {
            mstore(0, _user)
            mstore(0x20, 0x0)
            slot := keccak256(0, 0x40)
        }

        vm.store(address(DOLA), slot, bytes32(_amount));
    }

    function gibUSDC(address _user, uint _amount) internal {
        bytes32 slot;
        assembly {
            mstore(0, _user)
            mstore(0x20, 0x0)
            slot := keccak256(0, 0x40)
        }

        vm.store(address(USDC), slot, bytes32(_amount));
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
