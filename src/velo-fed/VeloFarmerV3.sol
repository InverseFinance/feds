// SPDX-License-Identifier: MIT
import "src/velo-fed/IRouter.sol";

pragma solidity ^0.8.13;

// OpenZeppelin Contracts (last updated v4.5.0) (token/ERC20/IERC20.sol)

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */

interface IERC20 {
    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     *another (`to`).
     *
     *Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     *a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the decimal points used by the token.
     */
    function decimals() external view returns (uint8);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's account to `to`.
     *
     *Returns a boolean value indicating whether the operation succeeded.
     *
     *Emits a {Transfer} event.
     */
    function transfer(address to, uint256 amount) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     *allowed to spend on behalf of `owner` through {transferFrom}. This is
     *zero by default.
     *
     *This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     *
     *Returns a boolean value indicating whether the operation succeeded.
     *
     *IMPORTANT: Beware that changing an allowance with this method brings the risk
     *that someone may use both the old and the new allowance by unfortunate
     *transaction ordering. One possible solution to mitigate this race
     *condition is to first reduce the spender's allowance to 0 and set the
     *desired value afterwards:
     *https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     *Emits an {Approval} event.
     */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @dev Moves `amount` tokens from `from` to `to` using the
     *allowance mechanism. `amount` is then deducted from the caller's
     *allowance.
     *
     *Returns a boolean value indicating whether the operation succeeded.
     *
     *Emits a {Transfer} event.
     */
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);
    
    /**
     * @dev Burns `amount` of token, shringking total supply
     */
    function burn(uint amount) external;

    /**
     * @dev Mints `amount` of token to address `to` increasing total supply
     */
    function mint(address to, uint amount) external;

    //For testing
    function addMinter(address minter_) external;
}

interface IGauge {
    function deposit(uint amount) external;
    function getReward(address account) external;
    function notifyRewardAmount(uint amount) external;
    function withdraw(uint shares) external;
    function balanceOf(address account) external returns (uint);
    function voter() external view returns(address);
}

/**
 * @title IL2ERC20Bridge
 */
interface IL2ERC20Bridge {
    /**********
     *Events *
     **********/

    event WithdrawalInitiated(
        address indexed _l1Token,
        address indexed _l2Token,
        address indexed _from,
        address _to,
        uint256 _amount,
        bytes _data
    );

    event DepositFinalized(
        address indexed _l1Token,
        address indexed _l2Token,
        address indexed _from,
        address _to,
        uint256 _amount,
        bytes _data
    );

    event DepositFailed(
        address indexed _l1Token,
        address indexed _l2Token,
        address indexed _from,
        address _to,
        uint256 _amount,
        bytes _data
    );

    /********************
     *Public Functions *
     ********************/

    /**
     * @dev get the address of the corresponding L1 bridge contract.
     * @return Address of the corresponding L1 bridge contract.
      */
    function l1TokenBridge() external returns (address);

    /**
     * @dev initiate a withdraw of some tokens to the caller's account on L1
     * @param _l2Token Address of L2 token where withdrawal was initiated.
     * @param _amount Amount of the token to withdraw.
     *param _l1Gas Unused, but included for potential forward compatibility considerations.
     * @param _data Optional data to forward to L1. This data is provided
     *solely as a convenience for external contracts. Aside from enforcing a maximum
     *length, these contracts provide no guarantees about its content.
      */
    function withdraw(
        address _l2Token,
        uint256 _amount,
        uint32 _l1Gas,
        bytes calldata _data
    ) external;

    /**
     * @dev initiate a withdraw of some token to a recipient's account on L1.
     * @param _l2Token Address of L2 token where withdrawal is initiated.
     * @param _to L1 adress to credit the withdrawal to.
     * @param _amount Amount of the token to withdraw.
     *param _l1Gas Unused, but included for potential forward compatibility considerations.
     * @param _data Optional data to forward to L1. This data is provided
     *solely as a convenience for external contracts. Aside from enforcing a maximum
     *length, these contracts provide no guarantees about its content.
      */
    function withdrawTo(
        address _l2Token,
        address _to,
        uint256 _amount,
        uint32 _l1Gas,
        bytes calldata _data
    ) external;

    /*************************
     *Cross-chain Functions *
     *************************/

