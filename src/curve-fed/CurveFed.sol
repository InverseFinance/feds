pragma solidity ^0.8.13;

import "src/interfaces/IERC20.sol";
import "src/interfaces/curve/IMetaPool.sol";
import "src/curve-fed/CurvePoolAdapter.sol";

contract CurveFed is CurvePoolAdapter {

    address public chair; // Fed Chair
    address public gov;
    address public pendingGov;
    address public guardian;
    uint public dolaSupply;
    uint public supplyCeiling = type(uint).max;
    uint public maxLossExpansionBps;
    uint public maxLossWithdrawBps;
    uint public guardianMaxLossBpsLimit;

    event Expansion(uint amount);
    event Contraction(uint amount);
    event ClaimRewards(uint amount, address token);

    constructor(
            address _crvPoolAddr,
            address _chair,
            address _gov,
            address _guardian,
            uint _maxLossExpansionBps,
            uint _maxLossWithdrawBps,
            uint _guardianMaxLossBpsLimit
            )
            CurvePoolAdapter(_crvPoolAddr)
    {
        maxLossExpansionBps = _maxLossExpansionBps;
        maxLossWithdrawBps = _maxLossWithdrawBps;
        guardianMaxLossBpsLimit = _guardianMaxLossBpsLimit;
        chair = _chair;
        gov = _gov;
        guardian = _guardian;
    }

    modifier onlyRole(address _role) {
        require(msg.sender == _role, "Unauthorized");
        _;
    }

    modifier onlyRoleOrGov(address _role) {
        require(msg.sender == _role || msg.sender == gov, "Unauthorized");
        _;
    }

    /**
    * @notice Method for gov to change gov address
    * @param _newGov Address of the new governor
    */
    function setPendingGov(address _newGov) external onlyRole(gov){
        pendingGov = _newGov;
    }

    /**
    * @notice Claim governance role
    */
    function claimGov() external onlyRole(pendingGov){
        gov = pendingGov;
        pendingGov = address(0);
    }

    /**
    * @notice Method for gov to change the chair
    * @param _newChair Address of the new chair
    */
    function setChair(address _newChair) external onlyRole(gov){
        chair = _newChair;
    }
    /**
    * @notice Method for gov to change the guardian
    * @param _newGuardian Address of the new guardian
    */
    function setGuardian(address _newGuardian) external onlyRole(gov){
        guardian = _newGuardian;
    }

    /**
    * @notice Method for current to resign
    */
    function resign() external onlyRole(chair){
        chair = address(0);
    }

    /**
    * @notice Set the maximum acceptable loss when expanding dola supply. Only callable by gov.
    * @param newMaxLossExpansionBps The maximum loss allowed by basis points 1 = 0.01%
    */
    function setMaxLossExpansionBps(uint newMaxLossExpansionBps) external onlyRole(gov){
        require(newMaxLossExpansionBps <= 10000, "Max loss > 100%");
        maxLossExpansionBps = newMaxLossExpansionBps;
    }

    /**
    * @notice Set the maximum acceptable loss when withdrawing dola supply. Only callable by gov or guardian.
    * @param newMaxLossWithdrawBps The maximum loss allowed by basis points 1 = 0.01%
    */
    function setMaxLossWithdrawBps(uint newMaxLossWithdrawBps) external onlyRoleOrGov(guardian){
        require(newMaxLossWithdrawBps <= 10000, "Max loss > 100%");
        if(msg.sender == guardian){
            require(newMaxLossWithdrawBps <= guardianMaxLossBpsLimit, "Max loss > guardian limit");
        }
        maxLossWithdrawBps = newMaxLossWithdrawBps;
    }

    /**
    * @notice Set limit of the max loss setable by guardian.
    * @param newGuardianMaxLossBpsLimit The maximum loss allowed by basis points 1 = 0.01%
    */
    function setGuardianMaxLossBpsLimit(uint newGuardianMaxLossBpsLimit) external onlyRole(gov){
        require(newGuardianMaxLossBpsLimit <= 10000, "Max loss > 100%");
        guardianMaxLossBpsLimit = newGuardianMaxLossBpsLimit;   
    }
    
    /**
    * @notice Set limit of the supply ceiling
    * @param newSupplyCeiling The new dola supply ceiling of the fed
    */ 
    function setSupplyCeiling(uint newSupplyCeiling) external onlyRole(gov) {
        supplyCeiling = newSupplyCeiling;
    }

    /**
    * @notice Deposits amount of dola tokens into convex
    * @param amount Amount of dola token to deposit into convex
    */
    function expansion(uint amount) external onlyRole(chair){
        require(amount + dolaSupply <= supplyCeiling, "Expansion above ceiling");
        dolaSupply += amount;
        dola.mint(address(this), amount);
        metapoolDeposit(amount, maxLossExpansionBps);
        emit Expansion(amount);
    }

    /**
    * @notice Withdraws an amount of dola token to be burnt, contracting DOLA dolaSupply
    * @dev Be careful when setting maxLoss parameter. There will almost always be some slippage when trading.
    * For example, slippage + trading fees may be incurred when withdrawing from a Curve pool.
    * On the other hand, setting the maxLoss too high, may cause you to be front run by MEV
    * sandwhich bots, making sure your entire maxLoss is incurred.
    * Recommended to always broadcast withdrawl transactions(contraction & takeProfits)
    * through a frontrun protected RPC like Flashbots RPC.
    * @param amountDola The amount of dola tokens to withdraw. Note that more tokens may
    be withdrawn than requested.
    */
    function contraction(uint amountDola) external onlyRole(chair){
        //Calculate how many lp tokens are needed to withdraw the dola
        uint crvLpNeeded = lpForDola(amountDola);
        require(crvLpNeeded <= crvLpSupply(), "Not enough crvLP tokens");

        //Withdraw DOLA from curve pool
        uint dolaWithdrawn = metapoolWithdraw(amountDola, maxLossWithdrawBps);
        require(dolaWithdrawn > 0, "Must contract");
        uint burnAmount = _burnAndPay();
        emit Contraction(burnAmount);
    }

    /**
    * @notice Withdraws every remaining crvLP token. Can take up to maxLossWithdrawBps in loss, compared to dolaSupply.
    * It will still be necessary to call takeProfit to withdraw any potential rewards.
    */
    function contractAll() external onlyRole(chair){
        uint dolaMinOut = dolaSupply * (10_000 - maxLossWithdrawBps) / 10_000;
        crvMetapool.remove_liquidity_one_coin(crvLpSupply(), 0, dolaMinOut);
        uint burnAmount = _burnAndPay();
        emit Contraction(burnAmount);
    }

    function claimOther(address otherReward) external onlyRole(chair){
        require(otherReward != address(dola), "Cant claim dola");
        require(otherReward != address(crvMetapool), "Cant claim crv LP tokens");
        uint rewardBalance = IERC20(otherReward).balanceOf(address(this));
        IERC20(otherReward).transfer(gov, rewardBalance);
        emit ClaimRewards(rewardBalance, otherReward);
    }

    /**
    * @notice Burns amount of dola supply with a maximum of the entire dola supply.
    * @param amount Amount of dola supply to be burnt.
    */
    function burnDolaSupply(uint amount) external {
        if(amount > dolaSupply){
            dola.transferFrom(msg.sender, address(this), dolaSupply);
        } else {
            dola.transferFrom(msg.sender, address(this), amount);
        }
        _burnAndPay();
    }

    /**
    * @notice Burns all dola tokens held by the fed up to the dolaSupply, taking any surplus as profit.
    */
    function _burnAndPay() internal returns(uint burnAmount){
        uint dolaBal = dola.balanceOf(address(this));
        if(dolaBal > dolaSupply){
            uint profit = dolaBal - dolaSupply;
            IERC20(dola).transfer(gov, profit);
            burnAmount = dolaSupply;
            dolaSupply = 0;
        } else {
            burnAmount = dolaBal;
            dolaSupply -= dolaBal;
        }
        IERC20(dola).burn(burnAmount);
    }

    /**
    * @notice Withdraws all owned curve LP tokens to governance.
    * @dev Only to be used in emergency situations and with full consent of governance.
    */
    function emergencyWithdraw() external onlyRole(gov) {
        crvMetapool.transfer(gov, crvMetapool.balanceOf(address(this)));
    }
    
    /**
    * @notice View function for getting crvLP tokens in the contract + convex baseRewardPool
    */
    function crvLpSupply() public view returns(uint){
        return crvMetapool.balanceOf(address(this));
    }
}
