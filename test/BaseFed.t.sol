pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "src/BaseFed.sol";

contract MockToken {
    mapping(address => uint) public balanceOf;
    
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
    }


}

contract BaseFedImplementation is BaseFed{
    constructor(address dola, address gov, address chair) BaseFed(dola, gov, chair){}

    function _repayDebt(uint amount) internal override{
        debt -= amount;
    }

    function takeProfit(uint flag) external override{}  

    function increaseDebt(uint amount) external{
        debt += amount;
    }
}

contract BaseFedTest is Test{

    address user = address(0xA);
    address dola = 0x8F97cCA30Dbe80e7a8B462F1dD1a51C32accDfC8;
    address gov = 0x8F97cCA30Dbe80e7a8B462F1dD1a51C32accDfC8;
    address chair = 0x8F97cCA30Dbe80e7a8B462F1dD1a51C32accDfC8;
    BaseFedImplementation fed;

    function setUp() public {
        dola = address(new MockToken());
        fed = new BaseFedImplementation(dola, gov, chair);
    }

    function testSetPendingGov_success_WhenCalledByGov() external{
        vm.prank(gov);
        fed.setPendingGov(user);
        assertEq(fed.pendingGov(), user, "Pending gov not eq user");
    }

    function testSetPendingGov_fails_WhenCalledByNonGov(address caller) external{
        vm.assume(caller != fed.gov());
        vm.prank(caller);
        vm.expectRevert("NOT GOV");
        fed.setPendingGov(user);
    }

    function testClaimPendingGov_success_WhenClaimedByPendingGov() external{
        vm.prank(gov);
        fed.setPendingGov(user);
        assertEq(fed.pendingGov(), user, "Pending not user");
        vm.prank(user);
        fed.claimPendingGov();
        assertEq(fed.gov(), user, "Gov not user");
    }

    function testClaimPendingGov_fails_WhenClaimedByNonPendingGov(address caller) external{
        vm.assume(user != caller);
        vm.prank(gov);
        fed.setPendingGov(user);
        vm.prank(caller);
        vm.expectRevert("NOT PENDING GOV");
        fed.claimPendingGov();
    }

    function testSetChair_success_WhenCalledByGov() external {
        vm.prank(gov);
        fed.setChair(user);
        assertEq(fed.chair(), user, "User not chair");
    }

    function testSetChair_fails_WhenCalledByNonGov(address caller) external {
        vm.assume(caller != fed.gov());
        vm.prank(caller);
        vm.expectRevert("NOT GOV");
        fed.setChair(user);
    }

    function testSetMigrator_success_WhenCalledByGov() external {
        vm.prank(gov);
        fed.setMigrator(user);
        assertEq(fed.migrator(), user, "User not migrator");
    }

    function testSetMigrator_fails_WhenCalledByNonGov(address caller) external {
        vm.assume(caller != fed.gov());
        vm.prank(caller);
        vm.expectRevert("NOT GOV");
        fed.setMigrator(user);
    }

    function testResign_SetsChairToZero_WhenCalledByChair() external {
        vm.prank(chair);
        fed.resign();
        assertEq(fed.chair(), address(0), "Fed chair not zero address");
    }

    function testResign_Fails_WhenCalledByNonChair(address caller) external {
        vm.assume(caller != fed.chair() && caller != fed.gov());
        vm.prank(caller);
        vm.expectRevert("NOT PERMISSIONED");
        fed.resign();
    }

    function testSweep_TransfersAllToGov_WhenCalledByGov() external {
        MockToken mockToken = new MockToken();
        mockToken.mint(address(fed), 1 ether);
        assertEq(mockToken.balanceOf(gov), 0);
        vm.prank(gov);
        fed.sweep(address(mockToken));
        assertEq(mockToken.balanceOf(gov), 1 ether, "Gov did not receive swept tokens");
    }

    function testSweep_Fails_WhenCalledByNonGov(address caller) external {
        vm.assume(caller != gov);
        MockToken mockToken = new MockToken();
        mockToken.mint(address(fed), 1 ether);
        assertEq(mockToken.balanceOf(gov), 0);
        vm.prank(caller);
        vm.expectRevert("NOT GOV");
        fed.sweep(address(mockToken));
        assertEq(mockToken.balanceOf(gov), 0, "Gov received ether");
    }

    function testRepayDebt_TransfersDolaToContract_WhenCalledByUserWithDolaTokens() external {
        MockToken(dola).mint(user, 1 ether);
        fed.increaseDebt(1 ether);
        vm.prank(user);
        fed.repayDebt(1 ether);
        assertEq(fed.debt(), 0);
        assertEq(MockToken(dola).balanceOf(address(fed)), 1 ether);
    }

    function testRepayDebt_FailsWhenRepayingMoreThanDebt_WhenCalledByUserWithDolaTokens() external {
        MockToken(dola).mint(user, 2 ether);
        fed.increaseDebt(1 ether);
        vm.prank(user);
        vm.expectRevert("BURN HIGHER THAN DEBT");
        fed.repayDebt(2 ether);
    }

}
