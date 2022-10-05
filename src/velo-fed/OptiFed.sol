pragma solidity ^0.8.13;

import "../interfaces/IERC20.sol";
import "../interfaces/velo/IDola.sol";
import "../interfaces/velo/IL1ERC20Bridge.sol";
import "../interfaces/velo/ICurvePool.sol";

contract OptiFed {
    address public chair;
    address public gov;
    address public pendingGov;
    uint public dolaSupply;
    uint public maxSlippageBpsDolaToUsdc;
    uint public maxSlippageBpsUsdcToDola;

    uint constant PRECISION = 10_000;
    uint public constant DOLA_USDC_CONVERSION_MULTI= 1e12;

    IDola public constant DOLA = IDola(0x865377367054516e17014CcdED1e7d814EDC9ce4);
    IERC20 public constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IL1ERC20Bridge public constant optiBridge = IL1ERC20Bridge(0x99C9fc46f92E8a1c0deC1b1747d010903E884bE1);
    address public constant DOLA_OPTI = 0x8aE125E8653821E851F12A49F7765db9a9ce7384;
    address public constant USDC_OPTI = 0x7F5c764cBc14f9669B88837ca1490cCa17c31607;
    ICurvePool public curvePool = ICurvePool(0xAA5A67c256e27A5d80712c51971408db3370927D);
    address public veloFarmer;

    event Expansion(uint amount);
    event Contraction(uint amount);

    error OnlyGov();
    error OnlyPendingGov();
    error OnlyChair();
    error CantBurnZeroDOLA();
    error MaxSlippageTooHigh();
    error DeltaAboveMax();

    constructor(
            address gov_,
            address chair_,
            address veloFarmer_,
            uint maxSlippageBpsDolaToUsdc_,
            uint maxSlippageBpsUsdcToDola_)
    {
        gov = gov_;
        chair = chair_;
        veloFarmer = veloFarmer_;
        maxSlippageBpsDolaToUsdc = maxSlippageBpsDolaToUsdc_;
        maxSlippageBpsUsdcToDola = maxSlippageBpsUsdcToDola_;
    }

    /**
    @notice Mints `dolaAmount` of DOLA, swaps half to USDC, then transfers all to `veloFarmer` through optimism bridge
    @param dolaAmount Amount of DOLA to mint
    */
    function expansionAndSwap(uint dolaAmount) external {
        if (msg.sender != chair) revert OnlyChair();
        
        dolaSupply += dolaAmount;
        DOLA.mint(address(this), dolaAmount);

        uint halfDolaAmount = dolaAmount / 2;
        DOLA.approve(address(curvePool), halfDolaAmount);
        uint usdcAmount = curvePool.exchange_underlying(0, 2, halfDolaAmount, halfDolaAmount * (PRECISION - maxSlippageBpsDolaToUsdc) / PRECISION / DOLA_USDC_CONVERSION_MULTI);

        DOLA.approve(address(optiBridge), halfDolaAmount);
        USDC.approve(address(optiBridge), usdcAmount);
        optiBridge.depositERC20To(address(DOLA), DOLA_OPTI, veloFarmer, halfDolaAmount, 200_000, "");
        optiBridge.depositERC20To(address(USDC), USDC_OPTI, veloFarmer, usdcAmount, 200_000, "");

        emit Expansion(dolaAmount);
    }

    /**
    @notice Mints & deposits `amountUnderlying` of `underlying` tokens into Optimism bridge to the `veloFarmer` contract
    @param dolaAmount Amount of underlying token to mint & deposit into Velodrome farmer on Optimism
    */
    function expansion(uint dolaAmount) external {
        if (msg.sender != chair) revert OnlyChair();
        
        dolaSupply += dolaAmount;
        DOLA.mint(address(this), dolaAmount);

        DOLA.approve(address(optiBridge), dolaAmount);
        optiBridge.depositERC20To(address(DOLA), DOLA_OPTI, veloFarmer, dolaAmount, 200_000, "");

        emit Expansion(dolaAmount);
    }

    /**
    @notice Burns `dolaAmount` of DOLA held in this contract
    @param dolaAmount Amount of DOLA to burn
    */
    function contraction(uint dolaAmount) public {
        if (msg.sender != chair) revert OnlyChair();

        _contraction(dolaAmount);
    }

    /**
    @notice Attempts to contract (burn) all DOLA held by this contract
    */
    function contractAll() external {
        if (msg.sender != chair) revert OnlyChair();

        _contraction(DOLA.balanceOf(address(this)));
    }

    /**
    @notice Attempts to contract (burn) `amount` of DOLA. Sends remainder to `gov` if `amount` > DOLA minted by this fed.
    @param amount Amount of DOLA to contract.
    */
    function _contraction(uint amount) internal{
        if (amount == 0) revert CantBurnZeroDOLA();
        if(amount > dolaSupply){
            DOLA.burn(dolaSupply);
            DOLA.transfer(gov, amount - dolaSupply);
            emit Contraction(dolaSupply);
            dolaSupply = 0;
        } else {
            DOLA.burn(amount);
            dolaSupply -= amount;
            emit Contraction(amount);
        }
    }

    /**
    @notice Swap `usdcAmount` of USDC for DOLA through curve.
    @dev Will revert if actual slippage > `maxSlippageBpsUsdcToDola`
    @param usdcAmount Amount of USDC to be swapped to DOLA through curve.
    */
    function swapUSDCtoDOLA(uint usdcAmount) external {
        if (msg.sender != chair) revert OnlyChair();
        
        USDC.approve(address(curvePool), usdcAmount);
        curvePool.exchange_underlying(2, 0, usdcAmount, usdcAmount * (PRECISION - maxSlippageBpsUsdcToDola) / PRECISION * DOLA_USDC_CONVERSION_MULTI);
    }

    /**
    @notice Swap `dolaAmount` of DOLA for USDC through curve.
    @dev Will revert if actual slippage > `maxSlippageBpsDolaToUsdc`
    @param dolaAmount Amount of DOLA to be swapped to USDC through curve.
    */
    function swapDOLAtoUSDC(uint dolaAmount) external {
        if (msg.sender != chair) revert OnlyChair();
        
        DOLA.approve(address(curvePool), dolaAmount);
        curvePool.exchange_underlying(0, 2, dolaAmount, dolaAmount * (PRECISION - maxSlippageBpsDolaToUsdc) / PRECISION / DOLA_USDC_CONVERSION_MULTI);
    }

    /**
    @notice Method for current chair of the Opti FED to resign
    */
    function resign() external {
        if (msg.sender != chair) revert OnlyChair();
        chair = address(0);
    }

    /**
    @notice Governance only function for setting acceptable slippage when swapping DOLA -> USDC
    @param newMaxSlippageBps The new maximum allowed loss for DOLA -> USDC swaps. 1 = 0.01%
    */
    function setMaxSlippageDolaToUsdc(uint newMaxSlippageBps) external {
        if (msg.sender != gov) revert OnlyGov();
        if (newMaxSlippageBps > 10000) revert MaxSlippageTooHigh();
        maxSlippageBpsDolaToUsdc = newMaxSlippageBps;
    }

    /**
    @notice Governance only function for setting acceptable slippage when swapping USDC -> DOLA
    @param newMaxSlippageBps The new maximum allowed loss for USDC -> DOLA swaps. 1 = 0.01%
    */
    function setMaxSlippageUsdcToDola(uint newMaxSlippageBps) external {
        if (msg.sender != gov) revert OnlyGov();
        if (newMaxSlippageBps > 10000) revert MaxSlippageTooHigh();
        maxSlippageBpsUsdcToDola = newMaxSlippageBps;
    }

    /**
    @notice Method for `gov` to change `pendingGov` address
    @dev `pendingGov` will have to call `claimGov` to complete `gov` transfer
    @param newPendingGov_ Address to be set as `pendingGov`
    */
    function setPendingGov(address newPendingGov_) external {
        if (msg.sender != gov) revert OnlyGov();
        pendingGov = newPendingGov_;
    }

    /**
    @notice Method for `pendingGov` to claim `gov` role.
    */
    function claimGov() external {
        if (msg.sender != pendingGov) revert OnlyPendingGov();
        gov = pendingGov;
        pendingGov = address(0);
    }

    /**
    @notice Method for gov to change the chair
    @param newChair_ Address to be set as chair
    */
    function changeChair(address newChair_) external {
        if (msg.sender != gov) revert OnlyGov();
        chair = newChair_;
    }

    /**
    @notice Method for gov to change the L2 veloFarmer address
    @dev veloFarmer is the L2 address that receives all bridged DOLA from expansion
    @param newVeloFarmer_ L2 address to be set as veloFarmer
    */
     function changeVeloFarmer(address newVeloFarmer_) external {
        if (msg.sender != gov) revert OnlyGov();
        veloFarmer = newVeloFarmer_;
    }

    /**
    @notice Method for gov to change the curve pool address
    @param newCurvePool_ Address to be set as curvePool
    */
     function changeCurvePool(address newCurvePool_) external {
        if (msg.sender != gov) revert OnlyGov();
        curvePool = ICurvePool(newCurvePool_);
    }
}