    /**
     * @dev Complete a deposit from L1 to L2, and credits funds to the recipient's balance of this
     *L2 token. This call will fail if it did not originate from a corresponding deposit in
     *L1StandardTokenBridge.
     * @param _l1Token Address for the l1 token this is called with
     * @param _l2Token Address for the l2 token this is called with
     * @param _from Account to pull the deposit from on L2.
     * @param _to Address to receive the withdrawal at
     * @param _amount Amount of the token to withdraw
     * @param _data Data provider by the sender on L1. This data is provided
     *solely as a convenience for external contracts. Aside from enforcing a maximum
     *length, these contracts provide no guarantees about its content.
      */
    function finalizeDeposit(
        address _l1Token,
        address _l2Token,
        address _from,
        address _to,
        uint256 _amount,
        bytes calldata _data
    ) external;
}

/**
 * @title ICrossDomainMessenger
 */
interface ICrossDomainMessenger {
    /**********
     *Events *
     **********/

    event SentMessage(
        address indexed target,
        address sender,
        bytes message,
        uint256 messageNonce,
        uint256 gasLimit
    );
    event RelayedMessage(bytes32 indexed msgHash);
    event FailedRelayedMessage(bytes32 indexed msgHash);

    /*************
     *Variables *
     *************/

    function xDomainMessageSender() external view returns (address);

    /********************
     *Public Functions *
     ********************/

    /**
      *Sends a cross domain message to the target messenger.
      * @param _target Target contract address.
      * @param _message Message to send to the target.
      * @param _gasLimit Gas limit for the provided message.
      */
    function sendMessage(
        address _target,
        bytes calldata _message,
        uint32 _gasLimit
    ) external;
}

interface ICCTP {
      /**
     * @notice Deposits and burns tokens from sender to be minted on destination domain.
     * Emits a `DepositForBurn` event.
     * @dev reverts if:
     * - given burnToken is not supported
     * - given destinationDomain has no TokenMessenger registered
     * - transferFrom() reverts. For example, if sender's burnToken balance or approved allowance
     * to this contract is less than `amount`.
     * - burn() reverts. For example, if `amount` is 0.
     * - MessageTransmitter returns false or reverts.
     * @param amount amount of tokens to burn
     * @param destinationDomain destination domain
     * @param mintRecipient address of mint recipient on destination domain
     * @param burnToken address of contract to burn deposited tokens, on local domain
     * @return _nonce unique nonce reserved by message
     */
    function depositForBurn(
        uint256 amount,
        uint32 destinationDomain,
        bytes32 mintRecipient,
        address burnToken
    ) external returns (uint64 _nonce);
}


