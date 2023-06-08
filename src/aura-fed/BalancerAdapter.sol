pragma solidity ^0.8.13;

import "src/interfaces/balancer/IVault.sol";
import "src/interfaces/IERC20.sol";

interface IBPT is IERC20{
    function getPoolId() external view returns (bytes32);
    function getRate() external view returns (uint256);
}

contract BalancerComposableStablepoolAdapter {
    
    uint constant BPS = 10_000;
    bytes32 public poolId;
    IERC20 constant _DOLA = IERC20(0x865377367054516e17014CcdED1e7d814EDC9ce4);
    IBPT public BPT;
    IVault constant VAULT = IVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    IVault.FundManagement fundMan;
    
    //Use internal init instead of constructor due to stack too deep
    function init(address _bpt) internal{
        BPT = IBPT(_bpt);
        poolId = BPT.getPoolId();
        _DOLA.approve(address(VAULT), type(uint).max);
        BPT.approve(address(VAULT), type(uint).max);
        fundMan.sender = address(this);
        fundMan.fromInternalBalance = false;
        fundMan.recipient = payable(address(this));
        fundMan.toInternalBalance = false;
    }
    
    /**
    @notice Swaps exact amount of assetIn for asseetOut through a balancer pool. Output must be higher than minOut
    @dev Due to the unique design of Balancer ComposableStablePools, where BPT are part of the swappable balance, we can just swap _DOLA directly for BPT
    @param assetIn Address of the asset to trade an exact amount in
    @param assetOut Address of the asset to trade for
    @param amount Amount of assetIn to trade
    @param minOut minimum amount of assetOut to receive
    */
    function swapExactIn(address assetIn, address assetOut, uint amount, uint minOut) internal {
        IVault.SingleSwap memory swapStruct;

        //Populate Single Swap struct
        swapStruct.poolId = poolId;
        swapStruct.kind = IVault.SwapKind.GIVEN_IN;
        swapStruct.assetIn = IAsset(assetIn);
        swapStruct.assetOut = IAsset(assetOut);
        swapStruct.amount = amount;
        //swapStruct.userData: User data can be left empty

        VAULT.swap(swapStruct, fundMan, minOut, block.timestamp+1);
    }

    /**
    @notice Deposit an amount of _DOLA into balancer, getting balancer pool tokens in return
    @param dolaAmount Amount of _DOLA to buy BPTs for
    @param maxSlippage Maximum amount of value that can be lost in basis points, assuming _DOLA = 1$
    */
    function _addLiquidity(uint dolaAmount, uint maxSlippage) internal returns(uint){
        uint initialBal = BPT.balanceOf(address(this));
        uint BPTWanted = bptNeededForDola(dolaAmount);
        uint minBptOut = BPTWanted - BPTWanted * maxSlippage / BPS;
        swapExactIn(address(_DOLA), address(BPT), dolaAmount, minBptOut);
        uint BPTOut =  BPT.balanceOf(address(this)) - initialBal;
        return BPTOut;
    }
    
    /**
    @notice Withdraws an amount of value close to dolaAmount
    @dev Will rarely withdraw an amount equal to dolaAmount, due to slippage.
    @param dolaAmount Amount of _DOLA the withdrawer wants to withdraw
    @param maxSlippage Maximum amount of value that can be lost in basis points, assuming _DOLA = 1$
    */
    function _removeLiquidity(uint dolaAmount, uint maxSlippage) internal returns(uint){
        uint initialBal = _DOLA.balanceOf(address(this));
        uint BPTNeeded = bptNeededForDola(dolaAmount);
        uint minDolaOut = dolaAmount - dolaAmount * maxSlippage / BPS;
        swapExactIn(address(BPT), address(_DOLA), BPTNeeded, minDolaOut);
        uint dolaOut = _DOLA.balanceOf(address(this)) - initialBal;
        return dolaOut;
    }

    /**
    @notice Withdraws all BPT in the contract
    @dev Will rarely withdraw an amount equal to dolaAmount, due to slippage.
    @param maxSlippage Maximum amount of value that can be lost in basis points, assuming _DOLA = 1$
    */
    function _removeAllLiquidity(uint maxSlippage) internal returns(uint){
        uint BPTBal = BPT.balanceOf(address(this));
        uint expectedDolaOut = BPTBal * BPT.getRate() / 10**18;
        uint minDolaOut = expectedDolaOut - expectedDolaOut * maxSlippage / BPS;
        swapExactIn(address(BPT), address(_DOLA), BPTBal, minDolaOut);
        return _DOLA.balanceOf(address(this));
    }

    /**
    @notice Get amount of BPT equal to the value of dolaAmount, assuming Dola = 1$
    @dev Uses the getRate() function of the balancer pool to calculate the value of the dolaAmount
    @param dolaAmount Amount of _DOLA to get the equal value in BPT.
    @return Uint representing the amount of BPT the dolaAmount should be worth.
    */
    function bptNeededForDola(uint dolaAmount) public view returns(uint) {
        return dolaAmount * 10**18 / BPT.getRate();
    }
}
