pragma solidity ^0.8.13;
import {ICrossDomainMessenger} from "src/drome-fed/interfaces/ICrossDomainMessenger.sol";
contract L1SuperchainGovernable {
    address public governor;
    address public pendingGovernor;
    ICrossDomainMessenger public constant ovmL2CrossDomainMessenger = ICrossDomainMessenger(0x4200000000000000000000000000000000000007);

    error OnlyRole(address role);
    error OnlyGovernor();
    error OnlyPendingGovernor();

    modifier onlyRoleOrGovernor(address l2Role) {
        if (msg.sender == address(ovmL2CrossDomainMessenger)) {
            if (ovmL2CrossDomainMessenger.xDomainMessageSender() != governor) revert OnlyGovernor();
        } else if (msg.sender != l2Role){
            revert OnlyRole(l2Role);
        }
        _;
    }

    modifier onlyGovernor() {
        if(msg.sender != address(ovmL2CrossDomainMessenger) || ovmL2CrossDomainMessenger.xDomainMessageSender() != governor) revert OnlyGovernor();
        _;
    }

    modifier onlyPendingGovernor() {
        if(msg.sender != address(ovmL2CrossDomainMessenger) || ovmL2CrossDomainMessenger.xDomainMessageSender() != pendingGovernor) revert OnlyPendingGovernor();
        _;
    }

    /**
     * @notice Method for `gov` to change `pendingGov` address
     * @param _pendingGovernor L1 Governor contract to be set as `pendingGovernor`
     */
    function setPendingGov(address _pendingGovernor) onlyGovernor external {
        pendingGovernor = _pendingGovernor;
    }

    /**
     * @notice Method for `pendingGov` to claim `gov` role.
     */
    function claimGov() external onlyPendingGovernor() {
        governor = pendingGovernor;
        pendingGovernor = address(0);
    }


}
