// SPDX-License-Identifier: MIT
import {IRouter} from "src/drome-fed/interfaces/IRouter.sol";
import {IERC20} from "src/drome-fed/interfaces/IERC20.sol";
import {IGauge} from "src/drome-fed/interfaces/IGauge.sol";
import {IL2ERC20Bridge} from "src/drome-fed/interfaces/IL2ERC20Bridge.sol";
import {ICrossDomainMessenger} from "src/drome-fed/interfaces/ICrossDomainMessenger.sol";
import {ICCTP} from "src/drome-fed/interfaces/ICCTP.sol";
import {L1SuperchainGovernable} from "src/L1Governable.sol";

pragma solidity ^0.8.13;

contract DromeFarmer is L1SuperchainGovernable{
    address public l2Chair;
    address public treasury;
    address public l1Treasury;

    uint public maxSlippageBpsDolaToStable;
    uint public maxSlippageBpsStableToDola;
    uint public maxSlippageBpsLiquidity;

    uint public constant pairedStable_MULTIPLIER= 1e12;
    uint public constant PRECISION = 10_000;
    uint32 public constant MAINNET_CCTP_DOMAIN = 0;

    IGauge public immutable dolaGauge;
    IERC20 public immutable LP_TOKEN;
    IERC20 public immutable dromeToken;
    address public immutable poolFactory;
    IRouter public immutable router;
    IERC20 public immutable DOLA;
    IERC20 public immutable pairedStable;
    IL2ERC20Bridge public bridge;
    address public fortKnox;
    ICCTP public immutable cctp;

    error MaxSlippageTooHigh();
    error NotEnoughTokens();
    error LiquiditySlippageTooHigh();
    error RestrictedToken();

    constructor(
        address _governor,
        address[] memory addresses,
        uint[] memory maxSlippageBps,
        uint maxSlippageBpsLiquidity_
        ) L1SuperchainGovernable(governor)
    {
        l2Chair = addresses[0];
        treasury = addresses[1];
        l1Treasury = addresses[2];
        bridge = IL2ERC20Bridge(addresses[3]);
        fortKnox = addresses[4];
        cctp = ICCTP(addresses[5]);

        maxSlippageBpsStableToDola = maxSlippageBps[1];
        maxSlippageBpsLiquidity = maxSlippageBpsLiquidity_;
    }

    /**
     * @notice Claims all VELO token rewards accrued by this contract & transfer all VELO owned by this contract to `treasury`
     */
    function claimAeroRewards() external {
        dolaGauge.getReward(address(this));

        dromeToken.transfer(treasury, dromeToken.balanceOf(address(this)));
    }


    /**
     * @notice Attempts to deposit `dolaAmount` of DOLA & `stableAmount` of pairedStable into Aerodrome DOLA/pairedStable stable pool. Then, deposits LP tokens into gauge.
     * @param dolaAmount Amount of DOLA to be added as liquidity in Aerodrome DOLA/pairedStable pool
     * @param stableAmount Amount of pairedStable to be added as liquidity in Aerodrome DOLA/pairedStable pool
     */
    function _deposit(uint dolaAmount, uint stableAmount) internal {
        uint lpTokenPrice = getLpTokenPrice();

        DOLA.approve(address(router), dolaAmount);
        pairedStable.approve(address(router), stableAmount);
        (uint dolaSpent, uint stableSpent, uint lpTokensReceived) = router.addLiquidity(address(DOLA), address(pairedStable), true, dolaAmount, stableAmount, 0, 0, address(this), block.timestamp);
        require(lpTokensReceived > 0, "No LP tokens received");

        uint totalDolaValue = stableSpent * pairedStable_MULTIPLIER + dolaSpent;

        uint expectedLpTokens = applySlippage(totalDolaValue * 1e18 / lpTokenPrice, maxSlippageBpsLiquidity);
        if (lpTokensReceived < expectedLpTokens) revert LiquiditySlippageTooHigh();
        
        uint lpBalance = LP_TOKEN.balanceOf(address(this));
        LP_TOKEN.approve(address(dolaGauge), lpBalance);
        dolaGauge.deposit(lpBalance);
    }

    /**
     * @notice Attempts to deposit `dolaAmount` of DOLA & `stableAmount` of pairedStable into Aerodrome DOLA/pairedStable stable pool. Then, deposits LP tokens into gauge.
     * @param dolaAmount Amount of DOLA to be added as liquidity in Aerodrome DOLA/pairedStable pool
     * @param stableAmount Amount of pairedStable to be added as liquidity in Aerodrome DOLA/pairedStable pool
     */
    function deposit(uint dolaAmount, uint stableAmount) external onlyRoleOrGovernor(l2Chair) {
        _deposit(dolaAmount, stableAmount);
    }

    /**
     * @notice Calls `deposit()` with entire DOLA & pairedStable token balance of this contract.
     */
    function depositAll() external onlyRoleOrGovernor(l2Chair) {
        _deposit(DOLA.balanceOf(address(this)), pairedStable.balanceOf(address(this)));
    }

    /**
     * @notice Withdraws `dolaAmount` worth of LP tokens from gauge. Then, redeems LP tokens for DOLA/pairedStable.
     * @dev If attempting to remove more DOLA than total LP tokens are worth, will remove all LP tokens.
     * @param dolaAmount Desired dola value to remove from DOLA/pairedStable pool. Will attempt to remove 50/50 while allowing for `maxSlippageBpsLiquidity` bps of variance.
     * @return Amount of pairedStable received from liquidity removal. Used by withdrawLiquidityAndSwap wrapper.
     */
    function _withdrawLiquidity(uint dolaAmount) internal returns (uint) {
        uint lpTokenPrice = getLpTokenPrice();
        uint liquidityToWithdraw = dolaAmount * 1e18 / lpTokenPrice;
        uint ownedLiquidity = dolaGauge.balanceOf(address(this));

        if (liquidityToWithdraw > ownedLiquidity) liquidityToWithdraw = ownedLiquidity;
        dolaGauge.withdraw(liquidityToWithdraw);
   
        LP_TOKEN.approve(address(router), liquidityToWithdraw);
        (uint amountpairedStable, uint amountDola) = router.removeLiquidity(address(pairedStable), address(DOLA), true, liquidityToWithdraw, 0, 0, address(this), block.timestamp);

        uint totalDolaReceived = amountDola + (amountpairedStable *pairedStable_MULTIPLIER);

        if (applySlippage(dolaAmount, maxSlippageBpsLiquidity) > totalDolaReceived) {
            revert LiquiditySlippageTooHigh();
        }

        return amountpairedStable;
    }

    /**
     * @notice Withdraws `dolaAmount` worth of LP tokens from gauge. Then, redeems LP tokens for DOLA/pairedStable.
     * @dev If attempting to remove more DOLA than total LP tokens are worth, will remove all LP tokens.
     * @param dolaAmount Desired dola value to remove from DOLA/pairedStable pool. Will attempt to remove 50/50 while allowing for `maxSlippageBpsLiquidity` bps of variance.
     * @return Amount of pairedStable received from liquidity removal. Used by withdrawLiquidityAndSwap wrapper.
     */
    function withdrawLiquidity(uint dolaAmount) external onlyRoleOrGovernor(l2Chair) returns (uint) {
        return _withdrawLiquidity(dolaAmount);
    }
 
    /**
     * @notice Withdraws `dolaAmount` worth of LP tokens from gauge. Then, redeems LP tokens for DOLA/pairedStable and swaps redeemed pairedStable to DOLA.
     * @param dolaAmount Desired dola value to remove from DOLA/pairedStable pool. Will attempt to remove 50/50 while allowing for `maxSlippageBpsLiquidity` bps of variance.
     */
    function withdrawLiquidityAndSwapToDOLA(uint dolaAmount) external onlyRoleOrGovernor(l2Chair) {
        uint stableAmount = _withdrawLiquidity(dolaAmount);

        swapStabletoDOLA(Amount);
    }

    /**
     * @notice Withdraws `dolaAmount` of DOLA & `stableAmount` of pairedStable to fortKnox on L1. Will take 7 days before withdraw is claimable on L1.
     * @param dolaAmount Amount of DOLA to withdraw and send to L1 FortKnox
     * @param stableAmount Amount of pairedStable to withdraw and send to L1 FortKnox
     */
    function withdrawToFortKnox(uint dolaAmount, uint stableAmount) external onlyRoleOrGovernor(l2Chair) {
        if (dolaAmount > DOLA.balanceOf(address(this))) revert NotEnoughTokens();
        if (stableAmount > pairedStable.balanceOf(address(this))) revert NotEnoughTokens();

        DOLA.transfer(dolaAmount, fortKnox);
        pairedStable.transfer(stableAmount. fortKnox);
    }

    /**
     * @notice Withdraws `amount` of `l2Token` to address `to` on L1. Will take 7 days before withdraw is claimable.
     * @param l2Token Address of the L2 token to be withdrawn
     * @param amount Amount of the L2 token to be withdrawn
     */
    function withdrawTokensToL1(address l2Token, uint amount) external onlyRoleOrGovernor(l2Chair) {
        if (amount > IERC20(l2Token).balanceOf(address(this))) revert NotEnoughTokens();
        if(l2Token == address(DOLA) || l2Token == address(pairedStable) || l2Token == address(pairedStable) ) revert RestrictedToken();

        IERC20(l2Token).approve(address(bridge), amount);
        bridge.withdrawTo(l2Token, l1Treasury, amount, 0, "");
    }

    /**
     * @notice Swap `stableAmount` of pairedStable to DOLA through aerodrome.
     * @param stableAmount Amount of pairedStable to swap to DOLA
     */
    function swapStableToDOLA(uint stableAmount) external onlyRoleOrGovernor(l2Chair) {
        uint minOut = applySlippage(stableAmount, maxSlippageBpsStableToDola) * pairedStable_MULTIPLIER;

        pairedStable.approve(address(router), stableAmount);
        router.swapExactTokensForTokens(stableAmount, minOut, getRoute(address(pairedStable), address(DOLA)), address(this), block.timestamp);
    }


    /**
     * @notice Calculates approximate price of 1 Aerodrome DOLA/pairedStable stable pool LP token
     */
    function getLpTokenPrice() internal view returns (uint) {
        (uint dolaAmountOneLP, uint stableAmountOneLP) = router.quoteRemoveLiquidity(address(DOLA), address(pairedStable), true, poolFactory, 0.001 ether);
        stableAmountOneLP *= pairedStable_MULTIPLIER;
        return (dolaAmountOneLP + stableAmountOneLP)*1000;
    }

    function applySlippage(uint amount, uint maxSlippage) internal pure returns(uint) {
        return amount * (PRECISION - maxSlippage) / PRECISION;
    }

    /**
     * @notice Generate route array for swap between two stablecoins
     * @param from Token to go from
     * @param to Token to go to
     * @return Returns a Route[] with a single element, representing the route
     */
    function getRoute(address from, address to) internal pure returns(IRouter.Route[] memory){
        IRouter.Route memory route = IRouter.Route(from, to, true, poolFactory);
        IRouter.Route[] memory routeArray = new IRouter.Route[](1);
        routeArray[0] = route;
        return routeArray;
    }

    /**
     * @notice Method for current l1Chair of the fed to resign
     */
    function resign() external onlyRoleOrGovernor(l2Chair) {
        l2Chair = address(0);
    }

    /**
     * @notice Governance only function for setting acceptable slippage when swapping DOLA -> pairedStable
     * @param newMaxSlippageBps The new maximum allowed loss for DOLA -> pairedStable swaps. 1 = 0.01%
     */
    function setMaxSlippageDolaToUsdc(uint newMaxSlippageBps) onlyGovernor external {
        if (newMaxSlippageBps > 10000) revert MaxSlippageTooHigh();
        maxSlippageBpsDolaToUsdc = newMaxSlippageBps;
    }

    /**
     * @notice Governance only function for setting acceptable slippage when adding or removing liquidty from DOLA/pairedStable pool
     * @param newMaxSlippageBps The new maximum allowed loss for adding/removing liquidity from DOLA/pairedStable pool. 1 = 0.01%
     */
    function setMaxSlippageLiquidity(uint newMaxSlippageBps) onlyGovernor external {
        if (newMaxSlippageBps > 10000) revert MaxSlippageTooHigh();
        maxSlippageBpsLiquidity = newMaxSlippageBps;
    }

    /**
     * @notice Method for gov to change treasury address, the address that receives all rewards
     * @param newTreasury_ L2 address to be set as treasury
     */
    function changeTreasury(address newTreasury_) external onlyGovernor {
        treasury = newTreasury_;
    }

    /**
     * @notice Method for gov to change the L2 l1Chair
     * @param newL2Chair_ L2 address to be set as l2Chair
     */
    function changeL2Chair(address newL2Chair_) external onlyGovernor {
        l2Chair = newL2Chair_;
    }

    /**
     * @notice Method for gov to change the L1 fortKnox address
     * @dev fortKnox is the L1 address that receives all bridged DOLA/pairedStable from both withdrawToL1FortKnox functions
     * @param newFortKnox_ L1 address to be set as fortKnox
     */
    function changeFortKnox(address newFortKnox_) external onlyGovernor {
        fortKnox = newFortKnox_;
    }
}
