pragma solidity ^0.8.16;

import "src/interfaces/IERC20.sol";

interface EToken is IERC20 {
    function underlyingAsset() external returns (address);
    function convertUnderlyingToBalance(uint underlyingAmount) external view returns (uint);
    function reserveBalance() external view returns (uint);
    function deposit(uint subAccountId, uint amount) external;
    function withdraw(uint subAccountId, uint amount) external;
}

contract EulerFed {

    address public gov;
    address public chair;
    IERC20 public dola;
    EToken public eDola;
    uint public dolaSupply;

    event expansionEvent(uint);
    event contractionEvent(uint);
    
    constructor(address gov_, address chair_, address dola_, address eDola_){
        eDola = EToken(eDola_);
        dola = IERC20(dola_);
        gov = gov_;
        chair = chair_;
        require(eDola.underlyingAsset() == dola_, "Wrong EToken or Underlying Asset");
        dola.approve(eDola_, type(uint).max); 
    }

    function expansion(uint dolaAmount) public {
        require(msg.sender == chair);
        dola.mint(address(this), dolaAmount);
        dolaSupply += dolaSupply;
        eDola.deposit(0, dola.balanceOf(address(this)));
        require(dola.balanceOf(address(this)) == 0, "Deposit failed");
        
        emit expansionEvent(dolaAmount);
    }

    function contraction(uint dolaAmount) public {
        require(msg.sender == chair);
        require(dolaAmount <= dolaSupply, "Can't burn profits");
        uint withdrawAmount = eDola.convertUnderlyingToBalance(dolaAmount);
        eDola.withdraw(0, withdrawAmount);
        dolaSupply -= dolaAmount;
        dola.burn(dolaAmount);
        
        emit contractionEvent(dolaAmount);
    }

    function contractAllAvailable() public {
        require(msg.sender == chair);
        if(eDola.reserveBalance() <= eDola.balanceOf(address(this))){
            eDola.withdraw(0, eDola.reserveBalance());
        } else {
            eDola.withdraw(0, eDola.balanceOf(address(this)));
        }
        if(dola.balanceOf(address(this)) > dolaSupply){
            dola.transfer(gov, dola.balanceOf(address(this)) - dolaSupply);
            dola.burn(dolaSupply);
            emit contractionEvent(dolaSupply);
            dolaSupply = 0;
        } else {
            emit contractionEvent(dola.balanceOf(address(this)));
            dolaSupply -= dola.balanceOf(address(this));
            dola.burn(dola.balanceOf(address(this)));
        }
    }

    function takeProfit() public {
        uint balance = eDola.balanceOf(address(this));
        uint needed = eDola.convertUnderlyingToBalance(dolaSupply);
        if(balance > needed){
            eDola.withdraw(0, balance - needed);
            dola.transfer(gov, dola.balanceOf(address(this)));
        }
    }

    /**
    @notice Method for gov to change gov address
    */
    function changeGov(address newGov_) public {
        require(msg.sender == gov, "ONLY GOV");
        gov = newGov_;
    }

    /**
    @notice Method for gov to change the chair
    */
    function changeChair(address newChair_) public {
        require(msg.sender == gov, "ONLY GOV");
        locker.delegate(newChair_);
        chair = newChair_;
    }

    /**
    @notice Method for current chair of the Yearn FED to resign
    */
    function resign() public {
        require(msg.sender == chair, "ONLY CHAIR");
        chair = address(0);
    }
}
