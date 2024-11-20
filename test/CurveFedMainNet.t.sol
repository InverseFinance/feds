// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.11;

import "forge-std/Test.sol";
import "src/curve-fed/CurveFed.sol";
import "src/interfaces/curve/IMetaPool.sol";
import "src/interfaces/curve/IZapDepositor3pool.sol";
import "src/interfaces/IERC20.sol";

interface IMinted is IERC20 {
    function addMinter(address minter_) external;
    function removeMinter(address minter_) external;
    function mint(address to, uint amount) external;
}

contract CurveFedTest is Test {
    IMetaPool public crvPool = IMetaPool(0xE57180685E3348589E9521aa53Af0BCD497E884d);
    CurveFed public curveFed;
    IMinted public dola = IMinted(0x865377367054516e17014CcdED1e7d814EDC9ce4);
    IERC20 public usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 public fraxBP = IERC20(0x3175Df0976dFA876431C2E9eE6Bc45b65d3473CC);
    address public gov = 0x926dF14a23BE491164dCF93f4c468A50ef659D5B;
    address public chair = address(0xB);
    address public guardian = address(0xC);
    address public dolaFaucet = address(0xF);
    uint public maxLossLimitGuardian = 1000;
    uint public maxLossExpansionBps = 100;
    uint public maxLossWithdrawBps = 100;

    function setUp() public {
        curveFed = new CurveFed(
            address(crvPool),
            chair,
            gov,
            guardian,
            maxLossExpansionBps,
            maxLossWithdrawBps,
            maxLossLimitGuardian
        );
        vm.startPrank(gov);
        dola.addMinter(address(curveFed));
        dola.addMinter(dolaFaucet);
        vm.stopPrank();
        vm.label(0xAA5A67c256e27A5d80712c51971408db3370927D, "DOLA-3CRV");
        vm.label(0x865377367054516e17014CcdED1e7d814EDC9ce4, "dola");
        vm.label(0x62B9c7356A2Dc64a1969e19C23e4f579F9810Aa7, "crv");
        vm.label(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B, "cvx");
    }

    function testExpansion_succeed_whenExpandedWithinAcceptableSlippage(uint amount) public {
        vm.assume(amount < 1_000_000 * 10**18);
        vm.assume(amount > 10**18);
        uint initialDolaSupply = curveFed.dolaSupply();
        uint initialCrvLpSupply = curveFed.crvLpSupply();
        uint initialDolaTotalSupply = dola.totalSupply();

        vm.prank(chair);
        curveFed.expansion(amount);

        assertEq(initialDolaTotalSupply + amount, dola.totalSupply());
        assertEq(initialDolaSupply + amount, curveFed.dolaSupply());
        assertGt(curveFed.crvLpSupply(), initialCrvLpSupply);
        assertGe(curveFed.crvLpSupply()-initialCrvLpSupply, amount * 10**18 / crvPool.get_virtual_price() * (10_000 - maxLossExpansionBps) / 10_000);
    }

    function testFailExpansion_fail_whenExpandedOutsideAcceptableSlippage() public {
        uint amount = 1_000_000_000 ether;

        vm.prank(chair);
        curveFed.expansion(amount);
    }

    function testFailExpansion_fail_whenExpandingAboveSupplyCeiling() public {
        uint ceiling = 1_000_000 ether;
        vm.prank(gov);
        curveFed.setSupplyCeiling(ceiling);

        vm.prank(chair);
        vm.expectRevert("Expansion above ceiling");
        curveFed.expansion(ceiling+1);
        curveFed.expansion(ceiling/2);
        vm.expectRevert("Expansion above ceiling");
        curveFed.expansion(ceiling/2+2);
    }

    function testBurnDolaSupply() public {
        uint amount = 1_000_000 ether;

        vm.prank(chair);
        curveFed.expansion(amount);

        vm.prank(gov);
        dola.mint(address(this), amount);
        dola.approve(address(curveFed), amount);
        
        uint dolaSupply = curveFed.dolaSupply();
        curveFed.burnDolaSupply(1);
        assertEq(curveFed.dolaSupply(), dolaSupply - 1);
        curveFed.burnDolaSupply(amount);
        assertEq(curveFed.dolaSupply(), 0);
    }


    function testContraction_succeed_whenContractedWithinAcceptableSlippage(uint amount) public {
        vm.assume(amount < 500_000 * 10**18);
        vm.assume(amount > 10**18);
        vm.prank(chair);
        curveFed.expansion(amount*2);
        uint initialDolaSupply = curveFed.dolaSupply();
        uint initialDolaTotalSupply = dola.totalSupply();
        uint initialCrvLpSupply = curveFed.crvLpSupply();

        vm.prank(chair);
        curveFed.contraction(amount);

        //Make sure basic accounting of contraction is correct:
        assertGt(initialCrvLpSupply, curveFed.crvLpSupply(), "");
        assertGt(initialDolaSupply, curveFed.dolaSupply());
        assertGt(initialDolaTotalSupply, dola.totalSupply());
        assertEq(initialDolaTotalSupply - dola.totalSupply(), initialDolaSupply - curveFed.dolaSupply());

        //Make sure maxLoss wasn't exceeded
        assertLe(initialDolaSupply-curveFed.dolaSupply(), amount*10_000/(10_000-maxLossWithdrawBps), "Amount withdrawn exceeds maxloss"); 
        assertLe(initialDolaTotalSupply-dola.totalSupply(), amount*10_000/(10_000-maxLossWithdrawBps), "Amount withdrawn exceeds maxloss");
        uint percentageToWithdraw = initialDolaSupply * 10**18 / amount;
        uint percentageActuallyWithdrawnCrv = initialCrvLpSupply * 10**18 / (initialCrvLpSupply - curveFed.crvLpSupply());
        assertLe(percentageActuallyWithdrawnCrv * (10_000 - maxLossWithdrawBps) / 10_000, percentageToWithdraw, "Too much crvLP spent");
    }

    function testContraction_succeed_whenContractedWithProfit(uint amount) public {
        vm.assume(amount < 1_000_000 * 10**18);
        vm.assume(amount > 10**18);
        vm.prank(chair);
        curveFed.expansion(amount);
        washTrade(5_000_000 ether, 100);
        uint initialDolaSupply = curveFed.dolaSupply();
        uint initialDolaTotalSupply = dola.totalSupply();
        uint initialCrvLpSupply = curveFed.crvLpSupply();
        uint initialGovDola = dola.balanceOf(gov);

        vm.prank(chair);
        curveFed.contraction(amount*100/99);

        //Make sure basic accounting of contraction is correct:
        assertGt(initialCrvLpSupply, curveFed.crvLpSupply(), "Crv LP Supply didn't drop");
        assertEq(initialDolaSupply-amount, curveFed.dolaSupply(), "Internal Dola Supply didn't drop by test amount");
        assertEq(initialDolaTotalSupply, dola.totalSupply()+amount, "Total Dola Supply didn't drop by test amount");
        assertGt(dola.balanceOf(gov), initialGovDola, "Gov dola balance isn't higher");
    }

    function testContractAll_succeed_whenContractedWithinAcceptableSlippage() public {
        vm.prank(chair);
        curveFed.expansion(1000_000 ether);
        uint initialDolaSupply = curveFed.dolaSupply();
        uint initialDolaTotalSupply = dola.totalSupply();
        uint initialCrvLpSupply = curveFed.crvLpSupply();

        vm.prank(chair);
        curveFed.contractAll();

        //Make sure basic accounting of contraction is correct:
        assertLe(initialDolaTotalSupply-initialDolaSupply, dola.totalSupply());

        //Make sure maxLoss wasn't exceeded
        assertLe(initialDolaSupply-curveFed.dolaSupply(), initialDolaSupply*10_000/(10_000-maxLossWithdrawBps), "Amount withdrawn exceeds maxloss"); 
        assertLe(initialDolaTotalSupply-dola.totalSupply(), initialDolaSupply*10_000/(10_000-maxLossWithdrawBps), "Amount withdrawn exceeds maxloss");
        uint percentageToWithdraw = 10**18;
        uint percentageActuallyWithdrawnCrv = initialCrvLpSupply * 10**18 / (initialCrvLpSupply - curveFed.crvLpSupply());
        assertLe(percentageActuallyWithdrawnCrv * (10_000 - maxLossWithdrawBps) / 10_000, percentageToWithdraw, "Too much crvLP spent");
    }

    function testContractAll_succeed_whenContractedWithProfit() public {
        vm.prank(chair);
        curveFed.expansion(100_000 ether);
        washTrade(5000_000 ether, 100);
        uint initialDolaSupply = curveFed.dolaSupply();
        uint initialDolaTotalSupply = dola.totalSupply();
        uint initialGovDola = dola.balanceOf(gov);
        uint initialCrvLpSupply = curveFed.crvLpSupply();

        vm.prank(chair);
        curveFed.contractAll();

        //Make sure basic accounting of contraction is correct:
        assertEq(initialDolaTotalSupply-initialDolaSupply, dola.totalSupply(), "Dola supply was not decreased by initialDolaSupply");
        assertEq(curveFed.dolaSupply(), 0);
        assertEq(curveFed.crvLpSupply(), 0);
        assertGt(initialCrvLpSupply, curveFed.crvLpSupply());
        assertGt(dola.balanceOf(gov), initialGovDola);
    }

    function testFailContraction_fail_whenContractedOutsideAcceptableSlippage() public {
        uint amount = 100_000 ether;

        vm.startPrank(chair);
        curveFed.expansion(amount);
        curveFed.setMaxLossWithdrawBps(0);
        curveFed.contraction(amount);
        vm.stopPrank();
    }

    function testFailContractAll_fail_whenContractedOutsideAcceptableSlippage() public {
        uint amount = 100_000 ether;

        vm.startPrank(chair);
        curveFed.expansion(amount);
        curveFed.setMaxLossWithdrawBps(0);
        curveFed.contractAll();
        vm.stopPrank();
    }

    function testContraction_FailWithUnauthorized_whenCalledByOtherAddress() public {
        vm.prank(dolaFaucet);
        vm.expectRevert("Unauthorized");
        curveFed.contraction(1000);
    }

    function testClaimOther() public {
        uint govUsdc = usdc.balanceOf(gov);
        uint mintAmount = 1_000 ether;
        deal(address(usdc), address(curveFed), mintAmount);
        vm.prank(chair);
        curveFed.claimOther(address(usdc));
        assertEq(usdc.balanceOf(gov), govUsdc + mintAmount);
    }

    function testEmergencyWithdrawn() public {
        vm.prank(chair);
        uint amount = 1_000_000 ether;
        curveFed.expansion(amount);
        uint lpAmount = curveFed.crvLpSupply();
        vm.prank(gov);
        curveFed.emergencyWithdraw();
        assertEq(curveFed.crvLpSupply(), 0, "Fed still has LP tokens");
        assertEq(crvPool.balanceOf(gov), lpAmount, "Gov didn't receive correct amount of LP tokens");
    }

    function testSetMaxLossExpansionBps_succeed_whenCalledByGov() public {
        uint initial = curveFed.maxLossExpansionBps();
        
        vm.prank(gov);
        curveFed.setMaxLossExpansionBps(1);

        assertEq(curveFed.maxLossExpansionBps(), 1);
        assertTrue(initial != curveFed.maxLossExpansionBps());
    }

    function testSetMaxLossWithdrawBps_succeed_whenCalledByGov() public {
        uint initial = curveFed.maxLossWithdrawBps();
        
        vm.prank(gov);
        curveFed.setMaxLossWithdrawBps(1);

        assertEq(curveFed.maxLossWithdrawBps(), 1);
        assertTrue(initial != curveFed.maxLossWithdrawBps());
    }

    function testSetMaxLossWithdrawBps_succeed_whenCalledByGuardian() public {
        uint initial = curveFed.maxLossWithdrawBps();
        
        vm.startPrank(guardian);
        uint guardianLimit = curveFed.guardianMaxLossBpsLimit();
        vm.expectRevert("Max loss > guardian limit");
        curveFed.setMaxLossWithdrawBps(guardianLimit + 1);
        
        curveFed.setMaxLossWithdrawBps(1);

        assertEq(curveFed.maxLossWithdrawBps(), 1);
        assertTrue(initial != curveFed.maxLossWithdrawBps());
    }


    function testSetMaxLossExpansionBps_fail_whenCalledByNonGov() public {
        uint initial = curveFed.maxLossExpansionBps();
        
        vm.expectRevert("Unauthorized");
        curveFed.setMaxLossExpansionBps(1);

        assertEq(curveFed.maxLossExpansionBps(), initial);
    }

    function testSetMaxLossWithdrawBps_fail_whenCalledByNonGov() public {
        uint initial = curveFed.maxLossWithdrawBps();
        
        vm.expectRevert("Unauthorized");
        curveFed.setMaxLossWithdrawBps(1);

        assertEq(curveFed.maxLossWithdrawBps(), initial);
    }

    function testSetGuardianMaxLossBpsLimit_fail_whenCalledByNonGov() public {
        uint initial = curveFed.guardianMaxLossBpsLimit();
        
        vm.expectRevert("Unauthorized");
        curveFed.setGuardianMaxLossBpsLimit(1);

        assertEq(curveFed.guardianMaxLossBpsLimit(), initial);
    }

    function testSetChair() public {
        vm.expectRevert("Unauthorized");
        curveFed.setChair(address(this));

        assertEq(curveFed.chair(), chair);
        vm.prank(gov);
        curveFed.setChair(address(this));
        assertEq(curveFed.chair(), address(this));
        curveFed.resign();
        assertEq(curveFed.chair(), address(0));
    }

    function testSetGuardian() public {
        vm.expectRevert("Unauthorized");
        curveFed.setGuardian(address(this));

        assertEq(curveFed.guardian(), guardian);
        vm.prank(gov);
        curveFed.setGuardian(address(this));
        assertEq(curveFed.guardian(), address(this));
    }

    function testSetGov() public {
        vm.expectRevert("Unauthorized");
        curveFed.claimGov();
        vm.expectRevert("Unauthorized");
        curveFed.setPendingGov(address(this));

        assertEq(address(0), curveFed.pendingGov());
        vm.prank(gov);
        curveFed.setPendingGov(address(this));
        assertEq(address(this), curveFed.pendingGov());
        
        curveFed.claimGov();
        assertEq(address(0), curveFed.pendingGov());
        assertEq(address(this), curveFed.gov());
    }

    function washTrade(uint amount, uint times) public{
        vm.startPrank(dolaFaucet);
        dola.mint(dolaFaucet, amount);
        //Trade back and forth to create a profit
        dola.approve(address(crvPool), type(uint).max);
        fraxBP.approve(address(crvPool), type(uint).max);
        uint input = amount;
        for(uint i; i < times; i++){
            uint received = crvPool.exchange(0, 1, input, 1);
            input = crvPool.exchange(1,0, received, 1);
        }
        vm.stopPrank();
    }
}

