pragma solidity ^0.8.13;

import "ds-test/test.sol";
import "forge-std/Vm.sol";
import "src/aura-fed/BalancerAdapter.sol";
import "src/interfaces/IERC20.sol";

interface IMintable is IERC20 {
    function addMinter(address) external;
}

contract Swapper is BalancerComposableStablepoolAdapter {
    constructor(bytes32 poolId_, address dola_, address vault_, address bpt_) BalancerComposableStablepoolAdapter(poolId_, dola_, vault_, bpt_){}

    function swapExact(address assetIn, address assetOut, uint amount) public{
        swapExactIn(assetIn, assetOut, amount, 1);
    }
}

contract BalancerTest is DSTest{
    Vm internal constant vm = Vm(HEVM_ADDRESS);
    IMintable dola = IMintable(0x865377367054516e17014CcdED1e7d814EDC9ce4);
    address bbausd = 0xA13a9247ea42D743238089903570127DdA72fE44;
    IERC20 bpt = IERC20(0x5b3240B6BE3E7487d61cd1AFdFC7Fe4Fa1D81e64);
    address vault = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address minter = address(0xB);
    address gov = address(0x926dF14a23BE491164dCF93f4c468A50ef659D5B);
    bytes32 poolId = bytes32(0x5b3240b6be3e7487d61cd1afdfc7fe4fa1d81e6400000000000000000000037b);
    address holder = 0x4D2F01D281Dd0b98e75Ca3E1FdD36823B16a7dbf;
    Swapper swapper;

    function setUp() public {
        swapper = new Swapper(poolId, address(dola), vault,address(bpt));
        vm.prank(gov);
        dola.addMinter(minter);
    }

    function testManipulate_getRate_when_AddingAndRemovingLP() public {
       uint bptNeededBefore = swapper.bptNeededForDola(1 ether); 
       vm.prank(minter);
       dola.mint(address(swapper), 1000_000_000 ether);
       swapper.swapExact(address(dola), address(bpt), 1000_000_000 ether);
       uint bptNeededAfter = swapper.bptNeededForDola(1 ether);
       assertGt(bptNeededBefore * 10000 / 9990, bptNeededAfter);
       assertLt(bptNeededBefore * 9990 / 10000, bptNeededAfter);
       swapper.swapExact(address(bpt), address(dola), bpt.balanceOf(address(swapper)));
       uint bptNeededAfterAfter = swapper.bptNeededForDola(1 ether);
       assertGt(bptNeededBefore * 10000 / 9990, bptNeededAfterAfter);
       assertLt(bptNeededBefore * 9990 / 10000, bptNeededAfterAfter);
       emit log_uint(bptNeededBefore);
       emit log_uint(bptNeededAfter);
       emit log_uint(bptNeededAfterAfter);
    }

    function testManipulate_getRate_when_TradingTokens() public {
       uint bptNeededBefore = swapper.bptNeededForDola(1 ether); 
       vm.prank(minter);
       dola.mint(address(swapper), 1000_000_000 ether);
       swapper.swapExact(address(dola), address(bbausd), 10_000_000 ether);
       uint bptNeededAfter = swapper.bptNeededForDola(1 ether);
       assertGt(bptNeededBefore * 10000 / 9990, bptNeededAfter);
       assertLt(bptNeededBefore * 9990 / 10000, bptNeededAfter);
       swapper.swapExact(address(bbausd), address(dola), IERC20(bbausd).balanceOf(address(swapper)));
       uint bptNeededAfterAfter = swapper.bptNeededForDola(1 ether);
       assertGt(bptNeededBefore * 10000 / 9990, bptNeededAfterAfter);
       assertLt(bptNeededBefore * 9990 / 10000, bptNeededAfterAfter);
       emit log_uint(bptNeededBefore);
       emit log_uint(bptNeededAfter);
       emit log_uint(bptNeededAfterAfter);   
    }
}

