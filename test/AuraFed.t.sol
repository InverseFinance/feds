pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "src/aura-fed/AuraFed.sol";
import {BalancerComposableStablepoolAdapter} from  "src/aura-fed/BalancerAdapter.sol";
import "src/interfaces/IERC20.sol";
import "src/interfaces/aura/IAuraBalRewardPool.sol";

interface IMintable is IERC20 {
    function addMinter(address) external;
}

contract Swapper is BalancerComposableStablepoolAdapter {
    constructor(address bpt_) {
        init(bpt_);
        IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48).approve(address(VAULT), type(uint).max);
    }

    function swapExact(address assetIn, address assetOut, uint amount) public{
        swapExactIn(assetIn, assetOut, amount, 1);
    }
}

contract AuraFedTest is Test{
    IMintable dola = IMintable(0x865377367054516e17014CcdED1e7d814EDC9ce4);
    IERC20 bpt = IERC20(0xFf4ce5AAAb5a627bf82f4A571AB1cE94Aa365eA6);
    IERC20 bal = IERC20(0xba100000625a3754423978a60c9317c58a424e3D);
    IERC20 aura = IERC20(0xC0c293ce456fF0ED870ADd98a0828Dd4d2903DBF);
    address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address vault = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    IAuraBalRewardPool baseRewardPool = IAuraBalRewardPool(0x22915f309EC0182c85cD8331C23bD187fd761360);
    address booster = 0xA57b8d98dAE62B26Ec3bcC4a365338157060B234;
    address chair = address(0xA);
    address guardian = address(0xB);
    address minter = address(0xB);
    address migrator = address(0xC);
    address gov = address(0x926dF14a23BE491164dCF93f4c468A50ef659D5B);
    uint maxLossExpansion = 20;
    uint maxLossContraction = 40;
    uint maxLossTakeProfit = 20;
    AuraFed fed;
    Swapper swapper;

    function setUp() public {
        fed = new AuraFed(
            address(dola), 
            address(baseRewardPool),
            address(bpt),
            booster,
            chair,
            guardian,
            gov,
            maxLossExpansion,
            maxLossContraction,
            maxLossTakeProfit
        );
        swapper = new Swapper(address(bpt));
        vm.startPrank(gov);
        dola.addMinter(address(fed));
        dola.addMinter(minter);
        vm.stopPrank();
    }

    function testExpansion_succeed_whenExpandedWithinAcceptableSlippage() public {
        uint amount = 1 ether;     
        uint initialDolaSupply = fed.debt();
        uint initialbptSupply = fed.claims();
        uint initialDolaTotalSupply = dola.totalSupply();

        vm.prank(chair);
        fed.expansion(amount);

        assertEq(initialDolaTotalSupply + amount, dola.totalSupply());
        assertEq(initialDolaSupply + amount, fed.debt());
        //TODO: Should have greater precision about the amount of balLP acquired
        assertGt(fed.claims(), initialbptSupply);
    }

    function testFailExpansion_fail_whenExpandedOutsideAcceptableSlippage() public {
        uint amount = 10_000_000 ether;

        vm.prank(chair);
        fed.expansion(amount);
    }

    function testContraction_succeed_whenContractedWithinAcceptableSlippage() public {
        uint amount = 1 ether;
        vm.prank(chair);
        fed.expansion(amount*2);
        uint initialDolaSupply = fed.debt();
        uint initialDolaTotalSupply = dola.totalSupply();
        uint initialBalLpSupply = fed.claims();

        vm.prank(chair);
        fed.contraction(amount);

        //Make sure basic accounting of contraction is correct:
        assertGt(initialBalLpSupply, fed.claims());
        assertGt(initialDolaSupply, fed.debt());
        assertGt(initialDolaTotalSupply, dola.totalSupply());
        assertEq(initialDolaTotalSupply - dola.totalSupply(), initialDolaSupply - fed.debt());

        //Make sure maxLoss wasn't exceeded
        assertLe(initialDolaSupply-fed.debt(), amount*10_000/(10_000-maxLossContraction), "Amount withdrawn exceeds maxloss"); 
        assertLe(initialDolaTotalSupply-dola.totalSupply(), amount*10_000/(10_000-maxLossContraction), "Amount withdrawn exceeds maxloss");
    }

    function testContraction_succeed_whenContractedWithProfit() public {
        balancePool();
        uint amount = 1000 ether;
        vm.prank(chair);
        fed.expansion(amount);
        washTrade(100, 1_000_000 ether);
        uint initialDolaSupply = fed.debt();
        uint initialDolaTotalSupply = dola.totalSupply();
        uint initialBalLpSupply = fed.claims();
        uint initialGovDola = dola.balanceOf(gov);

        vm.prank(chair);
        fed.contraction(amount);

        //Make sure basic accounting of contraction is correct:
        assertGt(initialBalLpSupply, fed.claims(), "BPT Supply didn't drop");
        assertLe(initialDolaSupply, fed.debt()+amount, "Internal Dola Supply didn't drop by test amount");
        assertGt(initialDolaSupply, fed.debt()+(amount - amount * maxLossContraction / 10000), "Internal Dola Supply didn't drop by test amount");
        assertLe(initialDolaTotalSupply, dola.totalSupply()+amount, "Total Dola Supply didn't drop by test amount");
        assertGt(initialDolaTotalSupply, dola.totalSupply()+(amount - amount * maxLossContraction / 10000), "Total Dola Supply didn't drop by test amount");
    }

    function testContractAll_succeed_whenContractedWithinAcceptableSlippage() public {
        vm.prank(chair);
        fed.expansion(1000 ether);
        uint initialDolaSupply = fed.debt();
        uint initialDolaTotalSupply = dola.totalSupply();
        uint initialBalLpSupply = fed.claims();

        vm.prank(chair);
        fed.contractAll();

        //Make sure basic accounting of contraction is correct:
        assertLe(initialDolaTotalSupply-initialDolaSupply, dola.totalSupply());

        //Make sure maxLoss wasn't exceeded
        assertLe(initialDolaSupply-fed.debt(), initialDolaSupply*10_000/(10_000-maxLossContraction), "Amount withdrawn exceeds maxloss"); 
        assertLe(initialDolaTotalSupply-dola.totalSupply(), initialDolaSupply*10_000/(10_000-maxLossContraction), "Amount withdrawn exceeds maxloss");
        uint percentageToWithdraw = 10**18;
        uint percentageActuallyWithdrawnBal = initialBalLpSupply * 10**18 / (initialBalLpSupply - fed.claims());
        assertLe(percentageActuallyWithdrawnBal * (10_000 - maxLossContraction) / 10_000, percentageToWithdraw, "Too much bpt spent");
    }

    function testContractAll_succeed_whenContractedWithProfit() public {
        vm.prank(chair);
        fed.expansion(1000 ether);
        washTrade(100, 100_000 ether);
        uint initialDolaSupply = fed.debt();
        uint initialDolaTotalSupply = dola.totalSupply();
        uint initialGovDola = dola.balanceOf(gov);
        uint initialBalLpSupply = fed.claims();

        vm.prank(chair);
        fed.contractAll();

        //Make sure basic accounting of contraction is correct:
        assertEq(initialDolaTotalSupply-initialDolaSupply, dola.totalSupply(), "Dola supply was not decreased by initialDolaSupply");
        assertEq(fed.debt(), 0);
        assertEq(fed.claims(), 0);
        assertGt(initialBalLpSupply, fed.claims());
        assertGt(dola.balanceOf(gov), initialGovDola);
    }


    function testTakeProfit_NoProfit_whenCallingWhenUnprofitable() public {
        vm.startPrank(chair);
        fed.expansion(1000 ether);
        uint initialAura = aura.balanceOf(gov);
        uint initialAuraBal = bal.balanceOf(gov);
        uint initialBalLpSupply = fed.claims();
        uint initialGovDola = dola.balanceOf(gov);
        fed.takeProfit(1);
        vm.stopPrank();

        assertEq(aura.balanceOf(gov), initialAura, "treasury aura balance didn't increase");
        assertEq(bal.balanceOf(gov), initialAuraBal, "treasury bal balance din't increase");
        assertEq(initialBalLpSupply, fed.claims());
        assertEq(dola.balanceOf(gov), initialGovDola);
    }

    function testTakeProfit_IncreaseGovBalAuraBalance_whenCallingWithoutHarvestLpFlag() public {
        vm.startPrank(chair);
        fed.expansion(1000 ether);
        uint initialAura = aura.balanceOf(gov);
        uint initialAuraBal = bal.balanceOf(gov);
        uint initialBalLpSupply = fed.claims();
        uint initialGovDola = dola.balanceOf(gov);
        //Pass time
        washTrade(100, 10_000 ether);
        vm.warp(baseRewardPool.periodFinish() + 1);
        vm.startPrank(chair);
        fed.takeProfit(0);
        vm.stopPrank();

        assertGt(aura.balanceOf(gov), initialAura, "treasury aura balance didn't increase");
        assertGt(bal.balanceOf(gov), initialAuraBal, "treasury bal balance din't increase");
        assertEq(initialBalLpSupply, fed.claims(), "bpt supply changed");
        assertEq(dola.balanceOf(gov), initialGovDola, "Gov DOLA supply changed");
    }

    function testburnRemainingDolaSupply_Success() public {
        vm.startPrank(chair);
        fed.expansion(1000 ether);
        vm.stopPrank();       
        vm.startPrank(minter);
        dola.mint(minter, 1000 ether);
        dola.approve(address(fed), 1000 ether);

        uint dolaSupplyBefore = dola.totalSupply();
        uint minterBalanceBefore = dola.balanceOf(minter);
        fed.repayDebt(fed.debt());
        assertEq(fed.debt(), 0);
        assertEq(dola.totalSupply(), dolaSupplyBefore - 1000 ether);
        assertEq(dola.balanceOf(minter), minterBalanceBefore - 1000 ether);
    }

    function testMigrateClaims_Success_WhenCalledByMigrator() public {
        vm.prank(chair);
        fed.expansion(1000 ether);
        uint initialClaims = fed.claims();
        uint initialDebt = fed.debt();
        vm.prank(gov);
        fed.setMigrator(migrator);
        vm.prank(migrator);
        uint debtToMigrate = fed.migrateTo(initialClaims);

        assertEq(bpt.balanceOf(migrator), initialClaims, "Migrator did not received correct amount of claims");
        assertEq(debtToMigrate, initialDebt, "debtToMigrate not equal debt");
        assertEq(fed.claims(), 0, "Fed claims not 0");
        assertEq(fed.debt(), 0, "Fed debt not 0");
        
    }

    function testMigrateClaims_Fails_WhenCalledByNonMigrator(address caller) public {
        vm.assume(caller != migrator);
        vm.prank(chair);
        fed.expansion(1000 ether);
        uint claims = fed.claims();
        vm.prank(gov);
        fed.setMigrator(migrator);
        vm.prank(caller);
        vm.expectRevert("ONLY MIGRATOR");
        uint debtToMigrate = fed.migrateTo(claims);
        
    }

    function testMigrateClaims_Success_WhenMigratingLessThanFullAmount(uint migrationAmount) public {
        vm.assume(migrationAmount > 1 ether);
        migrationAmount = migrationAmount % 1000 ether;
        vm.prank(chair);
        fed.expansion(1000 ether);
        uint initialClaims = fed.claims();
        uint claimsMigrationAmount = fed.claims() * migrationAmount / 1000 ether;
        uint initialDebt = fed.debt();
        vm.prank(gov);
        fed.setMigrator(migrator);
        vm.prank(migrator);
        uint debtToMigrate = fed.migrateTo(claimsMigrationAmount);

        assertEq(bpt.balanceOf(migrator), claimsMigrationAmount, "Migrator did not received correct amount of claims");
        assertEq(fed.claims(), initialClaims - claimsMigrationAmount, "Fed claims not decreased correctly");
        assertEq(fed.debt(), initialDebt - debtToMigrate, "Fed debt not decreased correctly");
    }

    function testSetMigrator_Fails_WhenCalledByNonGov(address caller) public {
        vm.assume(caller != migrator);
        vm.prank(chair);
        fed.expansion(1000 ether);
        vm.prank(caller);
        vm.expectRevert("NOT GOV");
        fed.setMigrator(migrator);
        
    }

    function testEmergencyWithdraw_Success_WhenCalledByGov() public {
        vm.prank(chair);
        fed.expansion(1000 ether);
        uint initialClaimsSupply = fed.claimsSupply();
        vm.prank(gov);
        fed.emergencyWithdraw();

        assertEq(bpt.balanceOf(gov), initialClaimsSupply);
        assertEq(fed.claimsSupply(), 0);
    }

    function testEmergencyWithdraw_Fails_WhenCalledByNonGov(address caller) public {
        vm.prank(chair);
        fed.expansion(1000 ether);
        vm.prank(caller);
        vm.expectRevert("NOT GOV");
        fed.emergencyWithdraw();
    }

    function testContraction_FailWithOnlyChair_whenCalledByOtherAddress() public {
        vm.prank(gov);
        vm.expectRevert("ONLY CHAIR");
        fed.contraction(1000);
    }

    function testSetMaxLossExpansionBps_succeed_whenCalledByGov() public {
        uint initial = fed.maxLossExpansionBps();
        
        vm.prank(gov);
        fed.setMaxLossExpansionBps(1);

        assertEq(fed.maxLossExpansionBps(), 1);
        assertTrue(initial != fed.maxLossExpansionBps());
    }

    function testSetMaxLossContractionBps_succeed_whenCalledByGov() public {
        uint initial = fed.maxLossContractionBps();
        
        vm.prank(gov);
        fed.setMaxLossContractionBps(1);

        assertEq(fed.maxLossContractionBps(), 1);
        assertTrue(initial != fed.maxLossContractionBps());
    }

    function testSetMaxLossTakeProfitBps_succeed_whenCalledByGov() public {
        uint initial = fed.maxLossTakeProfitBps();
        
        vm.prank(gov);
        fed.setMaxLossTakeProfitBps(1);

        assertEq(fed.maxLossTakeProfitBps(), 1);
        assertTrue(initial != fed.maxLossTakeProfitBps());
    }

    function testSetMaxLossExpansionBps_fail_whenCalledByNonGov() public {
        uint initial = fed.maxLossExpansionBps();
        
        vm.expectRevert("NOT GOV");
        fed.setMaxLossExpansionBps(1);

        assertEq(fed.maxLossExpansionBps(), initial);
    }

    function testSetMaxLossContractionBps_fail_whenNotCalledByGov() public {
        uint initial = fed.maxLossContractionBps();
        
        vm.expectRevert("ONLY GOV OR GUARDIAN");
        fed.setMaxLossContractionBps(1);

        assertEq(fed.maxLossContractionBps(), initial);
    }

    function testSetMaxLossTakeProfitBps_fail_whenNotCalledByGov() public {
        uint initial = fed.maxLossTakeProfitBps();
        
        vm.expectRevert("NOT GOV");
        fed.setMaxLossTakeProfitBps(1);

        assertEq(fed.maxLossTakeProfitBps(), initial);
    }

    function balancePool() public {
        (,uint[] memory balances,) = IVault(vault).getPoolTokens(IBPT(address(bpt)).getPoolId());
        uint inbalance = balances[0] - balances[1]*10**10;
        uint swapAmount = inbalance / 10**18;
        deal(usdc, address(swapper), swapAmount);
        swapper.swapExact(usdc, address(dola), swapAmount);

    }

    function washTrade(uint loops, uint amount) public {
        vm.startPrank(minter);
        dola.mint(address(swapper), amount);
        //Trade back and forth to create a profit
        for(uint i; i < loops; i++){
            swapper.swapExact(address(dola), usdc, dola.balanceOf(address(swapper)));
            swapper.swapExact(usdc, address(dola), IERC20(usdc).balanceOf(address(swapper)));
        }
        vm.stopPrank();     
    }
}
