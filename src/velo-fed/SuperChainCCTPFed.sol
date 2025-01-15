// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "src/interfaces/IERC20.sol";
import "src/interfaces/velo/IDola.sol";
import "src/interfaces/velo/IL1ERC20Bridge.sol";
import {Chairable} from "src/utils/Chairable.sol";

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

/**
 * @title SuperChainCCTPFed
 * @notice A generic contract for SuperChain CCTP Feds
 */
contract SuperChainCCTPFed is Chairable {
    error CantBurnZeroDOLA();
    error MaxSlippageTooHigh();
    error SlippageTooHigh();
    error SwapMoreDolaThanMinted();
    error SwapFailed();
    error ZeroAddressParameter();

    uint256 public dolaSupply;
    uint256 public maxSlippageBpsDolaToUsdc;
    uint256 public maxSlippageBpsUsdcToDola;
    address public exchangeProxy;
    address public farmer;

    uint256 public constant PRECISION = 10_000;
    uint256 public constant DOLA_USDC_CONVERSION_MULTI = 1e12;

    IDola public constant DOLA =
        IDola(0x865377367054516e17014CcdED1e7d814EDC9ce4);
    IERC20 public constant USDC =
        IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ICCTP public constant CCTP =
        ICCTP(0xBd3fa81B58Ba92a82136038B25aDec7066af3155);

    IL1ERC20Bridge public immutable BRIDGE;
    address public immutable DOLA_CHAIN;
    address public immutable USDC_CHAIN;
    uint32 public immutable CCTP_DOMAIN;

    event Expansion(uint256 amount);
    event Contraction(uint256 amount);
    event NewFarmer(address indexed oldFarmer, address indexed newFarmer);
    event NewExchangeProxy(
        address indexed oldExchangeProxy,
        address indexed newExchangeProxy
    );
    event NewMaxSlippageDolaToUsdc(
        uint256 oldMaxSlippageBps,
        uint256 newMaxSlippageBps
    );
    event NewMaxSlippageUsdcToDola(
        uint256 oldMaxSlippageBps,
        uint256 newMaxSlippageBps
    );
    event SwapDOLAtoUSDC(uint256 dolaAmount, uint256 usdcAmount);
    event SwapUSDCtoDOLA(uint256 usdcAmount, uint256 dolaAmount);

    constructor(
        address gov_,
        address chair_,
        address farmer_,
        address exchangeProxy_,
        uint256 maxSlippageBpsDolaToUsdc_,
        uint256 maxSlippageBpsUsdcToDola_,
        address bridge_,
        address dola_chain_,
        address usdc_chain_,
        uint32 domain_
    ) Chairable(gov_, chair_) {
        farmer = farmer_;
        exchangeProxy = exchangeProxy_;
        maxSlippageBpsDolaToUsdc = maxSlippageBpsDolaToUsdc_;
        maxSlippageBpsUsdcToDola = maxSlippageBpsUsdcToDola_;
        BRIDGE = IL1ERC20Bridge(bridge_);
        DOLA_CHAIN = dola_chain_;
        USDC_CHAIN = usdc_chain_;
        CCTP_DOMAIN = domain_;
    }

    /**
     * @notice Mints `dolaAmount` of DOLA, swaps `dolaToSwap` of DOLA to USDC, then transfers all to `farmer` through L1 bridge
     * @param dolaAmount Amount of DOLA to mint
     * @param dolaToSwap Amount of DOLA to swap for USDC
     * @param useCCTP If true, will use CCTP to bridge USDC. If false, will use L1 bridge
     * @param swapCallData Data for calling the exchange proxy to swap DOLA for USDC
     */
    function expansionAndSwap(
        uint256 dolaAmount,
        uint256 dolaToSwap,
        bool useCCTP,
        bytes calldata swapCallData
    ) external onlyChair {
        if (dolaToSwap > dolaAmount) revert SwapMoreDolaThanMinted();

        dolaSupply += dolaAmount;
        DOLA.mint(address(this), dolaAmount);

        DOLA.approve(exchangeProxy, dolaToSwap);
        uint256 usdcAmountBefore = USDC.balanceOf(address(this));

        (bool success, ) = exchangeProxy.call(swapCallData);
        if (!success) revert SwapFailed();

        uint256 usdcAmountAfter = USDC.balanceOf(address(this));
        uint256 usdcAmount = usdcAmountAfter - usdcAmountBefore;

        if (
            usdcAmount <
            (dolaToSwap * (PRECISION - maxSlippageBpsDolaToUsdc)) /
                PRECISION /
                DOLA_USDC_CONVERSION_MULTI
        ) {
            revert SlippageTooHigh();
        }

        uint256 dolaToBridge = dolaAmount - dolaToSwap;
        DOLA.approve(address(BRIDGE), dolaToBridge);

        BRIDGE.depositERC20To(
            address(DOLA),
            DOLA_CHAIN,
            farmer,
            dolaToBridge,
            200_000,
            ""
        );

        if (useCCTP) {
            USDC.approve(address(CCTP), usdcAmount);
            CCTP.depositForBurn(
                usdcAmount,
                CCTP_DOMAIN,
                bytes32(uint256(uint160(farmer))),
                address(USDC)
            );
        } else {
            USDC.approve(address(BRIDGE), usdcAmount);
            BRIDGE.depositERC20To(
                address(USDC),
                USDC_CHAIN,
                farmer,
                usdcAmount,
                200_000,
                ""
            );
        }

        emit Expansion(dolaAmount);
    }

    /**
     * @notice Mints & deposits `amountUnderlying` of `underlying` tokens into L1 bridge to the `farmer` contract
     * @param dolaAmount Amount of underlying token to mint & deposit into the farmer on the SuperChain
     */
    function expansion(uint256 dolaAmount) external onlyChair {
        dolaSupply += dolaAmount;
        DOLA.mint(address(this), dolaAmount);

        DOLA.approve(address(BRIDGE), dolaAmount);
        BRIDGE.depositERC20To(
            address(DOLA),
            DOLA_CHAIN,
            farmer,
            dolaAmount,
            200_000,
            ""
        );

        emit Expansion(dolaAmount);
    }

    /**
     * @notice Burns `dolaAmount` of DOLA held in this contract
     * @param dolaAmount Amount of DOLA to burn
     */
    function contraction(uint256 dolaAmount) public onlyChair {
        _contraction(dolaAmount);
    }

    /**
     * @notice Attempts to contract (burn) all DOLA held by this contract
     */
    function contractAll() external onlyChair {
        _contraction(DOLA.balanceOf(address(this)));
    }

    /**
     * @notice Attempts to contract (burn) `amount` of DOLA. Sends remainder to `gov` if `amount` > DOLA minted by this fed.
     * @param amount Amount of DOLA to contract.
     */
    function _contraction(uint256 amount) internal {
        if (amount == 0) revert CantBurnZeroDOLA();
        if (amount > dolaSupply) {
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
     * @notice Swap `usdcAmount` of USDC for DOLA through the exchange proxy.
     * @dev Will revert if actual slippage > `maxSlippageBpsUsdcToDola`
     * @param usdcAmount Amount of USDC to be swapped to DOLA through the exchange proxy.
     * @param swapCallData Data for calling the exchange proxy to swap USDC for DOLA
     */
    function swapUSDCtoDOLA(
        uint256 usdcAmount,
        bytes calldata swapCallData
    ) external onlyChair {
        USDC.approve(exchangeProxy, usdcAmount);
        uint256 dolaAmountBefore = DOLA.balanceOf(address(this));

        (bool success, ) = exchangeProxy.call(swapCallData);
        if (!success) revert SwapFailed();

        uint256 dolaAmount = DOLA.balanceOf(address(this)) - dolaAmountBefore;
        if (
            dolaAmount <
            (usdcAmount *
                (PRECISION - maxSlippageBpsUsdcToDola) *
                DOLA_USDC_CONVERSION_MULTI) /
                PRECISION
        ) {
            revert SlippageTooHigh();
        }
        emit SwapUSDCtoDOLA(usdcAmount, dolaAmount);
    }

    /**
     * @notice Swap `dolaAmount` of DOLA for USDC through the exchange proxy.
     * @dev Will revert if actual slippage > `maxSlippageBpsDolaToUsdc`
     * @param dolaAmount Amount of DOLA to be swapped to USDC through the exchange proxy.
     * @param swapCallData Data for calling the exchange proxy to swap DOLA for USDC
     */
    function swapDOLAtoUSDC(
        uint256 dolaAmount,
        bytes calldata swapCallData
    ) external onlyChair {
        DOLA.approve(exchangeProxy, dolaAmount);
        uint256 usdcAmountBefore = USDC.balanceOf(address(this));
        (bool success, ) = exchangeProxy.call(swapCallData);
        if (!success) revert SwapFailed();
        uint256 usdcAmount = USDC.balanceOf(address(this)) - usdcAmountBefore;
        if (
            usdcAmount <
            (dolaAmount * (PRECISION - maxSlippageBpsDolaToUsdc)) /
                DOLA_USDC_CONVERSION_MULTI /
                PRECISION
        ) {
            revert SlippageTooHigh();
        }
        emit SwapDOLAtoUSDC(dolaAmount, usdcAmount);
    }

    /**
     * @notice Set the new exchange proxy address
     * @param newExchangeProxy Address of the new exchange proxy
     */
    function setExchangeProxy(address newExchangeProxy) external onlyGov {
        if (newExchangeProxy == address(0)) revert ZeroAddressParameter();
        emit NewExchangeProxy(exchangeProxy, newExchangeProxy);
        exchangeProxy = newExchangeProxy;
    }

    /**
     * @notice Governance only function for setting acceptable slippage when swapping DOLA -> USDC
     * @param newMaxSlippageBps The new maximum allowed loss for DOLA -> USDC swaps. 1 = 0.01%
     */
    function setMaxSlippageDolaToUsdc(
        uint256 newMaxSlippageBps
    ) external onlyGov {
        if (newMaxSlippageBps > 10000) revert MaxSlippageTooHigh();
        emit NewMaxSlippageDolaToUsdc(
            maxSlippageBpsDolaToUsdc,
            newMaxSlippageBps
        );
        maxSlippageBpsDolaToUsdc = newMaxSlippageBps;
    }

    /**
     * @notice Governance only function for setting acceptable slippage when swapping USDC -> DOLA
     * @param newMaxSlippageBps The new maximum allowed loss for USDC -> DOLA swaps. 1 = 0.01%
     */
    function setMaxSlippageUsdcToDola(
        uint256 newMaxSlippageBps
    ) external onlyGov {
        if (newMaxSlippageBps > 10000) revert MaxSlippageTooHigh();
        emit NewMaxSlippageUsdcToDola(
            maxSlippageBpsUsdcToDola,
            newMaxSlippageBps
        );
        maxSlippageBpsUsdcToDola = newMaxSlippageBps;
    }

    /**
    @notice Method for gov to change the L2 farmer address
    @dev farmer is the L2 address that receives all bridged DOLA from expansion
    @param newFarmer L2 address to be set as farmer
    */
    function changeFarmer(address newFarmer) external onlyGov {
        if (newFarmer == address(0)) revert ZeroAddressParameter();
        emit NewFarmer(farmer, newFarmer);
        farmer = newFarmer;
    }
}
