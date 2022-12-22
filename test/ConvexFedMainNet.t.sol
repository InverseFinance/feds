// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.11;

import "ds-test/test.sol";
import "forge-std/Vm.sol";
import "src/convex-fed/ConvexFed.sol";
import "src/interfaces/curve/IMetaPool.sol";
import "src/interfaces/curve/IZapDepositor3pool.sol";
import "src/interfaces/IERC20.sol";
import "src/interfaces/convex/IConvexBooster.sol";
import "src/interfaces/convex/IConvexBaseRewardPool.sol";

interface IMinted is IERC20 {
    function addMinter(address minter_) external;
    function removeMinter(address minter_) external;
    function mint(address to, uint amount) external;
}

contract ConvexFedTest is DSTest {
    Vm internal constant vm = Vm(HEVM_ADDRESS);
    IConvexBooster public convexBooster = IConvexBooster(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);
    IConvexBaseRewardPool public baseRewardPool = IConvexBaseRewardPool(0x0404d05F3992347d2f0dC3a97bdd147D77C85c1c);
    IMetaPool public crvPool = IMetaPool(0xE57180685E3348589E9521aa53Af0BCD497E884d);
    ConvexFed public convexFed;
    IMinted public dola = IMinted(0x865377367054516e17014CcdED1e7d814EDC9ce4);
    IERC20 public crv = IERC20(0xD533a949740bb3306d119CC777fa900bA034cd52);
    IERC20 public cvx = IERC20(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);
    IERC20 public fraxBP = IERC20(0x3175Df0976dFA876431C2E9eE6Bc45b65d3473CC);
    address public gov = 0x926dF14a23BE491164dCF93f4c468A50ef659D5B;
    address public chair = address(0xB);
    address public guardian = address(0xC);
    address public dolaFaucet = address(0xF);
    uint public maxLossExpansionBps = 100;
    uint public maxLossWithdrawBps = 100;
    uint public maxLossTakeProfitBps = 100;

    function setUp() public {
        convexFed = new ConvexFed(
            address(dola),
            address(cvx),
            address(crvPool),
            address(convexBooster),
            address(baseRewardPool),
            chair,
            gov,
            guardian,
            maxLossExpansionBps,
            maxLossWithdrawBps,
            maxLossTakeProfitBps
        );
        vm.startPrank(gov);
        dola.addMinter(address(convexFed));
        dola.addMinter(dolaFaucet);
        vm.stopPrank();
        vm.label(0xF403C135812408BFbE8713b5A23a04b3D48AAE31, "convex booster");
        vm.label(0x3Fe65692bfCD0e6CF84cB1E7d24108E434A7587e, "convex base reward pool");
        vm.label(0xAA5A67c256e27A5d80712c51971408db3370927D, "DOLA-3CRV");
        vm.label(0x865377367054516e17014CcdED1e7d814EDC9ce4, "dola");
        vm.label(0x62B9c7356A2Dc64a1969e19C23e4f579F9810Aa7, "crv");
        vm.label(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B, "cvx");
    }

    function testExpansion_succeed_whenExpandedWithinAcceptableSlippage(uint amount) public {
        vm.assume(amount < 1_000_000 * 10**18);
        vm.assume(amount > 10**18);
        uint initialDolaSupply = convexFed.dolaSupply();
        uint initialCrvLpSupply = convexFed.crvLpSupply();
        uint initialDolaTotalSupply = dola.totalSupply();

        vm.prank(chair);
        convexFed.expansion(amount);

        assertEq(initialDolaTotalSupply + amount, dola.totalSupply());
        assertEq(initialDolaSupply + amount, convexFed.dolaSupply());
        //TODO: Should have greater precision about the amount of crvLP acquired
        assertGt(convexFed.crvLpSupply(), initialCrvLpSupply);
        assertGe(convexFed.crvLpSupply()-initialCrvLpSupply, amount * 10**18 / crvPool.get_virtual_price() * (10_000 - maxLossExpansionBps) / 10_000);
    }

    function testFailExpansion_fail_whenExpandedOutsideAcceptableSlippage() public {
        uint amount = 1000_000_000 ether;

        vm.prank(chair);
        convexFed.expansion(amount);
    }

    function testContraction_succeed_whenContractedWithinAcceptableSlippage(uint amount) public {
        vm.assume(amount < 500_000 * 10**18);
        vm.assume(amount > 10**18);
        vm.prank(chair);
        convexFed.expansion(amount*2);
        uint initialDolaSupply = convexFed.dolaSupply();
        uint initialDolaTotalSupply = dola.totalSupply();
        uint initialCrvLpSupply = convexFed.crvLpSupply();

        vm.prank(chair);
        convexFed.contraction(amount);

        //Make sure basic accounting of contraction is correct:
        assertGt(initialCrvLpSupply, convexFed.crvLpSupply(), "");
        assertGt(initialDolaSupply, convexFed.dolaSupply());
        assertGt(initialDolaTotalSupply, dola.totalSupply());
        assertEq(initialDolaTotalSupply - dola.totalSupply(), initialDolaSupply - convexFed.dolaSupply());

        //Make sure maxLoss wasn't exceeded
        assertLe(initialDolaSupply-convexFed.dolaSupply(), amount*10_000/(10_000-maxLossWithdrawBps), "Amount withdrawn exceeds maxloss"); 
        assertLe(initialDolaTotalSupply-dola.totalSupply(), amount*10_000/(10_000-maxLossWithdrawBps), "Amount withdrawn exceeds maxloss");
        uint percentageToWithdraw = initialDolaSupply * 10**18 / amount;
        uint percentageActuallyWithdrawnCrv = initialCrvLpSupply * 10**18 / (initialCrvLpSupply - convexFed.crvLpSupply());
        assertLe(percentageActuallyWithdrawnCrv * (10_000 - maxLossWithdrawBps) / 10_000, percentageToWithdraw, "Too much crvLP spent");
    }

    function testContraction_succeed_whenContractedWithProfit(uint amount) public {
        vm.assume(amount < 1_000_000 * 10**18);
        vm.assume(amount > 10**18);
        vm.prank(chair);
        convexFed.expansion(amount);
        washTrade(5_000_000 ether, 100);
        uint initialDolaSupply = convexFed.dolaSupply();
        uint initialDolaTotalSupply = dola.totalSupply();
        uint initialCrvLpSupply = convexFed.crvLpSupply();
        uint initialGovDola = dola.balanceOf(gov);

        vm.prank(chair);
        convexFed.contraction(amount*100/99);

        //Make sure basic accounting of contraction is correct:
        assertGt(initialCrvLpSupply, convexFed.crvLpSupply(), "Crv LP Supply didn't drop");
        assertEq(initialDolaSupply-amount, convexFed.dolaSupply(), "Internal Dola Supply didn't drop by test amount");
        assertEq(initialDolaTotalSupply, dola.totalSupply()+amount, "Total Dola Supply didn't drop by test amount");
        assertGt(dola.balanceOf(gov), initialGovDola, "Gov dola balance isn't higher");
    }

    function testContractAll_succeed_whenContractedWithinAcceptableSlippage() public {
        vm.prank(chair);
        convexFed.expansion(1000_000 ether);
        uint initialDolaSupply = convexFed.dolaSupply();
        uint initialDolaTotalSupply = dola.totalSupply();
        uint initialCrvLpSupply = convexFed.crvLpSupply();

        vm.prank(chair);
        convexFed.contractAll();

        //Make sure basic accounting of contraction is correct:
        assertLe(initialDolaTotalSupply-initialDolaSupply, dola.totalSupply());

        //Make sure maxLoss wasn't exceeded
        assertLe(initialDolaSupply-convexFed.dolaSupply(), initialDolaSupply*10_000/(10_000-maxLossWithdrawBps), "Amount withdrawn exceeds maxloss"); 
        assertLe(initialDolaTotalSupply-dola.totalSupply(), initialDolaSupply*10_000/(10_000-maxLossWithdrawBps), "Amount withdrawn exceeds maxloss");
        uint percentageToWithdraw = 10**18;
        uint percentageActuallyWithdrawnCrv = initialCrvLpSupply * 10**18 / (initialCrvLpSupply - convexFed.crvLpSupply());
        assertLe(percentageActuallyWithdrawnCrv * (10_000 - maxLossWithdrawBps) / 10_000, percentageToWithdraw, "Too much crvLP spent");
    }

    function testContractAll_succeed_whenContractedWithProfit() public {
        vm.prank(chair);
        convexFed.expansion(100_000 ether);
        washTrade(5000_000 ether, 100);
        uint initialDolaSupply = convexFed.dolaSupply();
        uint initialDolaTotalSupply = dola.totalSupply();
        uint initialGovDola = dola.balanceOf(gov);
        uint initialCrvLpSupply = convexFed.crvLpSupply();

        vm.prank(chair);
        convexFed.contractAll();

        //Make sure basic accounting of contraction is correct:
        assertEq(initialDolaTotalSupply-initialDolaSupply, dola.totalSupply(), "Dola supply was not decreased by initialDolaSupply");
        assertEq(convexFed.dolaSupply(), 0);
        assertEq(convexFed.crvLpSupply(), 0);
        assertGt(initialCrvLpSupply, convexFed.crvLpSupply());
        assertGt(dola.balanceOf(gov), initialGovDola);
    }

    function testFailContraction_fail_whenContractedOutsideAcceptableSlippage() public {
        uint amount = 100_000 ether;

        vm.startPrank(chair);
        convexFed.expansion(amount);
        convexFed.setMaxLossWithdrawBps(0);
        convexFed.contraction(amount);
        vm.stopPrank();
    }

    function testFailContractAll_fail_whenContractedOutsideAcceptableSlippage() public {
        uint amount = 100_000 ether;

        vm.startPrank(chair);
        convexFed.expansion(amount);
        convexFed.setMaxLossWithdrawBps(0);
        convexFed.contractAll();
        vm.stopPrank();
    }

    function testTakeProfit_NoProfit_whenCallingWhenUnprofitable() public {
        vm.startPrank(chair);
        convexFed.expansion(100_000 ether);
        uint initialCvx = cvx.balanceOf(gov);
        uint initialCvxCrv = crv.balanceOf(gov);
        uint initialCrvLpSupply = convexFed.crvLpSupply();
        uint initialGovDola = dola.balanceOf(gov);
        convexFed.takeProfit(true);
        vm.stopPrank();

        assertEq(cvx.balanceOf(gov), initialCvx, "treasury cvx balance didn't increase");
        assertEq(crv.balanceOf(gov), initialCvxCrv, "treasury crv balance din't increase");
        assertEq(initialCrvLpSupply, convexFed.crvLpSupply());
        assertEq(dola.balanceOf(gov), initialGovDola);
    }

    function testTakeProfit_IncreaseGovCrvCvxBalance_whenCallingWithoutHarvestLpFlag() public {
        vm.startPrank(chair);
        convexFed.expansion(100_000 ether);
        uint initialCvx = cvx.balanceOf(gov);
        uint initialCvxCrv = crv.balanceOf(gov);
        uint initialCrvLpSupply = convexFed.crvLpSupply();
        uint initialGovDola = dola.balanceOf(gov);
        //Pass time
        vm.warp(baseRewardPool.periodFinish() + 1);
        convexFed.takeProfit(false);
        vm.stopPrank();

        assertGt(cvx.balanceOf(gov), initialCvx, "treasury cvx balance didn't increase");
        assertGt(crv.balanceOf(gov), initialCvxCrv, "treasury crv balance din't increase");
        assertEq(initialCrvLpSupply, convexFed.crvLpSupply());
        assertEq(dola.balanceOf(gov), initialGovDola);
    }

    function testTakeProfit_IncreaseGovDolaBalance_whenCallingWithHarvestLpFlag() public {
        vm.prank(chair);
        convexFed.expansion(100_000 ether);
        uint initialCrvLpSupply = convexFed.crvLpSupply();
        uint initialGovDola = dola.balanceOf(gov);
        uint input = 1000_000 ether;
        washTrade(input, 100);
        vm.prank(chair);
        convexFed.takeProfit(true);

        assertGt(dola.balanceOf(gov), initialGovDola);
        assertGt(initialCrvLpSupply, convexFed.crvLpSupply());
    }

    function testContraction_FailWithOnlyChair_whenCalledByOtherAddress() public {
        vm.prank(dolaFaucet);
        vm.expectRevert("ONLY CHAIR");
        convexFed.contraction(1000);
    }

    function testSetMaxLossExpansionBps_succeed_whenCalledByGov() public {
        uint initial = convexFed.maxLossExpansionBps();
        
        vm.prank(gov);
        convexFed.setMaxLossExpansionBps(1);

        assertEq(convexFed.maxLossExpansionBps(), 1);
        assertTrue(initial != convexFed.maxLossExpansionBps());
    }

    function testSetMaxLossWithdrawBps_succeed_whenCalledByGov() public {
        uint initial = convexFed.maxLossWithdrawBps();
        
        vm.prank(gov);
        convexFed.setMaxLossWithdrawBps(1);

        assertEq(convexFed.maxLossWithdrawBps(), 1);
        assertTrue(initial != convexFed.maxLossWithdrawBps());
    }

    function testSetMaxLossTakeProfitBps_succeed_whenCalledByGov() public {
        uint initial = convexFed.maxLossTakeProfitBps();
        
        vm.prank(gov);
        convexFed.setMaxLossTakeProfitBps(1);

        assertEq(convexFed.maxLossTakeProfitBps(), 1);
        assertTrue(initial != convexFed.maxLossTakeProfitBps());
    }

    function testSetMaxLossExpansionBps_fail_whenCalledByNonGov() public {
        uint initial = convexFed.maxLossExpansionBps();
        
        vm.expectRevert("ONLY GOV");
        convexFed.setMaxLossExpansionBps(1);

        assertEq(convexFed.maxLossExpansionBps(), initial);
    }

    function testSetMaxLossWithdrawBps_fail_whenCalledByGov() public {
        uint initial = convexFed.maxLossWithdrawBps();
        
        vm.expectRevert("ONLY GOV");
        convexFed.setMaxLossWithdrawBps(1);

        assertEq(convexFed.maxLossWithdrawBps(), initial);
    }

    function testSetMaxLossTakeProfitBps_fail_whenCalledByGov() public {
        uint initial = convexFed.maxLossTakeProfitBps();
        
        vm.expectRevert("ONLY GOV");
        convexFed.setMaxLossTakeProfitBps(1);

        assertEq(convexFed.maxLossTakeProfitBps(), initial);
    }

    function testTakeProfit_FailWithOnlyChair_whenCalledByOtherAddress() public {
        vm.prank(chair);
        convexFed.expansion(100_000 ether);
        washTrade(1_000_000 ether, 100);
 
        vm.prank(dolaFaucet);
        vm.expectRevert("ONLY CHAIR CAN TAKE CRV LP PROFIT");
        convexFed.takeProfit(true);
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

