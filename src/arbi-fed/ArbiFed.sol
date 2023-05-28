pragma solidity ^0.8.13;

import "src/interfaces/IERC20.sol";
import "src/interfaces/velo/IDola.sol";
import "src/interfaces/velo/IL1ERC20Bridge.sol";
import {IL1GatewayRouter} from "arbitrum/tokenbridge/ethereum/gateway/IL1GatewayRouter.sol";

contract ArbiFed {
    address public chair;
    address public gov;
    address public l2Chair;
    uint public underlyingSupply;
    uint public lastDeltaUpdate;
    uint public maxDailyDelta;
    uint private dailyDelta;

    IDola public immutable DOLA = IDola(0x865377367054516e17014CcdED1e7d814EDC9ce4);
    IL1GatewayRouter public immutable gatewayRouter = IL1GatewayRouter(0x72Ce9c846789fdB6fC1f34aC4AD25Dd9ef7031ef); 
    IL1GatewayRouter  public immutable gateway = IL1GatewayRouter(0xb4299A1F5f26fF6a98B7BA35572290C359fde900);
    address public immutable l1ERC20Gateway = 0xa3A7B6F88361F48403514059F1F16C8E78d60EeC;

    address public auraFarmer; // On L2

    event Expansion(uint amount);
    event Contraction(uint amount);

    error OnlyGov();
    error OnlyChair();
    error CantBurnZeroDOLA();
    error DeltaAboveMax();
    error ZeroGasPriceBid();
    
    constructor(
            address gov_,
            address auraFarmer_,
            address l2Chair_,
            uint maxDailyDelta_)
    {
        chair = msg.sender;
        gov = gov_;
        auraFarmer = auraFarmer_;
        l2Chair = l2Chair_;
        maxDailyDelta = maxDailyDelta_; 
        lastDeltaUpdate = block.timestamp - 1 days;

        DOLA.approve(address(l1ERC20Gateway), type(uint).max); 
    }

    modifier onlyGov {
        if (msg.sender != gov) revert OnlyGov();
        _;
    }

    modifier onlyChair {
        if (msg.sender != chair) revert OnlyChair();
        _;
    }

    /**
    @notice Mints & deposits `amountUnderlying` of `underlying` tokens into Arbitrum Gateway to the `auraFarmer` contract
    @param amountUnderlying Amount of underlying token to mint & deposit into Aura farmer on Arbitrum
    */
    function expansion(uint amountUnderlying, uint256 gasLimit, uint256 gasPriceBid, bytes memory data) external payable onlyChair {
        if (gasPriceBid == 0) revert ZeroGasPriceBid();

        _updateDailyDelta(amountUnderlying);
        underlyingSupply += amountUnderlying;
        DOLA.mint(address(this), amountUnderlying);

        gatewayRouter.outboundTransferCustomRefund{value: msg.value}(
        address(DOLA),
        l2Chair,// where should we refund excess L2 gas? 
        auraFarmer,
        DOLA.balanceOf(address(this)),
        gasLimit, 
        gasPriceBid, 
        data
    );

        emit Expansion(amountUnderlying);
    }

    /**
    @notice Burns `amountUnderlying` of DOLA held in this contract
    */
    function contraction(uint amountUnderlying) external onlyChair {

        _contraction(amountUnderlying);
    }

    /**
    @notice Attempts to contract (burn) all DOLA held by this contract
    */
    function contractAll() external onlyChair {

        _contraction(DOLA.balanceOf(address(this)));
    }

    /**
    @notice Attempts to contract (burn) `amount` of DOLA. Sends remainder to `gov` if `amount` > DOLA minted by this fed.
    */
    function _contraction(uint amount) internal {
        if (amount == 0) revert CantBurnZeroDOLA();
        if(amount > underlyingSupply){
            DOLA.burn(underlyingSupply);
            _updateDailyDelta(underlyingSupply);
            DOLA.transfer(gov, amount - underlyingSupply);
            emit Contraction(underlyingSupply);
            underlyingSupply = 0;
        } else {
            DOLA.burn(amount);
            _updateDailyDelta(amount);
            underlyingSupply -= amount;
            emit Contraction(amount);
        }
    }

    /**
    @notice Method for current chair of the Arbi FED to resign
    */
    function resign() external onlyChair {
        chair = address(0);
    }
    
    /**
    @notice Updates dailyDelta and lastDeltaUpdate
    @dev This is the only way you should update dailyDelta or lastDeltaUpdate!
    @param delta The delta the dailyDelta is updated with
    */
    function _updateDailyDelta(uint delta) internal {
        //If statement isn't strictly necessary, but saves gas as long as function is called less than daily
        if(lastDeltaUpdate + 1 days <= block.timestamp){
            dailyDelta = delta;
        } else {
            uint freedDelta = maxDailyDelta * (block.timestamp - lastDeltaUpdate) / 1 days;
            dailyDelta = freedDelta >= dailyDelta ? delta : dailyDelta - freedDelta + delta;
        }
        if (dailyDelta > maxDailyDelta) revert DeltaAboveMax();
        lastDeltaUpdate = block.timestamp;
    }

    /**
    @notice Governance only function for setting maximum daily DOLA supply delta allowed for the fed
    @param newMaxDailyDelta The new maximum amount underlyingSupply can be expanded or contracted in a day
    */
    function setMaxDailyDelta(uint newMaxDailyDelta) external onlyGov {
        maxDailyDelta = newMaxDailyDelta;
    }

    /**
    @notice View function for reading the available daily delta
    */
    function availableDailyDelta() public view returns(uint){
        uint freedDelta = maxDailyDelta * (block.timestamp - lastDeltaUpdate) / 1 days;
        return freedDelta >= dailyDelta ? maxDailyDelta : maxDailyDelta - dailyDelta + freedDelta;
    }

    /**
    @notice Method for gov to change gov address
    */
    function changeGov(address newGov) external onlyGov {
        gov = newGov;
    }

    /**
    @notice Method for gov to change the chair
    */
    function changeChair(address newChair) external onlyGov {
        chair = newChair;
    }

    /**
    @notice Method for gov to change the L2 auraFarmer address
    */
    function changeAuraFarmer(address newAuraFarmer) external onlyGov {
        auraFarmer = newAuraFarmer;
    }

    /**
    @notice Method for gov to withdraw any ERC20 token from this contract
    */
    function emergecyWithdraw(address token, address to, uint256 amount) external onlyGov {
        IERC20(token).transfer(to, amount);
    }
    
}