pragma solidity ^0.8.13;

import "ds-test/test.sol";
import "forge-std/Vm.sol";
import "src/aura-fed/AuraFed.sol";
import "src/aura-fed/BalancerAdapter.sol";
import "src/interfaces/IERC20.sol";
import "src/interfaces/aura/IAuraBalRewardPool.sol";

interface IMintable is IERC20 {
    function addMinter(address) external;
}

contract Swapper is BalancerComposableStablepoolAdapter {
    constructor(bytes32 poolId_, address dola_, address vault_) BalancerComposableStablepoolAdapter(poolId_, dola_, vault_){}

    function swapExact(address assetIn, address assetOut, uint amount) public{
        swapExactIn(assetIn, assetOut, amount, 1);
    }
}

contract AuraFedTest is DSTest{
    Vm internal constant vm = Vm(HEVM_ADDRESS);
    IMintable dola = IMintable(0x865377367054516e17014CcdED1e7d814EDC9ce4);
    IERC20 bpt = IERC20(0x5b3240B6BE3E7487d61cd1AFdFC7Fe4Fa1D81e64);
    IERC20 bal = IERC20(0xba100000625a3754423978a60c9317c58a424e3D);
    IERC20 aura = IERC20(0xC0c293ce456fF0ED870ADd98a0828Dd4d2903DBF);
    address vault = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    IAuraBalRewardPool baseRewardPool = IAuraBalRewardPool(0x99653d46D52eE41c7b35cbAd1aC408A00bad6A76);
    address booster = 0x7818A1DA7BD1E64c199029E86Ba244a9798eEE10;
    address chair = address(0xA);
    address guardian = address(0xB);
    address minter = address(0xB);
    address gov = address(0x926dF14a23BE491164dCF93f4c468A50ef659D5B);
    uint maxLossExpansion = 20;
    uint maxLossWithdraw = 20;
    uint maxLossTakeProfit = 20;
    bytes32 poolId = bytes32(0x5b3240b6be3e7487d61cd1afdfc7fe4fa1d81e6400000000000000000000037b);
    address holder = 0x4D2F01D281Dd0b98e75Ca3E1FdD36823B16a7dbf;
    AuraFed fed;
    Swapper swapper;

    function setUp() public {
        fed = new AuraFed(
            address(dola), 
            address(aura), 
            vault, 
            address(baseRewardPool),
            booster,
            chair,
            guardian,
            gov,
            maxLossExpansion,
            maxLossWithdraw,
            maxLossTakeProfit,
            poolId
        );
        swapper = new Swapper(poolId, address(dola), vault);
        vm.startPrank(gov);
        dola.addMinter(address(fed));
        dola.addMinter(minter);
        vm.stopPrank();
    }

    function testExpansion_succeed_whenExpandedWithinAcceptableSlippage() public {
        uint amount = 1 ether;     
        uint initialDolaSupply = fed.dolaSupply();
        uint initialbptSupply = fed.bptSupply();
        uint initialDolaTotalSupply = dola.totalSupply();

        vm.prank(chair);
        fed.expansion(amount);

        assertEq(initialDolaTotalSupply + amount, dola.totalSupply());
        assertEq(initialDolaSupply + amount, fed.dolaSupply());
        //TODO: Should have greater precision about the amount of balLP acquired
        assertGt(fed.bptSupply(), initialbptSupply);
    }

    function testFailExpansion_fail_whenExpandedOutsideAcceptableSlippage() public {
        uint amount = 1000_000 ether;

        vm.prank(chair);
        fed.expansion(amount);
    }

    function testContraction_succeed_whenContractedWithinAcceptableSlippage() public {
        uint amount = 1 ether;
        vm.prank(chair);
        fed.expansion(amount*2);
        uint initialDolaSupply = fed.dolaSupply();
        uint initialDolaTotalSupply = dola.totalSupply();
        uint initialBalLpSupply = fed.bptSupply();

        vm.prank(chair);
        fed.contraction(amount);

        //Make sure basic accounting of contraction is correct:
        assertGt(initialBalLpSupply, fed.bptSupply());
        assertGt(initialDolaSupply, fed.dolaSupply());
        assertGt(initialDolaTotalSupply, dola.totalSupply());
        assertEq(initialDolaTotalSupply - dola.totalSupply(), initialDolaSupply - fed.dolaSupply());

        //Make sure maxLoss wasn't exceeded
        assertLe(initialDolaSupply-fed.dolaSupply(), amount*10_000/(10_000-maxLossWithdraw), "Amount withdrawn exceeds maxloss"); 
        assertLe(initialDolaTotalSupply-dola.totalSupply(), amount*10_000/(10_000-maxLossWithdraw), "Amount withdrawn exceeds maxloss");
    }

    function testContraction_succeed_whenContractedWithProfit() public {
        uint amount = 1000 ether;
        vm.prank(chair);
        fed.expansion(amount);
        washTrade(100, 1000_000 ether);
        uint initialDolaSupply = fed.dolaSupply();
        uint initialDolaTotalSupply = dola.totalSupply();
        uint initialBalLpSupply = fed.bptSupply();
        uint initialGovDola = dola.balanceOf(gov);

        vm.prank(chair);
        fed.contraction(amount);

        //Make sure basic accounting of contraction is correct:
        assertGt(initialBalLpSupply, fed.bptSupply(), "BPT Supply didn't drop");
        assertEq(initialDolaSupply-amount, fed.dolaSupply(), "Internal Dola Supply didn't drop by test amount");
        assertEq(initialDolaTotalSupply, dola.totalSupply()+amount, "Total Dola Supply didn't drop by test amount");
        assertGt(dola.balanceOf(gov), initialGovDola, "Gov dola balance isn't higher");
    }

    function testContractAll_succeed_whenContractedWithinAcceptableSlippage() public {
        vm.prank(chair);
        fed.expansion(1000 ether);
        uint initialDolaSupply = fed.dolaSupply();
        uint initialDolaTotalSupply = dola.totalSupply();
        uint initialBalLpSupply = fed.bptSupply();

        vm.prank(chair);
        fed.contractAll();

        //Make sure basic accounting of contraction is correct:
        assertLe(initialDolaTotalSupply-initialDolaSupply, dola.totalSupply());

        //Make sure maxLoss wasn't exceeded
        assertLe(initialDolaSupply-fed.dolaSupply(), initialDolaSupply*10_000/(10_000-maxLossWithdraw), "Amount withdrawn exceeds maxloss"); 
        assertLe(initialDolaTotalSupply-dola.totalSupply(), initialDolaSupply*10_000/(10_000-maxLossWithdraw), "Amount withdrawn exceeds maxloss");
        uint percentageToWithdraw = 10**18;
        uint percentageActuallyWithdrawnBal = initialBalLpSupply * 10**18 / (initialBalLpSupply - fed.bptSupply());
        assertLe(percentageActuallyWithdrawnBal * (10_000 - maxLossWithdraw) / 10_000, percentageToWithdraw, "Too much bpt spent");
    }

    function testContractAll_succeed_whenContractedWithProfit() public {
        vm.prank(chair);
        fed.expansion(1000 ether);
        washTrade(100, 100_000 ether);
        uint initialDolaSupply = fed.dolaSupply();
        uint initialDolaTotalSupply = dola.totalSupply();
        uint initialGovDola = dola.balanceOf(gov);
        uint initialBalLpSupply = fed.bptSupply();

        vm.prank(chair);
        fed.contractAll();

        //Make sure basic accounting of contraction is correct:
        assertEq(initialDolaTotalSupply-initialDolaSupply, dola.totalSupply(), "Dola supply was not decreased by initialDolaSupply");
        assertEq(fed.dolaSupply(), 0);
        assertEq(fed.bptSupply(), 0);
        assertGt(initialBalLpSupply, fed.bptSupply());
        assertGt(dola.balanceOf(gov), initialGovDola);
    }


    function testTakeProfit_NoProfit_whenCallingWhenUnprofitable() public {
        vm.startPrank(chair);
        fed.expansion(1000 ether);
        uint initialAura = aura.balanceOf(gov);
        uint initialAuraBal = bal.balanceOf(gov);
        uint initialBalLpSupply = fed.bptSupply();
        uint initialGovDola = dola.balanceOf(gov);
        fed.takeProfit(true);
        vm.stopPrank();

        assertEq(aura.balanceOf(gov), initialAura, "treasury aura balance didn't increase");
        assertEq(bal.balanceOf(gov), initialAuraBal, "treasury bal balance din't increase");
        assertEq(initialBalLpSupply, fed.bptSupply());
        assertEq(dola.balanceOf(gov), initialGovDola);
    }

    function testTakeProfit_IncreaseGovBalAuraBalance_whenCallingWithoutHarvestLpFlag() public {
        vm.startPrank(chair);
        fed.expansion(1000 ether);
        uint initialAura = aura.balanceOf(gov);
        uint initialAuraBal = bal.balanceOf(gov);
        uint initialBalLpSupply = fed.bptSupply();
        uint initialGovDola = dola.balanceOf(gov);
        //Pass time
        washTrade(100, 10_000 ether);
        vm.warp(baseRewardPool.periodFinish() + 1);
        vm.startPrank(chair);
        fed.takeProfit(false);
        vm.stopPrank();

        assertGt(aura.balanceOf(gov), initialAura, "treasury aura balance didn't increase");
        assertGt(bal.balanceOf(gov), initialAuraBal, "treasury bal balance din't increase");
        assertEq(initialBalLpSupply, fed.bptSupply(), "bpt supply changed");
        assertEq(dola.balanceOf(gov), initialGovDola, "Gov DOLA supply changed");
    }
    
    function testTakeProfit_IncreaseGovDolaBalance_whenDolaHasBeenSentToContract() public {
        vm.startPrank(chair);
        fed.expansion(1000 ether);
        vm.stopPrank();
        vm.startPrank(minter);
        dola.mint(address(fed), 1000 ether);
        vm.stopPrank();
        vm.startPrank(chair);
        uint initialAura = aura.balanceOf(gov);
        uint initialAuraBal = bal.balanceOf(gov);
        uint initialBalLpSupply = fed.bptSupply();
        uint initialGovDola = dola.balanceOf(gov);
        fed.contraction(200 ether);
        assertEq(fed.dolaSupply(), 0);
        //Pass time
        washTrade(100, 10_000 ether);
        vm.warp(baseRewardPool.periodFinish() + 1);
        vm.startPrank(chair);
        fed.takeProfit(true);
        vm.stopPrank();

        assertGt(aura.balanceOf(gov), initialAura, "treasury aura balance didn't increase");
        assertGt(bal.balanceOf(gov), initialAuraBal, "treasury bal balance din't increase");
        assertGt(initialBalLpSupply, fed.bptSupply(), "bpt Supply wasn't reduced");
        assertGt(dola.balanceOf(gov), initialGovDola, "Gov DOLA balance didn't increase");
    }

    function testburnRemainingDolaSupply_Success() public {
        vm.startPrank(chair);
        fed.expansion(1000 ether);
        vm.stopPrank();       
        vm.startPrank(minter);
        dola.mint(address(minter), 1000 ether);
        dola.approve(address(fed), 1000 ether);

        fed.burnRemainingDolaSupply();
        assertEq(fed.dolaSupply(), 0);
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

    function testSetMaxLossWithdrawBps_succeed_whenCalledByGov() public {
        uint initial = fed.maxLossWithdrawBps();
        
        vm.prank(gov);
        fed.setMaxLossWithdrawBps(1);

        assertEq(fed.maxLossWithdrawBps(), 1);
        assertTrue(initial != fed.maxLossWithdrawBps());
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
        
        vm.expectRevert("ONLY GOV");
        fed.setMaxLossExpansionBps(1);

        assertEq(fed.maxLossExpansionBps(), initial);
    }

    function testSetMaxLossWithdrawBps_fail_whenCalledByGov() public {
        uint initial = fed.maxLossWithdrawBps();
        
        vm.expectRevert("ONLY GOV");
        fed.setMaxLossWithdrawBps(1);

        assertEq(fed.maxLossWithdrawBps(), initial);
    }

    function testSetMaxLossTakeProfitBps_fail_whenCalledByGov() public {
        uint initial = fed.maxLossTakeProfitBps();
        
        vm.expectRevert("ONLY GOV");
        fed.setMaxLossTakeProfitBps(1);

        assertEq(fed.maxLossTakeProfitBps(), initial);
    }

    function washTrade(uint loops, uint amount) public {
        vm.stopPrank();     
        vm.startPrank(minter);
        dola.mint(address(swapper), amount);
        //Trade back and forth to create a profit
        for(uint i; i < loops; i++){
            swapper.swapExact(address(dola), address(bpt), dola.balanceOf(address(swapper)));
            swapper.swapExact(address(bpt), address(dola), bpt.balanceOf(address(swapper)));
        }
        vm.stopPrank();     
    }
}
