// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "src/interfaces/IERC20.sol";
import {IDola} from "src/interfaces/velo/IDola.sol";
import {BaseFedCCTP} from "src/velo-fed/BaseFedCCTP.sol";

import {MockExchangeProxy} from "test/mocks/MockExchangeProxy.sol";
import {Test} from "forge-std/Test.sol";

interface IFedCCTP {
    function expansion(uint _amount) external;
    function expansionAndSwap(
        uint _amount,
        uint _amountToSwap,
        bool _cctp,
        bytes memory _swapData
    ) external;
    function swapDOLAtoUSDC(uint _amount, bytes memory _swapData) external;
    function swapUSDCtoDOLA(uint _amount, bytes memory _swapData) external;
    function changeChair(address _chair) external;
    function setPendingGov(address _pendingGov) external;
    function claimGov() external;
    function setExchangeProxy(address _exchangeProxy) external;
    function setMaxSlippageDolaToUsdc(uint _maxSlippageDolaToUsdc) external;
    function setMaxSlippageUsdcToDola(uint _maxSlippageUsdcToDola) external;
    function resign() external;
    function contractAll() external;
    function contraction(uint _amount) external;
    function gov() external view returns (address);
    function pendingGov() external view returns (address);
    function exchangeProxy() external view returns (address);
    function maxSlippageDolaToUsdc() external view returns (uint);
    function maxSlippageUsdcToDola() external view returns (uint);
    function chair() external view returns (address);
}
abstract contract FedCCTPProxyMainnetTest is Test {
    //Tokens
    IDola public DOLA = IDola(0x865377367054516e17014CcdED1e7d814EDC9ce4);
    IERC20 public USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    address l1BridgeAddr; // = 0x3154Cf16ccdb4C6d922629664174b904d80F2C35;
    MockExchangeProxy exchangeProxy;

    //EOAs
    address user = address(0x69);
    address chair = address(0xB);
    address gov = 0x926dF14a23BE491164dCF93f4c468A50ef659D5B;

    //Numbas
    uint dolaAmount = 1_000_00e18;
    uint usdcAmount = 1_000_00e6;

    //Feds
    IFedCCTP fed;

    function initialize() public {
        gibUSDC(address(exchangeProxy), 1_000_000e6);
        vm.startPrank(gov);
        DOLA.addMinter(address(fed));
        DOLA.mint(address(exchangeProxy), 1_000_000e18);
        vm.stopPrank();
    }
    function testL1_BaseFedExpansion() public {
        vm.startPrank(chair);

        uint prevBal = DOLA.balanceOf(l1BridgeAddr);

        fed.expansion(dolaAmount);

        assertEq(prevBal + dolaAmount, DOLA.balanceOf(l1BridgeAddr));
    }

    function testL1_BaseFedExpansionAndSwap_Half_CCTP() public {
        vm.startPrank(chair);

        uint prevDolaBal = DOLA.balanceOf(l1BridgeAddr);
        bytes memory swapData = abi.encodeWithSelector(
            MockExchangeProxy.swapDolaIn.selector,
            address(USDC),
            dolaAmount / 2,
            dolaAmount / 2 / 1e12
        );
        fed.expansionAndSwap(dolaAmount, dolaAmount / 2, true, swapData);

        assertEq(
            prevDolaBal + dolaAmount / 2,
            DOLA.balanceOf(l1BridgeAddr),
            "Bridge didn't receive correct amount of DOLA"
        );
        assertEq(USDC.balanceOf(address(fed)), 0, "CCTP Burn Failed");
    }

    function testL1_BaseFedExpansionAndSwap_Half_NO_CCTP() public {
        vm.startPrank(chair);

        uint prevDolaBal = DOLA.balanceOf(l1BridgeAddr);
        uint prevUsdcBal = USDC.balanceOf(l1BridgeAddr);
        bytes memory swapData = abi.encodeWithSelector(
            MockExchangeProxy.swapDolaIn.selector,
            address(USDC),
            dolaAmount / 2,
            dolaAmount / 2 / 1e12
        );
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

    function testL1_BaseFedExpansionAndSwap(uint8 multi) public {
        uint256 multiplier = bound(uint(multi), 1, 10);
        uint dolaToSwap = (dolaAmount * multiplier) / 10;
        uint dolaToBridge = dolaAmount - dolaToSwap;

        vm.startPrank(chair);

        uint prevDolaBal = DOLA.balanceOf(l1BridgeAddr);
        uint prevUsdcBal = USDC.balanceOf(l1BridgeAddr);
        bytes memory swapData = abi.encodeWithSelector(
            MockExchangeProxy.swapDolaIn.selector,
            address(USDC),
            dolaToSwap,
            dolaToSwap / 1e12
        );
        fed.expansionAndSwap(dolaAmount, dolaToSwap, false, swapData);

        uint estimatedUsdcAmount = dolaToSwap / 1e12;

        assertEq(
            prevDolaBal + dolaToBridge,
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

    function testL1_BaseFedExpansionAndSwap_CCTP(uint8 multi) public {
        uint256 multiplier = bound(uint(multi), 1, 10);
        uint dolaToSwap = (dolaAmount * multiplier) / 10;
        uint dolaToBridge = dolaAmount - dolaToSwap;

        vm.startPrank(chair);

        uint prevDolaBal = DOLA.balanceOf(l1BridgeAddr);
        bytes memory swapData = abi.encodeWithSelector(
            MockExchangeProxy.swapDolaIn.selector,
            address(USDC),
            dolaToSwap,
            dolaToSwap / 1e12
        );
        fed.expansionAndSwap(dolaAmount, dolaToSwap, true, swapData);

        assertEq(
            prevDolaBal + dolaToBridge,
            DOLA.balanceOf(l1BridgeAddr),
            "Bridge didn't receive correct amount of DOLA"
        );
        assertEq(USDC.balanceOf(address(fed)), 0, "CCTP Burn Failed");
    }

    function testL1_BaseFedExpansionAndSwap_Fails_IfSlippageRestraintUnmet()
        public
    {
        bytes memory swapData = abi.encodeWithSelector(
            MockExchangeProxy.swapDolaIn.selector,
            address(USDC),
            dolaAmount / 2,
            ((dolaAmount / 2) * 98) / 100 / 1e12
        );
        vm.startPrank(chair);

        vm.expectRevert(BaseFedCCTP.SlippageTooHigh.selector);
        fed.expansionAndSwap(dolaAmount, dolaAmount / 2, true, swapData);
    }

    function testL1_BaseFedSwapDOLAtoUSDC() public {
        vm.startPrank(chair);

        uint prevDolaBal = DOLA.balanceOf(address(fed));
        uint prevUsdcBal = USDC.balanceOf(address(fed));

        gibDOLA(address(fed), dolaAmount);
        bytes memory swapData = abi.encodeWithSelector(
            MockExchangeProxy.swapDolaIn.selector,
            address(USDC),
            dolaAmount,
            dolaAmount / 1e12
        );
        fed.swapDOLAtoUSDC(dolaAmount, swapData);

        uint estimatedUsdcAmount = dolaAmount / 1e12;

        assertEq(
            prevDolaBal,
            DOLA.balanceOf(address(fed)),
            "DOLA didn't leave fed"
        );
        assertGt(
            prevUsdcBal + (estimatedUsdcAmount * 101) / 100,
            USDC.balanceOf(address(fed)),
            "Fed didn't receive correct amount of USDC"
        );
        assertLt(
            prevUsdcBal + estimatedUsdcAmount,
            (USDC.balanceOf(address(fed)) * 101) / 100,
            "Fed didn't receive correct amount of USDC"
        );
    }

    function testL1_BaseFedSwapUSDCtoDOLA_Fails_IfSlippageRestraintUnmet()
        public
    {
        bytes memory swapData = abi.encodeWithSelector(
            MockExchangeProxy.swapDolaOut.selector,
            address(USDC),
            usdcAmount,
            ((usdcAmount * 1e12) * 98) / 100
        );
        vm.startPrank(chair);
        gibUSDC(address(fed), usdcAmount);

        vm.expectRevert(BaseFedCCTP.SlippageTooHigh.selector);
        fed.swapUSDCtoDOLA(usdcAmount, swapData);
    }

    function testL1_BaseFedSwapDOLAtoUSDC_Fails_IfSlippageRestraintUnmet()
        public
    {
        bytes memory swapData = abi.encodeWithSelector(
            MockExchangeProxy.swapDolaIn.selector,
            address(USDC),
            dolaAmount,
            (dolaAmount * 98) / 100 / 1e12
        );

        vm.startPrank(chair);
        gibDOLA(address(fed), dolaAmount);
        vm.expectRevert(BaseFedCCTP.SlippageTooHigh.selector);
        fed.swapDOLAtoUSDC(dolaAmount, swapData);
    }

    function testL1_BaseFedSwapUSDCtoDOLA() public {
        vm.startPrank(chair);

        uint prevDolaBal = DOLA.balanceOf(address(fed));
        uint prevUsdcBal = USDC.balanceOf(address(fed));

        bytes memory swapData = abi.encodeWithSelector(
            MockExchangeProxy.swapDolaOut.selector,
            address(USDC),
            usdcAmount,
            usdcAmount * 1e12
        );

        gibUSDC(address(fed), usdcAmount);

        fed.swapUSDCtoDOLA(usdcAmount, swapData);

        uint estimatedDolaAmount = usdcAmount * 1e12;

        assertEq(
            prevUsdcBal,
            USDC.balanceOf(address(fed)),
            "USDC didn't leave fed"
        );
        assertGt(
            prevDolaBal + (estimatedDolaAmount * 101) / 100,
            DOLA.balanceOf(address(fed)),
            "Fed didn't receive correct amount of DOLA"
        );
        assertLt(
            prevDolaBal + estimatedDolaAmount,
            (DOLA.balanceOf(address(fed)) * 101) / 100,
            "Fed didn't receive correct amount of DOLA"
        );
    }

    function testL1_changeChair_fail_whenCalledByNonGov() public {
        vm.startPrank(user);

        vm.expectRevert(BaseFedCCTP.OnlyGov.selector);
        fed.changeChair(user);
    }

    function testL1_setPendingGov_fail_whenCalledByNonGov() public {
        vm.startPrank(user);

        vm.expectRevert(BaseFedCCTP.OnlyGov.selector);
        fed.setPendingGov(user);
    }

    function testL1_govChange() public {
        vm.startPrank(gov);

        fed.setPendingGov(user);
        vm.stopPrank();

        vm.startPrank(user);

        fed.claimGov();

        assertEq(fed.gov(), user, "user failed to be set as gov");
        assertEq(
            fed.pendingGov(),
            address(0),
            "pendingGov failed to be set as 0 address"
        );
    }

    function testL1_setExchangeProxy() public {
        address newExchangeProxy = address(0x70);
        assertEq(address(exchangeProxy), fed.exchangeProxy());
        vm.prank(gov);
        fed.setExchangeProxy(address(newExchangeProxy));
        assertEq(newExchangeProxy, fed.exchangeProxy());
    }

    function testL1_setExchangeProxy_fail_whenCalledByNonGov() public {
        vm.startPrank(user);

        vm.expectRevert(BaseFedCCTP.OnlyGov.selector);
        fed.setExchangeProxy(address(0x70));
    }

    function testL1_setMaxSlippageDolaToUsdc_fail_whenCalledByNonGov() public {
        vm.startPrank(user);

        vm.expectRevert(BaseFedCCTP.OnlyGov.selector);
        fed.setMaxSlippageDolaToUsdc(500);
    }

    function testL1_setMaxSlippageUsdcToDola_fail_whenCalledByNonGov() public {
        vm.startPrank(user);

        vm.expectRevert(BaseFedCCTP.OnlyGov.selector);
        fed.setMaxSlippageUsdcToDola(500);
    }

    function testL1_resign_fail_whenCalledByNonChair() public {
        vm.startPrank(user);

        vm.expectRevert(BaseFedCCTP.OnlyChair.selector);
        fed.resign();
    }

    function testL1_swapDOLAtoUSDC_fail_whenCalledByNonChair() public {
        vm.startPrank(user);
        bytes memory swapData;
        vm.expectRevert(BaseFedCCTP.OnlyChair.selector);
        fed.swapDOLAtoUSDC(1e18, swapData);
    }

    function testL1_swapUSDCtoDOLA_fail_whenCalledByNonChair() public {
        vm.startPrank(user);
        bytes memory swapData;
        vm.expectRevert(BaseFedCCTP.OnlyChair.selector);
        fed.swapUSDCtoDOLA(1e6, swapData);
    }

    function testL1_contractAll_fail_whenCalledByNonChair() public {
        vm.startPrank(user);

        vm.expectRevert(BaseFedCCTP.OnlyChair.selector);
        fed.contractAll();
    }

    function testL1_contract_fail_whenCalledByNonChair() public {
        vm.startPrank(user);

        vm.expectRevert(BaseFedCCTP.OnlyChair.selector);
        fed.contraction(1e18);
    }

    // My loyal helpers

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
