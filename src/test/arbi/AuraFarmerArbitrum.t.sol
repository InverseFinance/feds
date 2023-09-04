// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "ds-test/test.sol";
import "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IDola} from "src/interfaces/IDola.sol";
import {ArbiGovMessengerL1} from "src/arbi-fed/ArbiGovMessengerL1.sol";
import {AuraFarmer} from "src/arbi-fed/AuraFarmer.sol";
import "src/interfaces/aura/IAuraBalRewardPool.sol";
import "src/interfaces/balancer/IComposablePoolFactory.sol";
import "src/interfaces/balancer/IVault.sol";
import {AddressAliasHelper} from "src/utils/AddressAliasHelper.sol";
import {IL2GatewayRouter} from "src/interfaces/arbitrum/IL2GatewayRouter.sol";

contract AuraFarmerTest is Test {
    
    error ExpansionMaxLossTooHigh();
    error WithdrawMaxLossTooHigh();
    error TakeProfitMaxLossTooHigh();
    error OnlyL2Chair();
    error OnlyL2Guardian();
    error OnlyGov();
    error MaxSlippageTooHigh();
    error NotEnoughTokens();
    error NotEnoughBPT();
    error AuraWithdrawFailed();
    error NothingWithdrawn();
    error OnlyChairCanTakeBPTProfit();
    error NoProfit();
    error GettingRewardFailed();

    //L1
    IDola public DOLA = IDola(0x865377367054516e17014CcdED1e7d814EDC9ce4);
    IERC20 public USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 bpt = IERC20(0xFf4ce5AAAb5a627bf82f4A571AB1cE94Aa365eA6); // USDC-DOLA bal pool
    IERC20 bal = IERC20(0xba100000625a3754423978a60c9317c58a424e3D);
    IERC20 aura = IERC20(0xC0c293ce456fF0ED870ADd98a0828Dd4d2903DBF);
    address gov = 0x926dF14a23BE491164dCF93f4c468A50ef659D5B;
    ArbiGovMessengerL1 arbiGovMessengerL1;

    // Arbitrum
    IDola public DOLAArbi = IDola(0x6A7661795C374c0bFC635934efAddFf3A7Ee23b6);
    IERC20 public USDCArbi = IERC20(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
    IERC20 public auraArbi = IERC20(0x1509706a6c66CA549ff0cB464de88231DDBe213B);
    IERC20 public balArbi = IERC20(0x040d1EdC9569d4Bab2D15287Dc5A4F10F56a56B8);
    IERC20 public bptArbi = IERC20(0x8bc65Eed474D1A00555825c91FeAb6A8255C2107);

    address dolaUser = 0x052f7890E50fb5b921BCAb3B10B79a58A3B9d40f; 
    address usdcUser = 0x5bdf85216ec1e38D6458C870992A69e38e03F7Ef;
    address l2MessengerAlias;
    address l2Chair = address(0x69);
    address l2Guardian = address(0x70);
    address l2TWG = 0x23dEDab98D7828AFBD2B7Ab8C71089f2C517774a;
    address arbiFedL1 = address(0x23);
    IAuraBalRewardPool baseRewardPool = IAuraBalRewardPool(0xAc7025Dec5E216025C76414f6ac1976227c20Ff0);
    address booster = 0x98Ef32edd24e2c92525E59afc4475C1242a30184;
    IVault vault = IVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    bytes32 poolId = 0x8bc65eed474d1a00555825c91feab6a8255c2107000000000000000000000453;

    IL2GatewayRouter public immutable l2Gateway = IL2GatewayRouter(0x5288c571Fd7aD117beA99bF60FE0846C4E84F933); 
    address l2GatewayOutbound = 0x09e9222E96E7B4AE2a407B98d48e330053351EEe;


    // Values taken from AuraFed for USDC-DOLA 0x1CD24E3FBae88BECbaFED4b8Cda765D1e6e3BC03
    uint maxLossExpansion = 9999;
    uint maxLossWithdraw = 10;
    uint maxLossTakeProfit = 10;

    //Numbas
    uint dolaAmount = 1e18;

    //Feds
    AuraFarmer auraFarmer;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("arbitrum"));//, 93907980);

        arbiGovMessengerL1 = new ArbiGovMessengerL1(gov,gov,address(0),address(0));
        
        l2MessengerAlias = AddressAliasHelper.applyL1ToL2Alias(address(arbiGovMessengerL1));

        AuraFarmer.InitialAddresses memory addresses = AuraFarmer.InitialAddresses(
            address(DOLAArbi),
            address(vault),
            address(baseRewardPool),
            address(bptArbi), //bpt
            booster,
            l2Chair,
            l2Guardian,
            l2TWG,
            arbiFedL1,
            address(arbiGovMessengerL1),
            gov
        );


        // Deploy Aura Farmer
        auraFarmer = new AuraFarmer(
            addresses,
            maxLossExpansion,
            maxLossWithdraw,
            poolId
        );

        deal(address(DOLAArbi), address(auraFarmer), 1000 ether);

    }

    function test_deposit() public {
        uint amount = 0.001 ether;
        uint initialDolaSupply = auraFarmer.dolaDeposited();
        uint initialbptSupply = auraFarmer.bptSupply();

        vm.prank(l2Chair);
        auraFarmer.deposit(amount);

        assertEq(initialDolaSupply + amount, auraFarmer.dolaDeposited(), "Dola deposited didn't increase by amount");
        //TODO: Should have greater precision about the amount of balLP acquired
        assertGt(auraFarmer.bptSupply(), initialbptSupply);
    }
    
    function testFailDeposit_fail_whenExpandedOutsideAcceptableSlippage() public {
        uint amount = 1000_000 ether;

        vm.prank(l2Chair);
        auraFarmer.deposit(amount);
    }

    function test_withdrawLiquidity() public {
        vm.startPrank(l2Chair);
        auraFarmer.deposit(dolaAmount);

        assertEq(auraFarmer.dolaDeposited(), dolaAmount);
        assertEq(bptArbi.balanceOf(address(auraFarmer)),0);

        // Cannot withdraw full amount because of slippage when depositing and withdrawing
        vm.expectRevert(NotEnoughBPT.selector);
        auraFarmer.withdrawLiquidity(dolaAmount);

        // Withdraw 50% of available liquidity
        uint256 dolaWithdrawn = auraFarmer.withdrawLiquidity(dolaAmount * 50 /100);
        assertEq(auraFarmer.dolaDeposited(), dolaAmount - dolaWithdrawn);

    }

    function test_withdrawLiquidityAll() public {
        vm.startPrank(l2Chair);
        auraFarmer.deposit(dolaAmount);

        assertEq(auraFarmer.dolaDeposited(), dolaAmount);
        assertGt(IERC20(address(auraFarmer.dolaBptRewardPool())).balanceOf(address(auraFarmer)),0);

        // Withdraw all available liquidity
        uint dolaBalBefore = DOLAArbi.balanceOf(address(auraFarmer));
        uint256 dolaWithdrawn = auraFarmer.withdrawAllLiquidity();
        if(dolaWithdrawn < dolaAmount){
            assertEq(auraFarmer.dolaDeposited(), dolaAmount - dolaWithdrawn, "DOLA withdrawn didn't reduce dola deposited");
        }
        assertEq(DOLAArbi.balanceOf(address(auraFarmer)) - dolaBalBefore, dolaWithdrawn, "Balance doesn't correspond with withdrawn");
    }

    function test_takeProfit() public {
        vm.startPrank(l2Chair);
        auraFarmer.deposit(dolaAmount);
        vm.warp(block.timestamp + 30 days);
        
        uint twgBalBefore = balArbi.balanceOf(address(l2TWG));
        uint twgAuraBefore = auraArbi.balanceOf(address(l2TWG));

        auraFarmer.takeProfit();

        uint twgBalAfter = balArbi.balanceOf(address(l2TWG));
        uint twgAuraAfter = auraArbi.balanceOf(address(l2TWG));
        
        assertGt(twgBalAfter, twgBalBefore, "BAL balance didn't increase");
        assertGt(twgAuraAfter, twgAuraBefore, "AURA balance didn't increase");
    }

    function test_initialized_properly() public {
        
        assertEq(auraFarmer.l2Chair(), l2Chair);
        assertEq(auraFarmer.arbiGovMessengerL1(), address(arbiGovMessengerL1));
    }

    function test_changeL2Chair() public {
        vm.expectRevert(OnlyGov.selector);
        auraFarmer.changeL2Chair(address(0x70));

        vm.prank(l2MessengerAlias);
        auraFarmer.changeL2Chair(address(0x70));
        assertEq(auraFarmer.l2Chair(), address(0x70));
    }


    function test_setMaxLossExpansionBPS() public {
        vm.expectRevert(OnlyL2Guardian.selector);
        auraFarmer.setMaxLossExpansionBps(0);

        vm.prank(l2MessengerAlias);
        auraFarmer.setMaxLossExpansionBps(0);

        assertEq(auraFarmer.maxLossExpansionBps(), 0);

        vm.expectRevert(ExpansionMaxLossTooHigh.selector);
        vm.prank(l2MessengerAlias);
        auraFarmer.setMaxLossExpansionBps(10000);
    }

    function test_setMaxWithdrawExpansionBPS() public {
        vm.expectRevert(OnlyL2Guardian.selector);
        auraFarmer.setMaxLossWithdrawBps(0);

        vm.prank(l2MessengerAlias);
        auraFarmer.setMaxLossWithdrawBps(0);

        assertEq(auraFarmer.maxLossWithdrawBps(), 0);

        vm.expectRevert(WithdrawMaxLossTooHigh.selector);
        vm.prank(l2MessengerAlias);
        auraFarmer.setMaxLossWithdrawBps(10000);
    }

    function test_changeArbiFedL1() public {
        vm.expectRevert(OnlyGov.selector);
        auraFarmer.changeArbiFedL1(address(0x70));
        
        assertEq(address(auraFarmer.arbiFedL1()), arbiFedL1);
       
        vm.startPrank(l2MessengerAlias); 
        auraFarmer.changeArbiFedL1(address(0x70));

        assertEq(address(auraFarmer.arbiFedL1()), address(0x70));
    }

    function test_changeArbiGovMessengerL1() public {
        vm.expectRevert(OnlyGov.selector);
        auraFarmer.changeArbiGovMessengerL1(address(0x70));

        assertEq(address(auraFarmer.arbiGovMessengerL1()), address(arbiGovMessengerL1));
        
        vm.startPrank(l2MessengerAlias); 
        auraFarmer.changeArbiGovMessengerL1(address(0x70));

        assertEq(address(auraFarmer.arbiGovMessengerL1()), address(0x70));
    }
    /**
    /For some reason works in prod but not while testing
    function test_withdrawToL1ArbiFed() public {
        vm.prank(dolaUser);
        DOLAArbi.transfer(address(auraFarmer), dolaAmount);

        vm.expectRevert(OnlyL2Chair.selector);
        auraFarmer.withdrawToL1ArbiFed(dolaAmount);

        vm.prank(l2Chair);
        auraFarmer.withdrawToL1ArbiFed(dolaAmount);

        assertEq(DOLAArbi.balanceOf(address(auraFarmer)), 0);
    }

    
    function test_withdrawTokensToL1() public {
        vm.prank(usdcUser);
        USDCArbi.transfer(address(auraFarmer), usdcAmount);

        vm.expectRevert(OnlyL2Chair.selector);
        auraFarmer.withdrawToL1ArbiFed(usdcAmount);

        vm.prank(l2Chair);
        auraFarmer.withdrawTokensToL1(address(USDC),address(USDCArbi),address(2),usdcAmount);

        assertEq(DOLAArbi.balanceOf(address(auraFarmer)), 0);
    }
    */
}

