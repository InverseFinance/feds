pragma solidity ^0.8.20;

import {FedCCTPProxyMainnetTest, MockExchangeProxy, IFedCCTP} from "test/FedCCTPProxyMainnetTest.sol";
import {BaseFedCCTP} from "src/velo-fed/BaseFedCCTP.sol";

contract BaseFedCCTPTest is FedCCTPProxyMainnetTest {
    BaseFedCCTP baseFedCCTP;
    address l1BaseBridgeAddr = 0x3154Cf16ccdb4C6d922629664174b904d80F2C35;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"), 19512248);

        exchangeProxy = new MockExchangeProxy(address(DOLA));
        l1BridgeAddr = l1BaseBridgeAddr;

        fed = IFedCCTP(
            address(
                new BaseFedCCTP(
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
        BaseFedCCTP(address(fed)).changeAeroFarmer(user);
        assertEq(BaseFedCCTP(address(fed)).aeroFarmer(), user);
    }
    function testL1_changeVeloFarmer_fail_whenCalledByNonGov() public {
        vm.prank(chair);
        vm.expectRevert(BaseFedCCTP.OnlyGov.selector);
        BaseFedCCTP(address(fed)).changeAeroFarmer(user);
    }
}
