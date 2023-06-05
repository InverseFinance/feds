pragma solidity ^0.8.13;

import "src/MintingFed.sol";

abstract contract LossyFed is MintingFed {
    uint public maxLossExpansionBps;
    uint public maxLossContractionBps;
    uint public maxLossTakeProfitBps;
    uint public maxLossSetableByGuardian = 500;
    address public guardian;
    constructor(address _DOLA,
                address _gov,
                address _chair,
                address _guardian,
                uint _maxLossExpansionBps,
                uint _maxLossContractionBps,
                uint _maxLossTakeProfitBps
    ) MintingFed(_DOLA, _gov, _chair)
    {
        require(_maxLossExpansionBps < 10000, "Expansion max loss too high");
        require(_maxLossContractionBps < 10000, "Contraction max loss too high");
        require(_maxLossTakeProfitBps < 10000, "TakeProfit max loss too high");
        guardian = _guardian;
        maxLossExpansionBps = _maxLossExpansionBps;
        maxLossContractionBps = _maxLossContractionBps;
        maxLossTakeProfitBps = _maxLossTakeProfitBps;
    }

    modifier onlyGuardian {
        require(msg.sender == guardian || msg.sender == gov, "ONLY GOV OR GUARDIAN");
        _;
    }

    function setMaxLossExpansionBps(uint newMaxLossExpansionBps) onlyGov external {
        require(newMaxLossExpansionBps <= 10000, "Max loss above 100%");
        maxLossExpansionBps = newMaxLossExpansionBps;
    }

    function setMaxLossContractionBps(uint newMaxLossContractionBps) onlyGuardian external{
        if(msg.sender == guardian){
            //We limit the max loss a guardian can set, as we only want governance to be able to set a very high maxloss
            require(newMaxLossContractionBps <= maxLossSetableByGuardian, "Above allowed maxloss for chair");
        }
        require(newMaxLossContractionBps <= 10000, "Max loss above 100%");
        maxLossContractionBps = newMaxLossContractionBps;
    }

    function setMaxLossTakeProfitBps(uint newMaxLossTakeProfitBps) onlyGov external {
        require(newMaxLossTakeProfitBps <= 10000, "Max loss above 100%");
        maxLossTakeProfitBps = newMaxLossTakeProfitBps;
    }

    function setMaxLossSetableByGuardian(uint newMaxLossSetableByGuardian) onlyGov external {
        require(newMaxLossSetableByGuardian < 10000, "Max loss above 100%");
        maxLossSetableByGuardian = newMaxLossSetableByGuardian;
    }

    function setGuardian(address newGuardian) onlyGov external {
        guardian = newGuardian;
        emit NewGuardian(newGuardian);
    }
    
    event NewGuardian(address);
}
