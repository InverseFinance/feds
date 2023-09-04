// SPDX-License-Identifier: MIT
import "src/interfaces/IERC20.sol";
import "src/interfaces/velo/IGauge.sol";
import "src/interfaces/velo/IRouter.sol";
import "src/interfaces/opti/IL2ERC20Bridge.sol";
import "src/interfaces/opti/ICrossDomainMessenger.sol";

pragma solidity ^0.8.13;

contract VeloFarmerV2 {
    address public chair;
    address public l2chair;
    address public pendingGov;
    address public gov;
    address public treasury;
    address public guardian;
    uint public maxSlippageBpsDolaToUsdc;
    uint public maxSlippageBpsUsdcToDola;
    uint public maxSlippageBpsLiquidity;

    uint public constant DOLA_USDC_CONVERSION_MULTI= 1e12;
    uint public constant PRECISION = 10_000;

    IGauge public constant dolaGauge = IGauge(0xa1034Ed2C9eb616d6F7f318614316e64682e7923);
    IERC20 public constant LP_TOKEN = IERC20(0xB720FBC32d60BB6dcc955Be86b98D8fD3c4bA645);
    address public constant veloTokenAddr = 0x9560e827aF36c94D2Ac33a39bCE1Fe78631088Db;
    address public constant factory = 0xF1046053aa5682b4F9a81b5481394DA16BE5FF5a;
    ICrossDomainMessenger public constant ovmL2CrossDomainMessenger = ICrossDomainMessenger(0x4200000000000000000000000000000000000007);
    IRouter public constant router = IRouter(0xa062aE8A9c5e11aaA026fc2670B0D65cCc8B2858);
    IERC20 public constant DOLA = IERC20(0x8aE125E8653821E851F12A49F7765db9a9ce7384);
    IERC20 public constant USDC = IERC20(0x7F5c764cBc14f9669B88837ca1490cCa17c31607);
    IL2ERC20Bridge public bridge;
    address public optiFed;

    error OnlyChair();
    error OnlyGov();
    error OnlyPendingGov();
    error OnlyGovOrGuardian();
    error MaxSlippageTooHigh();
    error NotEnoughTokens();
    error LiquiditySlippageTooHigh();
    
    constructor(
        address gov_,
        address chair_,
        address l2chair_,
        address treasury_,
        address guardian_,
        address bridge_,
        address optiFed_,
        uint maxSlippageBpsDolaToUsdc_,
        uint maxSlippageBpsUsdcToDola_,
        uint maxSlippageBpsLiquidity_
        )
    {
        gov = gov_;
        chair = chair_;
        l2chair = l2chair_;
        treasury = treasury_;
        guardian = guardian_;
        bridge = IL2ERC20Bridge(bridge_);
        optiFed = optiFed_;
        maxSlippageBpsDolaToUsdc = maxSlippageBpsDolaToUsdc_;
        maxSlippageBpsUsdcToDola = maxSlippageBpsUsdcToDola_;
        maxSlippageBpsLiquidity = maxSlippageBpsLiquidity_;
    }

    modifier onlyGov() {
        if (msg.sender != address(ovmL2CrossDomainMessenger) ||
            ovmL2CrossDomainMessenger.xDomainMessageSender() != gov
        ) revert OnlyGov();
        _;
    }

    modifier onlyPendingGov() {
        if (msg.sender != address(ovmL2CrossDomainMessenger) ||
            ovmL2CrossDomainMessenger.xDomainMessageSender() != pendingGov
        ) revert OnlyPendingGov();
        _;
    }

    modifier onlyChair() {
        if ((msg.sender != address(ovmL2CrossDomainMessenger) ||
            ovmL2CrossDomainMessenger.xDomainMessageSender() != chair) &&
            msg.sender != l2chair
        ) revert OnlyChair();
        _;
    }

    modifier onlyGovOrGuardian() {
        if ((msg.sender != address(ovmL2CrossDomainMessenger) ||
            (ovmL2CrossDomainMessenger.xDomainMessageSender() != gov) &&
             ovmL2CrossDomainMessenger.xDomainMessageSender() != guardian)
        ) revert OnlyGovOrGuardian();
        _;
    }

    /**
     * @notice Claims all VELO token rewards accrued by this contract & transfer all VELO owned by this contract to `treasury`
     */
    function claimVeloRewards() external {
        dolaGauge.getReward(address(this));

        IERC20(veloTokenAddr).transfer(treasury, IERC20(veloTokenAddr).balanceOf(address(this)));
    }

    /**
     * @notice Attempts to deposit `dolaAmount` of DOLA & `usdcAmount` of USDC into Velodrome DOLA/USDC stable pool. Then, deposits LP tokens into gauge.
     * @param dolaAmount Amount of DOLA to be added as liquidity in Velodrome DOLA/USDC pool
     * @param usdcAmount Amount of USDC to be added as liquidity in Velodrome DOLA/USDC pool
     */
    function deposit(uint dolaAmount, uint usdcAmount) public onlyChair {
        uint lpTokenPrice = getLpTokenPrice();

        DOLA.approve(address(router), dolaAmount);
        USDC.approve(address(router), usdcAmount);
        (uint dolaSpent, uint usdcSpent, uint lpTokensReceived) = router.addLiquidity(address(DOLA), address(USDC), true, dolaAmount, usdcAmount, 0, 0, address(this), block.timestamp);
        require(lpTokensReceived > 0, "No LP tokens received");

        uint totalDolaValue = dolaSpent + (usdcSpent *DOLA_USDC_CONVERSION_MULTI);

        uint expectedLpTokens = totalDolaValue *1e18 / lpTokenPrice *(PRECISION - maxSlippageBpsLiquidity) / PRECISION;
        if (lpTokensReceived < expectedLpTokens) revert LiquiditySlippageTooHigh();
        
        LP_TOKEN.approve(address(dolaGauge), LP_TOKEN.balanceOf(address(this)));
        dolaGauge.deposit(LP_TOKEN.balanceOf(address(this)));
    }

    /**
     * @notice Calls `deposit()` with entire DOLA & USDC token balance of this contract.
     */
    function depositAll() external {
        deposit(DOLA.balanceOf(address(this)), USDC.balanceOf(address(this)));
    }

    /**
     * @notice Withdraws `dolaAmount` worth of LP tokens from gauge. Then, redeems LP tokens for DOLA/USDC.
     * @dev If attempting to remove more DOLA than total LP tokens are worth, will remove all LP tokens.
     * @param dolaAmount Desired dola value to remove from DOLA/USDC pool. Will attempt to remove 50/50 while allowing for `maxSlippageBpsLiquidity` bps of variance.
     * @return Amount of USDC received from liquidity removal. Used by withdrawLiquidityAndSwap wrapper.
     */
    function withdrawLiquidity(uint dolaAmount) public onlyChair returns (uint) {
        uint lpTokenPrice = getLpTokenPrice();
        uint liquidityToWithdraw = dolaAmount *1e18 / lpTokenPrice;
        uint ownedLiquidity = dolaGauge.balanceOf(address(this));

        if (liquidityToWithdraw > ownedLiquidity) liquidityToWithdraw = ownedLiquidity;
        dolaGauge.withdraw(liquidityToWithdraw);

        LP_TOKEN.approve(address(router), liquidityToWithdraw);
        (uint amountUSDC, uint amountDola) = router.removeLiquidity(address(USDC), address(DOLA), true, liquidityToWithdraw, 0, 0, address(this), block.timestamp);

        uint totalDolaReceived = amountDola + (amountUSDC *DOLA_USDC_CONVERSION_MULTI);

        if ((dolaAmount *(PRECISION - maxSlippageBpsLiquidity) / PRECISION) > totalDolaReceived) {
            revert LiquiditySlippageTooHigh();
        }

        return amountUSDC;
    }

    /**
     * @notice Withdraws `dolaAmount` worth of LP tokens from gauge. Then, redeems LP tokens for DOLA/USDC and swaps redeemed USDC to DOLA.
     * @param dolaAmount Desired dola value to remove from DOLA/USDC pool. Will attempt to remove 50/50 while allowing for `maxSlippageBpsLiquidity` bps of variance.
     */
    function withdrawLiquidityAndSwapToDOLA(uint dolaAmount) external {
        uint usdcAmount = withdrawLiquidity(dolaAmount);

        swapUSDCtoDOLA(usdcAmount);
    }

    /**
     * @notice Withdraws `dolaAmount` of DOLA to optiFed on L1. Will take 7 days before withdraw is claimable on L1.
     * @param dolaAmount Amount of DOLA to withdraw and send to L1 OptiFed
     */
    function withdrawToL1OptiFed(uint dolaAmount) external onlyChair {
        if (dolaAmount > DOLA.balanceOf(address(this))) revert NotEnoughTokens();

        bridge.withdrawTo(address(DOLA), optiFed, dolaAmount, 0, "");
    }

    /**
     * @notice Withdraws `dolaAmount` of DOLA & `usdcAmount` of USDC to optiFed on L1. Will take 7 days before withdraw is claimable on L1.
     * @param dolaAmount Amount of DOLA to withdraw and send to L1 OptiFed
     * @param usdcAmount Amount of USDC to withdraw and send to L1 OptiFed
     */
    function withdrawToL1OptiFed(uint dolaAmount, uint usdcAmount) external onlyChair {
        if (dolaAmount > DOLA.balanceOf(address(this))) revert NotEnoughTokens();
        if (usdcAmount > USDC.balanceOf(address(this))) revert NotEnoughTokens();

        bridge.withdrawTo(address(DOLA), optiFed, dolaAmount, 0, "");
        bridge.withdrawTo(address(USDC), optiFed, usdcAmount, 0, "");
    }

    /**
     * @notice Withdraws `amount` of `l2Token` to address `to` on L1. Will take 7 days before withdraw is claimable.
     * @param l2Token Address of the L2 token to be withdrawn
     * @param to L1 Address that tokens will be sent to
     * @param amount Amount of the L2 token to be withdrawn
     */
    function withdrawTokensToL1(address l2Token, address to, uint amount) external onlyChair {
        if (amount > IERC20(l2Token).balanceOf(address(this))) revert NotEnoughTokens();

        IERC20(l2Token).approve(address(bridge), amount);
        bridge.withdrawTo(address(l2Token), to, amount, 0, "");
    }

    /**
     * @notice Swap `usdcAmount` of USDC to DOLA through velodrome.
     * @param usdcAmount Amount of USDC to swap to DOLA
     */
    function swapUSDCtoDOLA(uint usdcAmount) public onlyChair {
        uint minOut = usdcAmount *(PRECISION - maxSlippageBpsUsdcToDola) / PRECISION *DOLA_USDC_CONVERSION_MULTI;

        USDC.approve(address(router), usdcAmount);
        router.swapExactTokensForTokens(usdcAmount, minOut, getRoute(address(USDC), address(DOLA)), address(this), block.timestamp);
    }

    /**
     * @notice Swap `dolaAmount` of DOLA to USDC through velodrome.
     * @param dolaAmount Amount of DOLA to swap to USDC
     */
    function swapDOLAtoUSDC(uint dolaAmount) public onlyChair { 
        uint minOut = dolaAmount *(PRECISION - maxSlippageBpsDolaToUsdc) / PRECISION / DOLA_USDC_CONVERSION_MULTI;
        
        DOLA.approve(address(router), dolaAmount);
        router.swapExactTokensForTokens(dolaAmount, minOut, getRoute(address(DOLA), address(USDC)), address(this), block.timestamp);
    }

    /**
     * @notice Calculates approximate price of 1 Velodrome DOLA/USDC stable pool LP token
     */
    function getLpTokenPrice() internal view returns (uint) {
        (uint dolaAmountOneLP, uint usdcAmountOneLP) = router.quoteRemoveLiquidity(address(DOLA), address(USDC), true, factory, 0.001 ether);
        usdcAmountOneLP *= DOLA_USDC_CONVERSION_MULTI;
        return (dolaAmountOneLP + usdcAmountOneLP)*1000;
    }

    /**
     * @notice Generate route array for swap between two stablecoins
     * @param from Token to go from
     * @param to Token to go to
     * @return Returns a Route[] with a single element, representing the route
     */
    function getRoute(address from, address to) internal pure returns(IRouter.Route[] memory){
        IRouter.Route memory route = IRouter.Route(from, to, true, factory);
        IRouter.Route[] memory routeArray = new IRouter.Route[](1);
        routeArray[0] = route;
        return routeArray;
    }

    /**
     * @notice Method for current chair of the fed to resign
     */
    function resign() external onlyChair {
        if (msg.sender == l2chair) {
            l2chair = address(0);
        } else {
            chair = address(0);
        }
    }

    /**
     * @notice Governance only function for setting acceptable slippage when swapping DOLA -> USDC
     * @param newMaxSlippageBps The new maximum allowed loss for DOLA -> USDC swaps. 1 = 0.01%
     */
    function setMaxSlippageDolaToUsdc(uint newMaxSlippageBps) onlyGovOrGuardian external {
        if (newMaxSlippageBps > 10000) revert MaxSlippageTooHigh();
        maxSlippageBpsDolaToUsdc = newMaxSlippageBps;
    }

    /**
     * @notice Governance only function for setting acceptable slippage when swapping USDC -> DOLA
     * @param newMaxSlippageBps The new maximum allowed loss for USDC -> DOLA swaps. 1 = 0.01%
     */
    function setMaxSlippageUsdcToDola(uint newMaxSlippageBps) onlyGovOrGuardian external {
        if (newMaxSlippageBps > 10000) revert MaxSlippageTooHigh();
        maxSlippageBpsUsdcToDola = newMaxSlippageBps;
    }

    /**
     * @notice Governance only function for setting acceptable slippage when adding or removing liquidty from DOLA/USDC pool
     * @param newMaxSlippageBps The new maximum allowed loss for adding/removing liquidity from DOLA/USDC pool. 1 = 0.01%
     */
    function setMaxSlippageLiquidity(uint newMaxSlippageBps) onlyGovOrGuardian external {
        if (newMaxSlippageBps > 10000) revert MaxSlippageTooHigh();
        maxSlippageBpsLiquidity = newMaxSlippageBps;
    }

    /**
     * @notice Method for `gov` to change `pendingGov` address
     * @dev `pendingGov` will have to call `claimGov` to complete `gov` transfer
     * @dev `pendingGov` should be an L1 address
     * @param newPendingGov_ L1 address to be set as `pendingGov`
     */
    function setPendingGov(address newPendingGov_) onlyGov external {
        pendingGov = newPendingGov_;
    }

    /**
     * @notice Method for `pendingGov` to claim `gov` role.
     */
    function claimGov() external onlyPendingGov {
        gov = pendingGov;
        pendingGov = address(0);
    }

    /**
     * @notice Method for gov to change treasury address, the address that receives all rewards
     * @param newTreasury_ L2 address to be set as treasury
     */
    function changeTreasury(address newTreasury_) external onlyGov {
        treasury = newTreasury_;
    }

    /**
     * @notice Method for gov to change the chair
     * @dev chair address should be set to the address of L1 VeloFarmerMessenger if it is being used
     * @param newChair_ L1 address to be set as chair
     */
    function changeChair(address newChair_) external onlyGov {
        chair = newChair_;
    }

    /**
     * @notice Method for gov to change the L2 chair
     * @param newL2Chair_ L2 address to be set as l2chair
     */
    function changeL2Chair(address newL2Chair_) external onlyGov {
        l2chair = newL2Chair_;
    }

    /**
     * @notice Method for gov to change the guardian
     * @param guardian_ L1 address to be set as guardian
     */
    function changeGuardian(address guardian_) external onlyGov {
        guardian = guardian_;
    }

    /**
     * @notice Method for gov to change the L1 optiFed address
     * @dev optiFed is the L1 address that receives all bridged DOLA/USDC from both withdrawToL1OptiFed functions
     * @param newOptiFed_ L1 address to be set as optiFed
     */
    function changeOptiFed(address newOptiFed_) external onlyGov {
        optiFed = newOptiFed_;
    }
}
