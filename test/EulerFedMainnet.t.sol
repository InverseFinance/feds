pragma solidity ^0.8.16;

import "ds-test/test.sol";
import "forge-std/Vm.sol";
import "src/euler-fed/EulerFed.sol";

contract EulerFedTest is DSTest {
    Vm internal constant vm = Vm(HEVM_ADDRESS);
    EToken eDola;
    address dola;
    address gov = address(0xA);
    address chair = address(0xB);

    function setUp(){
    
    }

}
