//SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.21;

interface IDromeFarmer {
    function withdrawLiquidity(uint dolaAmount) external;
    function withdrawLiquidityAndSwapToDOLA(uint dolaAmount) external;
    function withdrawToL1BaseFed(uint dolaAmount) external;
    function withdrawToL1BaseFedNative(uint dolaAmount, uint usdcAmount) external;
    function withdrawToL1BaseFedNative(uint usdcAmount) external;
    function withdrawToL1BaseFedBridged(uint usdcAmount) external;
    function withdrawTokensToL1(address l2Token, uint amount) external;
    function swapUSDCtoDOLA(uint usdcAmount) external;
    function swapUSDCNativetoDOLA(uint usdcAmount) external;
    function swapDOLAtoUSDC(uint dolaAmount) external;
    function swapDOLAtoUSDCNative(uint dolaAmount) external;
    function swapUSDCtoUSDCNative(uint usdcAmount) external;
    function swapUSDCNativeToUSDC(uint usdcAmount) external;
    function resign() external;
}

contract ChairIntermediary {
    IDromeFarmer public dromeFarmer;
    address public chair;
    
    constructor(address _chair, address _dromeFarmer){
        chair = _chair;
        dromeFarmer = IDromeFarmer(_dromeFarmer);
    }

    modifier onlyChair() {
        require(msg.sender == chair, "ONLY MSG.SENDER");
        _;
    }

    function withdrawLiquidity(uint dolaAmount) external onlyChair {
        dromeFarmer.withdrawLiquidity(dolaAmount);
    }
 
    function withdrawLiquidityAndSwapToDOLA(uint dolaAmount) external onlyChair {
        dromeFarmer.withdrawLiquidityAndSwapToDOLA(dolaAmount);
    }

    function withdrawToL1BaseFed(uint dolaAmount) external onlyChair {
        dromeFarmer.withdrawToL1BaseFed(dolaAmount);
    }

    function withdrawToL1BaseFedNative(uint dolaAmount, uint usdcAmount) external onlyChair {
        dromeFarmer.withdrawToL1BaseFedNative(dolaAmount, usdcAmount);
    }

    function withdrawToL1BaseFedNative(uint usdcAmount) external onlyChair {
        dromeFarmer.withdrawToL1BaseFedNative(usdcAmount);
    }

    function withdrawToL1BaseFedBridged(uint usdcAmount) external onlyChair {
        dromeFarmer.withdrawToL1BaseFedBridged(usdcAmount);
    }

    function withdrawTokensToL1(address l2Token, uint amount) external onlyChair{
        dromeFarmer.withdrawTokensToL1(l2Token, amount);
    }

    function swapUSDCtoDOLA(uint usdcAmount) external onlyChair {
        dromeFarmer.swapUSDCtoDOLA(usdcAmount);
    }

    function swapUSDCNativetoDOLA(uint usdcAmount) external onlyChair {
        dromeFarmer.swapUSDCNativetoDOLA(usdcAmount);
    }

    function swapDOLAtoUSDC(uint dolaAmount) external onlyChair {
        dromeFarmer.swapDOLAtoUSDC(dolaAmount);
    }

    function swapDOLAtoUSDCNative(uint dolaAmount) external onlyChair {
        dromeFarmer.swapDOLAtoUSDCNative(dolaAmount);
    }

    function swapUSDCtoUSDCNative(uint usdcAmount) external onlyChair {
        dromeFarmer.swapUSDCtoUSDCNative(usdcAmount);
    }

    function swapUSDCNativeToUSDC(uint usdcAmount) external onlyChair {
        dromeFarmer.swapUSDCNativeToUSDC(usdcAmount);
    }

    function resign() external onlyChair {
        dromeFarmer.resign();
    }
}