contract VeloFarmerV3 {
    address public l1Chair;
    address public l2Chair;
    address public pendingGov;
    address public gov;
    address public treasury;
    address public guardian;
    address public l1Treasury;

    uint public maxSlippageBpsDolaToUsdc;
    uint public maxSlippageBpsUsdcToDola;
    uint public maxSlippageBpsUsdcNativeToDola;
    uint public maxSlippageBpsDolaToUsdcNative;
    uint public maxSlippageBpsUsdcToUsdcNative;
    uint public maxSlippageBpsUsdcNativeToUsdc;

    uint public maxSlippageBpsLiquidity;

    uint public constant DOLA_USDC_CONVERSION_MULTI= 1e12;
    uint public constant PRECISION = 10_000;

    IGauge public constant dolaGauge = IGauge(0x853CAcEc83e4183eF78d6b64ccca3de365861CaF); 
    IERC20 public constant LP_TOKEN = IERC20(0xA56a25Dee5B3199A9198Bbd48715EE3D0ed98378);
    address public constant veloTokenAddr = 0x9560e827aF36c94D2Ac33a39bCE1Fe78631088Db;
    address public constant factory = 0xF1046053aa5682b4F9a81b5481394DA16BE5FF5a;
    ICrossDomainMessenger public constant ovmL2CrossDomainMessenger = ICrossDomainMessenger(0x4200000000000000000000000000000000000007);
    IRouter public constant router = IRouter(0xa062aE8A9c5e11aaA026fc2670B0D65cCc8B2858);
    IERC20 public constant DOLA = IERC20(0x8aE125E8653821E851F12A49F7765db9a9ce7384);
    IERC20 public constant USDC = IERC20(0x7F5c764cBc14f9669B88837ca1490cCa17c31607);
    IERC20 public constant nUSDC = IERC20(0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85); // native USDC
    uint32 public constant MAINNET_CCTP_DOMAIN = 0;
    IL2ERC20Bridge public bridge;
    address public optiFed;
    ICCTP public immutable cctp;

    error OnlyRole(address l1, address l2);
    error OnlyGovOrGuardian();
    error MaxSlippageTooHigh();
    error NotEnoughTokens();
    error LiquiditySlippageTooHigh();
    error RestrictedToken();

    constructor(
        address[] memory addresses,
        uint[] memory maxSlippageBps,
        uint maxSlippageBpsLiquidity_
        )
    {
        gov = addresses[0];
        l1Chair = addresses[1];
        l2Chair = addresses[2];
        treasury = addresses[3];
        l1Treasury = addresses[4];
        guardian = addresses[5];
        bridge = IL2ERC20Bridge(addresses[6]);
        optiFed = addresses[7];
        cctp = ICCTP(addresses[8]);

        maxSlippageBpsDolaToUsdc = maxSlippageBps[0];
        maxSlippageBpsUsdcToDola = maxSlippageBps[1];
        maxSlippageBpsUsdcNativeToDola = maxSlippageBps[2];
        maxSlippageBpsDolaToUsdcNative = maxSlippageBps[3];
        maxSlippageBpsUsdcToUsdcNative = maxSlippageBps[4];
        maxSlippageBpsUsdcNativeToUsdc = maxSlippageBps[5];
        maxSlippageBpsLiquidity = maxSlippageBpsLiquidity_;
    }

    modifier onlyRole(address l1Role, address l2Role) {
        if (msg.sender == address(ovmL2CrossDomainMessenger)) {
            if (ovmL2CrossDomainMessenger.xDomainMessageSender() != l1Role) revert OnlyRole(l1Role, l2Role);
        } else if (msg.sender != l2Role){
            revert OnlyRole(l1Role, l2Role);
        }
        _;
    }

    modifier onlyGovOrGuardian() {
        if (msg.sender != address(ovmL2CrossDomainMessenger)) {
            revert OnlyGovOrGuardian();
        } else {
            address messageSender = ovmL2CrossDomainMessenger.xDomainMessageSender();
            if (messageSender != guardian && messageSender != gov) revert OnlyGovOrGuardian();
        }
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
    function _deposit(uint dolaAmount, uint usdcAmount) internal {
        uint lpTokenPrice = getLpTokenPrice();

        DOLA.approve(address(router), dolaAmount);
        nUSDC.approve(address(router), usdcAmount);
        (uint dolaSpent, uint usdcSpent, uint lpTokensReceived) = router.addLiquidity(address(DOLA), address(nUSDC), true, dolaAmount, usdcAmount, 0, 0, address(this), block.timestamp);
        require(lpTokensReceived > 0, "No LP tokens received");

        uint totalDolaValue = usdcSpent * DOLA_USDC_CONVERSION_MULTI + dolaSpent;

        uint expectedLpTokens = applySlippage(totalDolaValue * 1e18 / lpTokenPrice, maxSlippageBpsLiquidity);
        if (lpTokensReceived < expectedLpTokens) revert LiquiditySlippageTooHigh();
        
        uint lpBalance = LP_TOKEN.balanceOf(address(this));
        LP_TOKEN.approve(address(dolaGauge), lpBalance);
        dolaGauge.deposit(lpBalance);
    }

    /**
     * @notice Attempts to deposit `dolaAmount` of DOLA & `usdcAmount` of USDC into Velodrome DOLA/USDC stable pool. Then, deposits LP tokens into gauge.
     * @param dolaAmount Amount of DOLA to be added as liquidity in Velodrome DOLA/USDC pool
     * @param usdcAmount Amount of USDC to be added as liquidity in Velodrome DOLA/USDC pool
     */
    function deposit(uint dolaAmount, uint usdcAmount) external onlyRole(l1Chair, l2Chair) {
        _deposit(dolaAmount, usdcAmount);
    }

    /**
     * @notice Calls `deposit()` with entire DOLA & USDC token balance of this contract.
     */
    function depositAll() external onlyRole(l1Chair, l2Chair) {
        _deposit(DOLA.balanceOf(address(this)), nUSDC.balanceOf(address(this)));
    }

    /**
     * @notice Withdraws `dolaAmount` worth of LP tokens from gauge. Then, redeems LP tokens for DOLA/USDC.
     * @dev If attempting to remove more DOLA than total LP tokens are worth, will remove all LP tokens.
     * @param dolaAmount Desired dola value to remove from DOLA/USDC pool. Will attempt to remove 50/50 while allowing for `maxSlippageBpsLiquidity` bps of variance.
     * @return Amount of USDC received from liquidity removal. Used by withdrawLiquidityAndSwap wrapper.
     */
    function _withdrawLiquidity(uint dolaAmount) internal returns (uint) {
        uint lpTokenPrice = getLpTokenPrice();
        uint liquidityToWithdraw = dolaAmount * 1e18 / lpTokenPrice;
        uint ownedLiquidity = dolaGauge.balanceOf(address(this));

        if (liquidityToWithdraw > ownedLiquidity) liquidityToWithdraw = ownedLiquidity;
        dolaGauge.withdraw(liquidityToWithdraw);
   
        LP_TOKEN.approve(address(router), liquidityToWithdraw);
        (uint amountUSDC, uint amountDola) = router.removeLiquidity(address(nUSDC), address(DOLA), true, liquidityToWithdraw, 0, 0, address(this), block.timestamp);

        uint totalDolaReceived = amountDola + (amountUSDC *DOLA_USDC_CONVERSION_MULTI);

        if (applySlippage(dolaAmount, maxSlippageBpsLiquidity) > totalDolaReceived) {
            revert LiquiditySlippageTooHigh();
        }

        return amountUSDC;
    }

    /**
     * @notice Withdraws `dolaAmount` worth of LP tokens from gauge. Then, redeems LP tokens for DOLA/USDC.
     * @dev If attempting to remove more DOLA than total LP tokens are worth, will remove all LP tokens.
     * @param dolaAmount Desired dola value to remove from DOLA/USDC pool. Will attempt to remove 50/50 while allowing for `maxSlippageBpsLiquidity` bps of variance.
     * @return Amount of USDC received from liquidity removal. Used by withdrawLiquidityAndSwap wrapper.
     */
    function withdrawLiquidity(uint dolaAmount) external onlyRole(l1Chair, l2Chair) returns (uint) {
        return _withdrawLiquidity(dolaAmount);
    }
 
    /**
     * @notice Withdraws `dolaAmount` worth of LP tokens from gauge. Then, redeems LP tokens for DOLA/USDC and swaps redeemed USDC to DOLA.
     * @param dolaAmount Desired dola value to remove from DOLA/USDC pool. Will attempt to remove 50/50 while allowing for `maxSlippageBpsLiquidity` bps of variance.
     */
    function withdrawLiquidityAndSwapToDOLA(uint dolaAmount) external onlyRole(l1Chair, l2Chair) {
        uint usdcAmount = _withdrawLiquidity(dolaAmount);

        swapUSDCNativetoDOLA(usdcAmount);
    }
    /**
     * @notice Withdraws `dolaAmount` of DOLA to optiFed on L1. Will take 7 days before withdraw is claimable on L1.
     * @param dolaAmount Amount of DOLA to withdraw and send to L1 OptiFed
     */
    function withdrawToL1OptiFed(uint dolaAmount) external onlyRole(l1Chair, l2Chair) {
        if (dolaAmount > DOLA.balanceOf(address(this))) revert NotEnoughTokens();

        bridge.withdrawTo(address(DOLA), optiFed, dolaAmount, 0, "");
    }

    /**
     * @notice Withdraws `dolaAmount` of DOLA & `usdcAmount` of USDC to optiFed on L1. Will take 7 days before withdraw is claimable on L1.
     * @param dolaAmount Amount of DOLA to withdraw and send to L1 OptiFed
     * @param usdcAmount Amount of USDC to withdraw and send to L1 OptiFed
     */
    function withdrawToL1OptiFedNative(uint dolaAmount, uint usdcAmount) external onlyRole(l1Chair, l2Chair) {
        if (dolaAmount > DOLA.balanceOf(address(this))) revert NotEnoughTokens();
        if (usdcAmount > nUSDC.balanceOf(address(this))) revert NotEnoughTokens();

        bridge.withdrawTo(address(DOLA), optiFed, dolaAmount, 0, "");
        nUSDC.approve(address(cctp), usdcAmount);
        cctp.depositForBurn(usdcAmount, MAINNET_CCTP_DOMAIN, bytes32(uint256(uint160(optiFed))), address(nUSDC));
    }

    function withdrawToL1OptiFedNative(uint usdcAmount) external onlyRole(l1Chair, l2Chair) {
        if (usdcAmount > nUSDC.balanceOf(address(this))) revert NotEnoughTokens();
        
        nUSDC.approve(address(cctp), usdcAmount);
        cctp.depositForBurn(usdcAmount, MAINNET_CCTP_DOMAIN, bytes32(uint256(uint160(optiFed))), address(nUSDC));
    }

    /**
     * @notice Withdraws `usdcAmount` of USDC to optiFed on L1. Will take 7 days before withdraw is claimable.
     * @param usdcAmount Amount of USDC to withdraw and send to L1 OptiFed
     */
    function withdrawToL1OptiFedBridged(uint usdcAmount) external onlyRole(l1Chair, l2Chair) {
        if (usdcAmount > USDC.balanceOf(address(this))) revert NotEnoughTokens();

        bridge.withdrawTo(address(USDC), optiFed, usdcAmount, 0, "");
    }
    /**
     * @notice Withdraws `amount` of `l2Token` to address `to` on L1. Will take 7 days before withdraw is claimable.
     * @param l2Token Address of the L2 token to be withdrawn
     * @param amount Amount of the L2 token to be withdrawn
     */
    function withdrawTokensToL1(address l2Token, uint amount) external onlyRole(l1Chair, l2Chair) {
        if (amount > IERC20(l2Token).balanceOf(address(this))) revert NotEnoughTokens();
        if(l2Token == address(DOLA) || l2Token == address(nUSDC) || l2Token == address(USDC) ) revert RestrictedToken();

        IERC20(l2Token).approve(address(bridge), amount);
        bridge.withdrawTo(l2Token, l1Treasury, amount, 0, "");
    }

    /**
     * @notice Swap `usdcAmount` of USDC to DOLA through velodrome.
     * @param usdcAmount Amount of USDC to swap to DOLA
     */
    function swapUSDCtoDOLA(uint usdcAmount) external onlyRole(l1Chair, l2Chair) {
        uint minOut = applySlippage(usdcAmount, maxSlippageBpsUsdcToDola) * DOLA_USDC_CONVERSION_MULTI;

        USDC.approve(address(router), usdcAmount);
        router.swapExactTokensForTokens(usdcAmount, minOut, getRoute(address(USDC), address(DOLA)), address(this), block.timestamp);
    }

    /**
     * @notice Swap `usdcAmount` of USDC to DOLA through velodrome.
     * @param usdcAmount Amount of USDC to swap to DOLA
     */
    function swapUSDCNativetoDOLA(uint usdcAmount) public onlyRole(l1Chair, l2Chair) {
        uint minOut = applySlippage(usdcAmount, maxSlippageBpsUsdcNativeToDola) * DOLA_USDC_CONVERSION_MULTI;

        nUSDC.approve(address(router), usdcAmount);
        router.swapExactTokensForTokens(usdcAmount, minOut, getRoute(address(nUSDC), address(DOLA)), address(this), block.timestamp);
    }

    /**
     * @notice Swap `dolaAmount` of DOLA to USDC through velodrome.
     * @param dolaAmount Amount of DOLA to swap to USDC
     */
    function swapDOLAtoUSDC(uint dolaAmount) external onlyRole(l1Chair, l2Chair) { 
        uint minOut = applySlippage(dolaAmount, maxSlippageBpsDolaToUsdc) / DOLA_USDC_CONVERSION_MULTI;
        
        DOLA.approve(address(router), dolaAmount);
        router.swapExactTokensForTokens(dolaAmount, minOut, getRoute(address(DOLA), address(USDC)), address(this), block.timestamp);
    }

    /**
     * @notice Swap `dolaAmount` of DOLA to USDC Native through velodrome.
     */
    function swapDOLAtoUSDCNative(uint dolaAmount) external onlyRole(l1Chair, l2Chair) { 
        uint minOut = applySlippage(dolaAmount, maxSlippageBpsDolaToUsdcNative) / DOLA_USDC_CONVERSION_MULTI;
        
        DOLA.approve(address(router), dolaAmount);
        router.swapExactTokensForTokens(dolaAmount, minOut, getRoute(address(DOLA), address(nUSDC)), address(this), block.timestamp);
    }

    /**
     * @notice Swap `usdcAmount` of USDC to USDC Native through velodrome.
     */
    function swapUSDCtoUSDCNative(uint usdcAmount) external onlyRole(l1Chair, l2Chair) {
        uint minOut = applySlippage(usdcAmount, maxSlippageBpsUsdcToUsdcNative);
        USDC.approve(address(router), usdcAmount);
        router.swapExactTokensForTokens(usdcAmount, minOut, getRoute(address(USDC), address(nUSDC)), address(this), block.timestamp);
    }

    /**
     * @notice Swap `usdcAmount` of USDC Native to USDC through velodrome.
     */
    function swapUSDCNativeToUSDC(uint usdcAmount) public onlyRole(l1Chair, l2Chair) {
        uint minOut = applySlippage(usdcAmount, maxSlippageBpsUsdcNativeToUsdc);

        nUSDC.approve(address(router), usdcAmount);
        router.swapExactTokensForTokens(usdcAmount, minOut, getRoute(address(nUSDC), address(USDC)), address(this), block.timestamp);
    }


    /**
     * @notice Calculates approximate price of 1 Velodrome DOLA/USDC stable pool LP token
     */
    function getLpTokenPrice() internal view returns (uint) {
        (uint dolaAmountOneLP, uint usdcAmountOneLP) = router.quoteRemoveLiquidity(address(DOLA), address(nUSDC), true, factory, 0.001 ether);
        usdcAmountOneLP *= DOLA_USDC_CONVERSION_MULTI;
        return (dolaAmountOneLP + usdcAmountOneLP)*1000;
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
        IRouter.Route memory route = IRouter.Route(from, to, true, factory);
        IRouter.Route[] memory routeArray = new IRouter.Route[](1);
        routeArray[0] = route;
        return routeArray;
    }

    /**
     * @notice Method for current l1Chair of the fed to resign
     */
    function resign() external onlyRole(l1Chair, l2Chair) {
        if (msg.sender == l2Chair) {
            l2Chair = address(0);
        } else {
            l1Chair = address(0);
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

    function setMaxSlippageUsdcNativeToDola(uint newMaxSlippageBps) onlyGovOrGuardian external {
        if (newMaxSlippageBps > 10000) revert MaxSlippageTooHigh();
        maxSlippageBpsUsdcNativeToDola = newMaxSlippageBps;
    }

    function setMaxSlippageDolaToUsdcNative(uint newMaxSlippageBps) onlyGovOrGuardian external {
        if (newMaxSlippageBps > 10000) revert MaxSlippageTooHigh();
        maxSlippageBpsDolaToUsdcNative = newMaxSlippageBps;
    }

    function setMaxSlippageUsdcToUsdcNative(uint newMaxSlippageBps) onlyGovOrGuardian external {
        if (newMaxSlippageBps > 10000) revert MaxSlippageTooHigh();
        maxSlippageBpsUsdcToUsdcNative = newMaxSlippageBps;
    }

    function setMaxSlippageUsdcNativeToUsdc(uint newMaxSlippageBps) onlyGovOrGuardian external {
        if (newMaxSlippageBps > 10000) revert MaxSlippageTooHigh();
        maxSlippageBpsUsdcNativeToUsdc = newMaxSlippageBps;
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
    function setPendingGov(address newPendingGov_) onlyRole(gov, address(0)) external {
        pendingGov = newPendingGov_;
    }

    /**
     * @notice Method for `pendingGov` to claim `gov` role.
     */
    function claimGov() external onlyRole(pendingGov, address(0)) {
        gov = pendingGov;
        pendingGov = address(0);
    }

    /**
     * @notice Method for gov to change treasury address, the address that receives all rewards
     * @param newTreasury_ L2 address to be set as treasury
     */
    function changeTreasury(address newTreasury_) external onlyRole(gov, address(0)) {
        treasury = newTreasury_;
    }

    /**
     * @notice Method for gov to change the l1Chair
     * @dev l1Chair address should be set to the address of L1 VeloFarmerMessenger if it is being used
     * @param newL1Chair_ L1 address to be set as l1Chair
     */
    function changeL1Chair(address newL1Chair_) external onlyRole(gov, address(0)) {
        l1Chair = newL1Chair_;
    }

    /**
     * @notice Method for gov to change the L2 l1Chair
     * @param newL2Chair_ L2 address to be set as l2Chair
     */
    function changeL2Chair(address newL2Chair_) external onlyRole(gov, address(0)) {
        l2Chair = newL2Chair_;
    }

    /**
     * @notice Method for gov to change the guardian
     * @param guardian_ L1 address to be set as guardian
     */
    function changeGuardian(address guardian_) external onlyRole(gov, address(0)) {
        guardian = guardian_;
    }

    /**
     * @notice Method for gov to change the L1 optiFed address
     * @dev optiFed is the L1 address that receives all bridged DOLA/USDC from both withdrawToL1OptiFed functions
     * @param newOptiFed_ L1 address to be set as optiFed
     */
    function changeOptiFed(address newOptiFed_) external onlyRole(gov, address(0)) {
        optiFed = newOptiFed_;
    }
}
