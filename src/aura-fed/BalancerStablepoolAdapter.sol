pragma solidity ^0.8.13;

import "src/interfaces/balancer/IVault.sol";
import "src/interfaces/IERC20.sol";

interface IBPT is IERC20{
    function getPoolId() external view returns (bytes32);
    function getRate() external view returns (uint256);
}

interface IBalancerHelper{
    function queryExit(bytes32 poolId, address sender, address recipient, IVault.ExitPoolRequest memory erp) external returns (uint256 BPTIn, uint256[] memory amountsOut);
    function queryJoin(bytes32 poolId, address sender, address recipient, IVault.JoinPoolRequest memory jrp) external returns (uint256 BPTOut, uint256[] memory amountsIn);
}

contract BalancerStablepoolAdapter {

    uint constant BPS = 10_000;
    bytes32  poolId;
    IERC20 constant dola = IERC20(0x865377367054516e17014CcdED1e7d814EDC9ce4);
    IERC20 constant usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IBPT BPT;
    IVault constant vault = IVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    IAsset[] assets = new IAsset[](0);
    uint dolaIndex = type(uint).max;

    function init( address _BPT) internal{
        BPT = IBPT(_BPT);
        poolId = BPT.getPoolId();
        dola.approve(address(vault), type(uint).max);
        BPT.approve(address(vault), type(uint).max);
        (address[] memory tokens,,) = vault.getPoolTokens(poolId);
        for(uint i; i<tokens.length; i++){
            assets.push(IAsset(address(tokens[i])));
            if(address(tokens[i]) == address(dola)){
                dolaIndex = i;
            }
        }
        require(dolaIndex < type(uint).max, "Underlying token not found");
    }

    function getUserDataExactInDola(uint amountIn) internal view returns(bytes memory) {
        uint[] memory amounts = new uint[](assets.length);
        amounts[dolaIndex] = amountIn;
        return abi.encode(1, amounts, 0);
    }

    function getUserDataExactInBPT(uint amountIn) internal view returns(bytes memory) {
        uint[] memory amounts = new uint[](assets.length);
        amounts[dolaIndex] = amountIn;
        return abi.encode(0, amounts);
    }

    function getUserDataCustomExit(uint exactDolaOut, uint maxBPTin) internal view returns(bytes memory) {
        uint[] memory amounts = new uint[](assets.length);
        amounts[dolaIndex] = exactDolaOut;
        return abi.encode(2, amounts, maxBPTin);
    }

    function getUserDataExitExact(uint exactBptIn) internal view returns(bytes memory) {
        return abi.encode(0, exactBptIn, dolaIndex);
    }

    function createJoinPoolRequest(uint dolaAmount) internal view returns(IVault.JoinPoolRequest memory){
        IVault.JoinPoolRequest memory jpr;
        jpr.assets = assets;
        jpr.maxAmountsIn = new uint[](assets.length);
        jpr.maxAmountsIn[dolaIndex] = dolaAmount;
        jpr.userData = getUserDataExactInDola(dolaAmount);
        jpr.fromInternalBalance = false;
        return jpr;
    }

    function createExitPoolRequest(uint index, uint dolaAmount, uint maxBPTin) internal view returns (IVault.ExitPoolRequest memory){
        IVault.ExitPoolRequest memory epr;
        epr.assets = assets;
        epr.minAmountsOut = new uint[](assets.length);
        epr.minAmountsOut[index] = dolaAmount;
        epr.userData = getUserDataCustomExit(dolaAmount, maxBPTin);
        epr.toInternalBalance = false;
        return epr;
    }

    function createExitExactPoolRequest(uint index, uint BPTAmount, uint minDolaOut) internal view returns (IVault.ExitPoolRequest memory){
        IVault.ExitPoolRequest memory epr;
        epr.assets = assets;
        epr.minAmountsOut = new uint[](assets.length);
        epr.minAmountsOut[index] = minDolaOut;
        epr.userData = getUserDataExitExact(BPTAmount);
        epr.toInternalBalance = false;
        return epr;
    }


    function _addLiquidity(uint dolaAmount, uint maxSlippage) internal returns(uint){
        uint initial = BPT.balanceOf(address(this));
        uint BPTWanted = bptNeededForDola(dolaAmount);
        vault.joinPool(poolId, address(this), address(this), createJoinPoolRequest(dolaAmount));
        uint BPTOut =  BPT.balanceOf(address(this)) - initial;
        require(BPTOut > BPTWanted - BPTWanted * maxSlippage / BPS, "Insufficient BPT received");
        return BPTOut;
    }

    function _removeLiquidity(uint dolaAmount, uint maxSlippage) internal returns(uint){
        uint initial = dola.balanceOf(address(this));
        uint BPTNeeded = bptNeededForDola(dolaAmount);
        uint minDolaOut = dolaAmount - dolaAmount * maxSlippage / BPS;
        vault.exitPool(poolId, address(this), payable(address(this)), createExitExactPoolRequest(dolaIndex, BPTNeeded, minDolaOut));
        uint dolaOut = dola.balanceOf(address(this)) - initial;
        return dolaOut;
    }

    function _removeAllLiquidity(uint maxSlippage) internal returns(uint){
        uint BPTBal = BPT.balanceOf(address(this));
        uint expectedDolaOut = BPTBal * BPT.getRate() / 10**18;
        uint minDolaOut = expectedDolaOut - expectedDolaOut * maxSlippage / BPS;
        vault.exitPool(poolId, address(this), payable(address(this)), createExitExactPoolRequest(dolaIndex, BPTBal, minDolaOut));
        return dola.balanceOf(address(this));
    }

    function bptNeededForDola(uint dolaAmount) public view returns(uint) {
        return dolaAmount * 10 ** 18 / BPT.getRate();
    }
}
