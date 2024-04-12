// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import { IERC20 } from "../interfaces/IERC20.sol";
import { IDola } from "../interfaces/velo/IDola.sol";
import "../interfaces/velo/IL2CrossDomainMessenger.sol";
import { VeloFarmerV3, IRouter, IGauge} from "../velo-fed/VeloFarmerV3.sol";
import {OptiFed} from "../velo-fed/OptiFed.sol";
import {console} from "forge-std/console.sol";

contract VeloFarmerV3Test is Test {
    IRouter public router = IRouter(payable(0xa062aE8A9c5e11aaA026fc2670B0D65cCc8B2858));
    IGauge public dolaGauge = IGauge(0x853CAcEc83e4183eF78d6b64ccca3de365861CaF);
  
    IDola public DOLA = IDola(0x8aE125E8653821E851F12A49F7765db9a9ce7384);
    IERC20 public VELO = IERC20(0x9560e827aF36c94D2Ac33a39bCE1Fe78631088Db);
    IERC20 public USDC = IERC20(0x7F5c764cBc14f9669B88837ca1490cCa17c31607);
    IERC20 public nUSDC = IERC20(0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85);
    address public l2optiBridgeAddress = 0x4200000000000000000000000000000000000010;
    address public veloTokenAddr = 0x9560e827aF36c94D2Ac33a39bCE1Fe78631088Db;
    address public optiFedAddress = address(0xA);
    IL2CrossDomainMessenger public l2CrossDomainMessenger = IL2CrossDomainMessenger(0x4200000000000000000000000000000000000007);
    address public l1CrossDomainMessenger = 0x36BDE71C97B33Cc4729cf772aE268934f7AB70B2;
    address public treasury = 0xa283139017a2f5BAdE8d8e25412C600055D318F8;
    address public l1Treasury = 0x926dF14a23BE491164dCF93f4c468A50ef659D5B;
    address public cctpMainnet = 0xBd3fa81B58Ba92a82136038B25aDec7066af3155;
    address public cctpOpti = 0x2B4069517957735bE00ceE0fadAE88a26365528f;
    address public usdcNativeWhale = 0x8aF3827a41c26C7F32C81E93bb66e837e0210D5c; // 10 M nUSDC available at block 118031906
    uint nonce;

    //EOAs
    address user = address(69);
    address chair = address(0xB);
    address l2chair = address(0xC);
    address gov = address(0x607); // VeloMessengerV3
    address guardian = address(0xD);

    //Numbas
    uint dolaAmount = 1_000e18;
    uint usdcAmount = 1_000e6;

    uint maxSlippageBpsDolaToUsdc = 100;
    uint maxSlippageBpsUsdcToDola = 100;
    uint maxSlippageBpsUsdcNativeToDola = 100;
    uint maxSlippageBpsDolaToUsdcNative = 100;
    uint maxSlippageBpsUsdcToUsdcNative = 100;
    uint maxSlippageBpsUsdcNativeToUsdc = 100;
    uint maxSlippageLiquidity = 1000;

    //Feds
    VeloFarmerV3 fed;

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
        vm.createSelectFork(vm.rpcUrl("optimism"), 118031906);
        vm.label(veloTokenAddr, "VELO");
        vm.label(address(nUSDC), "nUSDC");
        vm.label(address(USDC), "USDC");
        vm.label(address(DOLA), "DOLA");

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

        vm.startPrank(chair);
        fed = new VeloFarmerV3(addresses, maxSlippageBps, maxSlippageLiquidity);
        vm.makePersistent(address(fed));

        vm.stopPrank();

        address voter = dolaGauge.voter();
        deal(address(VELO), address(voter), 1000 ether);
        vm.startPrank(voter);
        VELO.approve(address(dolaGauge), 1000 ether);
        dolaGauge.notifyRewardAmount(1000 ether);
        vm.stopPrank();
    }

    // NATIVE USDC
    // L2
    function testL2_swapDolaToUSDCNative() public {
        gibDOLA(address(fed), dolaAmount * 3);
        
        vm.prank(l2chair);
        fed.swapDOLAtoUSDCNative(dolaAmount * 3);

        assertGt(nUSDC.balanceOf(address(fed)), 0, "No USDC swapped");
    }

    function testL2_swapUsdcNativeToDola() public {
        gibUSDCNative(address(fed),usdcAmount);

        vm.prank(l2chair);
        fed.swapUSDCNativetoDOLA(usdcAmount);

        assertGt(DOLA.balanceOf(address(fed)), 0, "No DOLA swapped");
    }

    function testL2_deposit() public {
        gibDOLA(address(fed), dolaAmount * 3);
        gibUSDCNative(address(fed), usdcAmount * 3);

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

        assertEq(fed.LP_TOKEN_NATIVE().balanceOf(address(fed)),0);
        assertGt(VELO.balanceOf(address(treasury)), initialVelo, "No rewards claimed");
    }

    function testL2_depositAll() public {
        gibDOLA(address(fed), dolaAmount * 3);
        gibUSDCNative(address(fed), usdcAmount * 3);

        uint initialVelo = VELO.balanceOf(address(treasury));

        vm.startPrank(address(l2CrossDomainMessenger));
        mockXDomainMessageSender(gov);
        fed.setMaxSlippageLiquidity(5000);
        vm.stopPrank();

        vm.startPrank(l2chair);
        fed.depositAll();

        vm.roll(block.number + 100000);
        vm.warp(block.timestamp + (10_0000 * 60));
        fed.claimVeloRewards();

        assertEq(fed.LP_TOKEN_NATIVE().balanceOf(address(fed)),0);
        assertGt(VELO.balanceOf(address(treasury)), initialVelo, "No rewards claimed");
    }

    function testL2_withdrawNative() public {
        gibDOLA(address(fed), dolaAmount * 3);
        gibUSDCNative(address(fed), usdcAmount * 3);

        vm.startPrank(address(l2CrossDomainMessenger));
        mockXDomainMessageSender(gov);
        fed.setMaxSlippageLiquidity(1000);
        vm.stopPrank();

        vm.startPrank(l2chair);
        fed.depositAll();
        fed.withdrawLiquidity(dolaAmount/2);
    }

    function testL2_withdrawLiquidityAndSwap() public {
        gibDOLA(address(fed), dolaAmount * 3);
        gibUSDCNative(address(fed), usdcAmount * 3);

        vm.startPrank(address(l2CrossDomainMessenger));
        mockXDomainMessageSender(gov);
        fed.setMaxSlippageLiquidity(1000);
        vm.stopPrank();

        vm.startPrank(l2chair);
        fed.depositAll();

        uint usdcBefore = nUSDC.balanceOf(address(fed));
        fed.withdrawLiquidityAndSwapToDOLA(dolaAmount/2);
        assertGt(DOLA.balanceOf(address(fed)), 0, "No DOLA swapped");
        assertEq(nUSDC.balanceOf(address(fed)), usdcBefore, "Failed USDC Swap");
    }   

    function testL2_withdrawToL1Native() public {
        gibDOLA(address(fed), dolaAmount * 3);
        gibUSDCNative(address(fed), usdcAmount * 3);

        vm.startPrank(address(l2CrossDomainMessenger));
        mockXDomainMessageSender(gov);
        fed.setMaxSlippageLiquidity(1000);
        vm.stopPrank();

        vm.startPrank(l2chair);
        fed.depositAll();
        fed.withdrawLiquidity(dolaAmount/2);

        fed.withdrawToL1OptiFedNative(DOLA.balanceOf(address(fed)), nUSDC.balanceOf(address(fed))/2);
        fed.withdrawToL1OptiFedNative(nUSDC.balanceOf(address(fed)));
    }

    function testL2_withdrawTokensToL1() public {
        // USDT
        deal(address(0x94b008aA00579c1307B0EF2c499aD98a8ce58e58), address(fed), 1000e6);
        vm.startPrank(l2chair);
        fed.withdrawTokensToL1(address(0x94b008aA00579c1307B0EF2c499aD98a8ce58e58), 1000e6);
    }

    function testL2_withdrawTokensToL1_fails() public {
        gibDOLA(address(fed), dolaAmount);
        gibUSDCNative(address(fed), usdcAmount);
        gibUSDC(address(fed), usdcAmount);
        deal(address(VELO), address(fed), 1000 ether);

        vm.expectRevert(abi.encodeWithSelector(VeloFarmerV3.OnlyChair.selector));
        fed.withdrawTokensToL1(address(VELO), dolaAmount);

        vm.startPrank(l2chair);
        vm.expectRevert(abi.encodeWithSelector(VeloFarmerV3.RestrictedToken.selector));
        fed.withdrawTokensToL1(address(DOLA), dolaAmount);
        vm.expectRevert(abi.encodeWithSelector(VeloFarmerV3.RestrictedToken.selector));
        fed.withdrawTokensToL1(address(USDC), usdcAmount);
        vm.expectRevert(abi.encodeWithSelector(VeloFarmerV3.RestrictedToken.selector));
        fed.withdrawTokensToL1(address(nUSDC), usdcAmount);
    }

    function testL2_withdrawToL1OptiFedBridged() public {
        gibUSDC(address(fed), usdcAmount);
        vm.prank(l2chair);
        fed.withdrawToL1OptiFedBridged(usdcAmount);
    }

    function testL2_DepositAndClaimVeloRewards() public {
        gibDOLA(address(fed), dolaAmount * 3);
        gibUSDCNative(address(fed), usdcAmount * 3);
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
        gibUSDCNative(address(fed), usdcAmount * 3);

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
        gibUSDCNative(address(fed), usdcAmount * 3);

        uint initialVelo = VELO.balanceOf(address(treasury));

        vm.startPrank(address(l2CrossDomainMessenger));
        mockXDomainMessageSender(gov);
        fed.setMaxSlippageLiquidity(5000);
        vm.stopPrank();

        vm.startPrank(l2chair);
        fed.depositAll();
        vm.roll(block.number + 10000);
        vm.warp(block.timestamp + (10_000 * 60));
  
        fed.claimVeloRewards();

        assertGt(VELO.balanceOf(address(treasury)), initialVelo, "No rewards claimed");
    }

    function testL2_swap_USDCNativeToUSDC() public {
        gibUSDCNative(address(fed), usdcAmount * 3);

        assertEq(USDC.balanceOf(address(fed)),0, "Wrong balance");
        
        vm.prank(l2chair);
        fed.swapUSDCNativeToUSDC(usdcAmount * 3);

        assertGt(USDC.balanceOf(address(fed)),0, "Failed swap");
    }

    function testL2_swap_USDCToUSDCNative() public {
        gibUSDC(address(fed), usdcAmount * 3);

        assertEq(nUSDC.balanceOf(address(fed)),0, "Wrong balance");
    
        vm.prank(l2chair);
        fed.swapUSDCtoUSDCNative(uint(usdcAmount * 3));

        assertGt(nUSDC.balanceOf(address(fed)),0, "Failed swap");
    }

    function testL2_swap_USDCToDOLA() public {
        gibUSDC(address(fed), usdcAmount * 3);

        assertEq(DOLA.balanceOf(address(fed)),0, "Wrong balance");
    
        vm.prank(l2chair);
        fed.swapUSDCtoDOLA(uint(usdcAmount * 3));

        assertGt(DOLA.balanceOf(address(fed)),0, "Failed swap");
    }

    function testL2_swap_DOLAToUSDC() public {
        gibDOLA(address(fed), dolaAmount * 3);

        assertEq(USDC.balanceOf(address(fed)),0, "Wrong balance");
    
        vm.prank(l2chair);
        fed.swapDOLAtoUSDC(uint(dolaAmount * 3));

        assertGt(USDC.balanceOf(address(fed)),0, "Failed swap");
    }

    function testL2_Deposit_Succeeds_WhenSlippageLtMaxLiquiditySlippage() public {
        gibDOLA(address(fed), dolaAmount);
        gibUSDCNative(address(fed), usdcAmount * 2);

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

    function testL2_SwapDolaToUsdc_Fails_WhenSlippageGtMaxDolaToUsdcNativeSlippage() public {
        gibDOLA(address(fed), dolaAmount  * 3);

        vm.startPrank(address(l2CrossDomainMessenger));
        mockXDomainMessageSender(gov);
        fed.setMaxSlippageLiquidity(50);
        fed.setMaxSlippageDolaToUsdcNative(1);
        vm.stopPrank();

        vm.startPrank(l2chair);
        vm.expectRevert(abi.encodeWithSelector(IRouter.InsufficientOutputAmount.selector));
        fed.swapDOLAtoUSDCNative(dolaAmount * 3);
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

    function testL2_SwapUsdcToDola_Fails_WhenSlippageGtMaxUsdcNativeToDolaSlippage() public {
        gibUSDCNative(address(fed), usdcAmount*5);

        uint usdcToSwap = usdcAmount*5;
        gibUSDCNative(address(user), usdcToSwap);
        vm.startPrank(user);
        nUSDC.approve(address(router), type(uint).max);
        router.swapExactTokensForTokens(usdcToSwap, 0, getRoute(address(nUSDC), address(DOLA)), address(user), block.timestamp);
        vm.stopPrank();

        vm.startPrank(address(l2CrossDomainMessenger));
        mockXDomainMessageSender(gov);
        fed.setMaxSlippageUsdcNativeToDola(1);
        vm.stopPrank();

        vm.startPrank(l2chair);
        vm.expectRevert(abi.encodeWithSelector(IRouter.InsufficientOutputAmount.selector));
        fed.swapUSDCNativetoDOLA(usdcAmount*5);
    }


    function testL2_Withdraw_FromL1Chair(uint amountDola) public {
        amountDola = bound(amountDola, 10_000e18, 1_800_000e18);  // smaller amount since cctp has a burn limit per tx, currently at about 1.85M

        vm.startPrank(l2optiBridgeAddress);
        DOLA.mint(address(fed), amountDola);
        vm.stopPrank();
        gibUSDCNative(address(fed), amountDola / 1e12);

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
        uint prevUsdc = nUSDC.balanceOf(address(fed));

        vm.startPrank(address(l2CrossDomainMessenger));
        mockXDomainMessageSender(chair);
        fed.withdrawToL1OptiFedNative(DOLA.balanceOf(address(fed)), nUSDC.balanceOf(address(fed)));
        vm.stopPrank();

        assertGt(prevDola, DOLA.balanceOf(address(fed)), "Withdraw to L1 failed");
        assertGt(prevUsdc, nUSDC.balanceOf(address(fed)), "Withdraw to L1 failed");
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
        address factory = address(0xF1046053aa5682b4F9a81b5481394DA16BE5FF5a); //Actual factory
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

    function gibUSDCNative(address _user, uint _amount) internal {
        vm.prank(usdcNativeWhale);
        nUSDC.transfer(_user, _amount);
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
