pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "src/MintingFed.sol";

contract MockToken {
    mapping(address => uint) public balanceOf;
    uint public totalSupply;
    
    function transfer(address to, uint amount) external returns(bool){
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint amount) external returns(bool){
        balanceOf[from] -= amount;
        balanceOf[to] += amount;       
        return true;
    }

    function mint(address to, uint amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function burn(uint amount) external {
        balanceOf[msg.sender] -= amount;
        totalSupply -= amount;
    }
}

contract MintingFedImplementation is MintingFed{
    uint lossFactor = 1 ether;
    constructor(address dola, address gov, address chair) MintingFed(dola, gov, chair){

    }

    function setLossFactor(uint newLossFactor) external {
        lossFactor = newLossFactor;
    }


    function _deposit(uint dolaAmount) internal override returns(uint claimsReceived){
        return dolaAmount * lossFactor / 1 ether;
    }

    function _withdraw(uint dolaAmount) internal override returns(uint claimsUsed, uint dolaReceived){
        return (dolaAmount, dolaAmount * lossFactor / 1 ether);
    }

    function _withdrawAll() internal override returns(uint claimsUSed, uint dolaReceived){
        return(claims, claims * lossFactor / 1 ether);
    }

    function takeProfit(uint flag) override external{}

    function claimsSupply() public view override returns(uint claims){return claims;}

}

contract MintingFedTest is Test{

    address user = address(0xA);
    MockToken dola;
    address gov = 0x8F97cCA30Dbe80e7a8B462F1dD1a51C32accDfC8;
    address chair = 0x8F97cCA30Dbe80e7a8B462F1dD1a51C32accDfC8;
    MintingFedImplementation fed;

    function setUp() public {
        vm.chainId(1);
        dola = new MockToken();
        fed = new MintingFedImplementation(address(dola), gov, chair);
    }

    function testExpansion_Succeeds_WhenCalledByFedChair(uint128 expansion) external {
        uint totalSupplyBefore = dola.totalSupply();
        uint claimsBefore = fed.claims();
        vm.prank(chair);
        fed.expansion(uint(expansion));
        assertEq(totalSupplyBefore + uint(expansion), dola.totalSupply(), "Total supply didn't increase");
        assertEq(fed.debt(), uint(expansion), "Fed debt did not increase by expansion");
        if(expansion > 0){
            assertGt(fed.claims(), claimsBefore, "Fed claims did not increase");
        }
    }

    function testExpansion_Succeeds_WhenCalledTwice(uint128 expansion) external {
        uint totalSupplyBefore = dola.totalSupply();
        uint claimsBefore = fed.claims();
        vm.startPrank(chair);
        fed.expansion(uint(expansion));
        fed.expansion(uint(expansion));
        vm.stopPrank();
        assertEq(totalSupplyBefore + uint(expansion)*2, dola.totalSupply(), "Total supply didn't increase");
        assertEq(fed.debt(), uint(expansion)*2, "Fed debt did not increase by expansion");
        if(expansion > 0){
            assertGt(fed.claims(), claimsBefore, "Fed claims did not increase");
        }
    }

    function testExpansion_Fails_WhenCalledByNonFedChair(address caller) external {
        vm.assume(caller != chair && caller != gov);
        vm.prank(caller);
        vm.expectRevert("NOT PERMISSIONED");
        fed.expansion(1 ether);
    }

    function testContraction_Succeeds_WhenCalledByFedChair(uint128 expansion, uint128 contraction) external {
        vm.assume(expansion >= contraction);
        uint totalSupplyBefore = dola.totalSupply();
        uint claimsBefore = fed.claims();
        vm.startPrank(chair);
        fed.expansion(uint(expansion));
        uint claimsAfterExpansion = fed.claims();
        fed.contraction(uint(contraction));
        assertEq(totalSupplyBefore + uint(expansion - contraction), dola.totalSupply(), "Total supply didn't increase");
        assertEq(fed.debt(), uint(expansion - contraction), "Fed debt did not increase by expansion");
        if(expansion - contraction > 0){
            assertGt(fed.claims(), claimsBefore, "Fed claims did not increase");
        }
        if(contraction > 0){
            assertLt(fed.claims(), claimsAfterExpansion, "Fed claims did not decrease with contraction");
        }
    }

    function testContraction_Fails_WhenCalledByNonFedChair(address caller) external {
        vm.assume(caller != chair && caller != gov);
        vm.prank(chair);
        fed.expansion(1 ether);
        vm.prank(caller);
        vm.expectRevert("NOT PERMISSIONED");
        fed.contraction(1 ether);
    }
}
