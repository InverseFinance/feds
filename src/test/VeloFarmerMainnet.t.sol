// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import { IERC20 } from "src/interfaces/IERC20.sol";
import { IDola } from "src/interfaces/IDola.sol";
import "src/interfaces/opti/IL2CrossDomainMessenger.sol";
import { VeloFarmer, IRouter, IGauge} from "src/velo-fed/VeloFarmer.sol";
import {OptiFed} from "src/velo-fed/OptiFed.sol";

contract VeloFarmerMainnetTest is Test {
    IRouter public router = IRouter(payable(0xa132DAB612dB5cB9fC9Ac426A0Cc215A3423F9c9));
    IGauge public dolaGauge = IGauge(0xAFD2c84b9d1cd50E7E18a55e419749A6c9055E1F);
    IDola public DOLA = IDola(0x8aE125E8653821E851F12A49F7765db9a9ce7384);
    IERC20 public VELO = IERC20(0x3c8B650257cFb5f272f799F5e2b4e65093a11a05);
    IERC20 public USDC = IERC20(0x7F5c764cBc14f9669B88837ca1490cCa17c31607);
    address public l2optiBridgeAddress = 0x4200000000000000000000000000000000000010;
    address public dolaUsdcPoolAddy = 0x6C5019D345Ec05004A7E7B0623A91a0D9B8D590d;
    address public veloTokenAddr = 0x3c8B650257cFb5f272f799F5e2b4e65093a11a05;
    address public optiFedAddress = address(0xA);
    IL2CrossDomainMessenger public l2CrossDomainMessenger = IL2CrossDomainMessenger(0x4200000000000000000000000000000000000007);
    address public l1CrossDomainMessenger = 0x36BDE71C97B33Cc4729cf772aE268934f7AB70B2;
    //address public l1CrossDomainMessenger = 0x25ace71c97B33Cc4729CF772ae268934F7ab5fA1;
    address public treasury = 0xa283139017a2f5BAdE8d8e25412C600055D318F8;

    uint nonce;

    //EOAs
    address user = address(69);
    address chair = address(0xB);
    address l2chair = address(0xC);
    address gov = address(0x607);
    address guardian = address(0xD);

    //Numbas
    uint dolaAmount = 100_000e18;
    uint usdcAmount = 100_000e6;

    uint maxSlippageBpsDolaToUsdc = 100;
    uint maxSlippageBpsUsdcToDola = 20;
    uint maxSlippageLiquidity = 20;

    //Feds
    VeloFarmer fed;

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
        fed = new VeloFarmer(gov, chair, l2chair, treasury, guardian, l2optiBridgeAddress, optiFedAddress, maxSlippageBpsDolaToUsdc, maxSlippageBpsUsdcToDola, maxSlippageLiquidity);
        vm.makePersistent(address(fed));

        vm.stopPrank();
    }

    // L2

    function testL2_DepositAndClaimVeloRewards() public {
        gibDOLA(address(fed), dolaAmount * 3);
        gibUSDC(address(fed), usdcAmount * 3);

        uint initialVelo = VELO.balanceOf(address(treasury));

        vm.startPrank(l1CrossDomainMessenger);
        relayGovMessage(abi.encodeWithSignature("setMaxSlippageLiquidity(uint256)", 5000));
        vm.stopPrank();

        vm.startPrank(l2chair);
        fed.deposit(dolaAmount / 2, usdcAmount / 2);

        vm.roll(block.number + 10000);
        vm.warp(block.timestamp + (10_000 * 60));
        fed.claimVeloRewards();

        assertGt(VELO.balanceOf(address(treasury)), initialVelo, "No rewards claimed");
    }

    function testL2_SwapAndClaimVeloRewards() public {
        gibDOLA(address(fed), dolaAmount * 3);
        gibUSDC(address(fed), usdcAmount * 3);

        uint initialVelo = VELO.balanceOf(address(treasury));

        vm.startPrank(l1CrossDomainMessenger);
        relayGovMessage(abi.encodeWithSignature("setMaxSlippageLiquidity(uint256)", 5000));
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

        vm.startPrank(l1CrossDomainMessenger);
        relayGovMessage(abi.encodeWithSignature("setMaxSlippageLiquidity(uint256)", 5000));
        vm.stopPrank();

        vm.startPrank(l2chair);
        fed.depositAll();
        vm.roll(block.number + 10000);
        vm.warp(block.timestamp + (10_000 * 60));
        address[] memory addr = new address[](1);
        addr[0] = 0x3c8B650257cFb5f272f799F5e2b4e65093a11a05;
        fed.claimRewards(addr);

        assertGt(VELO.balanceOf(address(treasury)), initialVelo, "No rewards claimed");
    }

    function testL2_Deposit_Succeeds_WhenSlippageLtMaxLiquiditySlippage() public {
        gibDOLA(address(fed), dolaAmount);
        gibUSDC(address(fed), usdcAmount * 2);

        uint initialPoolTokens = dolaGauge.balanceOf(address(fed));

        vm.startPrank(l2chair);

        fed.depositAll();

        assertGt(dolaGauge.balanceOf(address(fed)), initialPoolTokens, "depositAll failed");
    }

    function testL2_SwapDolaToUsdc_Fails_WhenSlippageGtMaxDolaToUsdcSlippage() public {
        gibDOLA(address(fed), dolaAmount * 3);

        vm.startPrank(l1CrossDomainMessenger);
        relayGovMessage(abi.encodeWithSignature("setMaxSlippageDolaToUsdc(uint256)", 100));
        vm.stopPrank();

        vm.startPrank(l2chair);
        vm.expectRevert("Router: INSUFFICIENT_OUTPUT_AMOUNT");
        fed.swapDOLAtoUSDC(dolaAmount);
    }

    function testL2_SwapUsdcToDola_Fails_WhenSlippageGtMaxUsdcToDolaSlippage() public {
        gibUSDC(address(fed), usdcAmount * 3);

        uint usdcToSwap = usdcAmount * 3;
        gibUSDC(address(user), usdcToSwap);
        vm.startPrank(user);
        USDC.approve(address(router), type(uint).max);
        router.swapExactTokensForTokensSimple(usdcToSwap, 0, address(USDC), address(DOLA), true, address(user), block.timestamp);
        vm.stopPrank();

        vm.startPrank(l1CrossDomainMessenger);
        relayGovMessage(abi.encodeWithSignature("setMaxSlippageUsdcToDola(uint256)", 100));
        vm.stopPrank();

        vm.startPrank(l2chair);
        vm.expectRevert("Router: INSUFFICIENT_OUTPUT_AMOUNT");
        fed.swapUSDCtoDOLA(usdcAmount);
    }

    function testL2_Withdraw() public {
        vm.startPrank(l2optiBridgeAddress);
        DOLA.mint(address(fed), dolaAmount);
        USDC.mint(address(fed), dolaAmount / 1e12);
        vm.stopPrank();

        vm.startPrank(l1CrossDomainMessenger);
        relayGovMessage(abi.encodeWithSignature("setMaxSlippageLiquidity(uint256)", 50));
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

        vm.startPrank(l1CrossDomainMessenger);
        relayGovMessage(abi.encodeWithSignature("setMaxSlippageLiquidity(uint256)", 4000));

        uint prevLiquidity = dolaGauge.balanceOf(address(fed));

        relayChairMessage(abi.encodeWithSignature("depositAll()"));

        assertLt(prevLiquidity, dolaGauge.balanceOf(address(fed)), "depositAll failed");
        prevLiquidity = dolaGauge.balanceOf(address(fed));

        relayChairMessage(abi.encodeWithSignature("withdrawLiquidity(uint256)", amountDola));

        assertGt(prevLiquidity, dolaGauge.balanceOf(address(fed)), "withdrawLiquidity failed");

        uint prevDola = DOLA.balanceOf(address(fed));
        uint prevUsdc = USDC.balanceOf(address(fed));

        relayChairMessage(abi.encodeWithSignature("withdrawToL1OptiFed(uint256,uint256)", DOLA.balanceOf(address(fed)), USDC.balanceOf(address(fed))));

        assertGt(prevDola, DOLA.balanceOf(address(fed)), "Withdraw to L1 failed");
        assertGt(prevUsdc, USDC.balanceOf(address(fed)), "Withdraw to L1 failed");
    }

    function testL2_WithdrawAndSwap() public {
        vm.startPrank(l2optiBridgeAddress);
        DOLA.mint(address(fed), dolaAmount);
        gibUSDC(address(fed), usdcAmount);
        vm.stopPrank();

        vm.startPrank(l2chair);
        fed.depositAll();

        uint dolaBal = DOLA.balanceOf(address(fed));
        uint usdcBal = USDC.balanceOf(address(fed)) * fed.DOLA_USDC_CONVERSION_MULTI();
        uint withdrawAmount = dolaAmount - dolaBal - usdcBal;

        fed.withdrawLiquidityAndSwapToDOLA(withdrawAmount);
    }

    function testL2_onlyChair_fail_whenCalledByBridge_NonChairSender() public {
        vm.startPrank(l1CrossDomainMessenger);

        address prevChair = fed.chair();

        bytes memory message = abi.encodeWithSignature("resign()");
        l2CrossDomainMessenger.relayMessage(address(fed), address(0x999), message, nonce++);

        assertEq(prevChair, fed.chair(), "onlyChair function did not revert properly");
        assertTrue(fed.chair() != address(0), "onlyChair function did not revert properly");
    }

    function testL2_resign_fromChair() public {
        vm.startPrank(l1CrossDomainMessenger);

        address prevChair = fed.chair();

        bytes memory message = abi.encodeWithSignature("resign()");
        l2CrossDomainMessenger.relayMessage(address(fed), address(chair), message, nonce++);

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
        vm.startPrank(l1CrossDomainMessenger);
        relayGovMessage(abi.encodeWithSignature("setPendingGov(address)", user));

        relayUserMessage(abi.encodeWithSignature("claimGov()"));

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
