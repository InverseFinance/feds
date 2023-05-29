pragma solidity ^0.8.13;
import "src/interfaces/IERC20.sol";

abstract contract BaseFed {
    //Mintable DOLA contract
    IERC20 public immutable DOLA;
    //Amount of DOLA the contract has minted
    uint public debt;
    //Amount of claims the contract has on underlying markets
    uint public claims;
    //Treasury of Inverse Finance DAO
    address public gov;
    //Pending change of the governance role
    address public pendingGov;
    //Chair address allowed to perform expansions and contractions
    address public chair;

    constructor(address _DOLA, address _gov, address _chair){
        require(gov != address(0), "Gov set to 0");
        require(_DOLA != address(0), "Must be correct DOLA address");
        require(block.chainid == 1, "Must mint DOLA on Mainnet");
        gov = _gov;
        chair = _chair;
        DOLA = IERC20(_DOLA);
    }

    // ******************
    // * Access Control *
    // ******************

    modifier onlyGov(){
        require(msg.sender == gov, "NOT GOV");
        _;
    }

    modifier onlyChair(){
        require(msg.sender == chair || msg.sender == gov, "NOT PERMISSIONED");
        _;
    }

    /**
     * @notice Sets the pendingGov, which can claim gov role.
     * @dev Only callable by gov
     */
    function setPendingGov(address _pendingGov) onlyGov external {
        pendingGov = _pendingGov;
        emit NewPendingGov(_pendingGov);
    }

    /**
     * @notice Claims the gov role
     * @dev Only callable by pendingGov
     */
    function claimPendingGov() external {
        require(msg.sender == pendingGov, "NOT PENDING GOV");
        gov = pendingGov;
        pendingGov = address(0);
        emit NewGov(gov);
    }

    /**
     * @notice Sets the chair of the Fed
     * @dev Only callable by gov
     */
    function setChair(address newChair) onlyGov external{
        chair = newChair;
        emit NewChair(newChair);
    }

    /**
     * @notice Resigns from the Fed role
     * @dev Useful in case of key compromise or multi-sig compromise
     */
    function resign() onlyChair external{
        chair = address(0);
    }

    // **********************
    // * Abstract Functions *
    // **********************


    /**
     * @notice Function for expanding DOLA into a given fed market.
     * @param amount Amount of DOLA to mint and expand into the fed.
     * @dev May fail due to exceeding max loss parameters when depositing to lossy markets
     */
    function expansion(uint amount) onlyChair virtual external {
        revert("NOT IMPLEMENTED");
    }

    /**
     * @notice Function for contracting DOLA from the attached market, and repaying debt.
     * @param amount Amount of DOLA to attempt to withdraw and burn, may be imprecise due to underlying contracts.
     * @dev May fail due to exceeding max loss parameters when withdrawing from lossy markets
     */
    function contraction(uint amount) onlyChair virtual external {
        revert("NOT IMPLEMENTED");
    }

    /**
     * @notice Function for turning all claims into DOLA, burning up to the debt, and sending the rest to gov.
     * @dev May fail due to exceeding max loss parameters when withdrawing from lossy markets
     */   
    function contractAll() onlyChair virtual external {
        revert("NOT IMPLEMENTED");
    }


    /**
     * @notice Internal function for paying down debt. Should be used in all functions that pay down DOLA debt,
     like contraction, contractAll and repayDebt.
     * @dev Must send any surplus DOLA to gov.
     * @dev Should be used by repayDebt, contraction and contractAll functions
     * @param amount Amount of debt to repay.
     */
    function _repayDebt(uint amount) virtual internal;

    /**
     * @notice Funtion for taking profit from profit generating feds.
     * @dev Must attempt to not take excessive profit
     * @dev Must NOT reduce debt
     * @dev Profits must be sent to governance
     * @param flag Flag for signalling certain profit taking behaviour.
       Some profit taking may be unsafe and should be permissioned to only chair,
       while other profit taking may be safe for all to call.
     */
    function takeProfit(uint flag) external virtual;

    /**
     * @notice Function for withdrawing underlying of Fed in emergency.
       Can be useful in case of Fed accounting errors, hacks of underlying market or accidents.
     * @dev Will likely destroy all contract accounting. Use carefully. Should send withdrawn tokens to gov.
     */
    function emergencyWithdraw() onlyGov external virtual{
        revert("NOT IMPLEMENTED");
    }

    // **********************
    // * Standard Functions *
    // **********************

    /**
     * @notice Function for withdrawing stuck tokens of Fed in emergency.
       Can be useful in case of Fed accounting errors, hacks of underlying market or accidents.
     * @dev May destroy all accounting if used on DOLA or claims. Use carefully.
     * @param token Token to sweep balance of to governance
     */
    function sweep(address token) onlyGov external {
        IERC20(token).transfer(gov, IERC20(token).balanceOf(address(this)));
    }

    /**
     * @notice Accounting function for repaying any debt that the contract will be unable to repay itself.
     * @param amount Amount of debt to repay.
     */
    function repayDebt(uint amount) external {
        require(amount <= debt, "BURN HIGHER THAN DEBT");
        DOLA.transferFrom(msg.sender, address(this), amount);
        _repayDebt(amount);
    }


    // **********
    // * Events *
    // **********

    event NewChair(address newChair);
    event NewPendingGov(address newPendingGov);
    event NewGov(address newGov);
    event Expansion(uint amount);
    event Contraction(uint amount);
    event Profit(address token, uint amount);
}
