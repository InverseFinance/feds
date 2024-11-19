pragma solidity ^0.8.20;

import {FedCCTPProxyMainnetTest, MockExchangeProxy, IFedCCTP} from "test/FedCCTPProxyMainnetTest.sol";
import {OptiFedCCTP} from "src/velo-fed/OptiFedCCTP.sol";

contract OptiFedCCTPTest is FedCCTPProxyMainnetTest {
    OptiFedCCTP optiFedCCTP;
    address l1OptiBridgeAddr = 0x99C9fc46f92E8a1c0deC1b1747d010903E884bE1;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"), 19512248);

        exchangeProxy = new MockExchangeProxy(address(DOLA));
        l1BridgeAddr = l1OptiBridgeAddr;

        fed = IFedCCTP(
            address(
                new OptiFedCCTP(
                    gov,
                    chair,
                    address(0x69),
                    address(exchangeProxy),
                    25,
                    10
                )
            )
        );

        initialize();
    }

    function testL1_changeVeloFarmer() public {
        vm.prank(gov);
        OptiFedCCTP(address(fed)).changeVeloFarmer(user);
        assertEq(OptiFedCCTP(address(fed)).veloFarmer(), user);
    }
    function testL1_changeVeloFarmer_fail_whenCalledByNonGov() public {
        vm.prank(chair);
        vm.expectRevert(OptiFedCCTP.OnlyGov.selector);
        OptiFedCCTP(address(fed)).changeVeloFarmer(user);
    }
}
