// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {FundVault} from "../src/FundVault.sol";
import {MockUSDC} from "./MockUSDC.sol";

contract FundVaultTest is Test {
    FundVault v;
    MockUSDC usdc;

    address owner = makeAddr("owner");
    address operator = makeAddr("operator");
    address manager = makeAddr("manager");
    address feeTo = makeAddr("feeRecipient");
    address treasury = makeAddr("treasury");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address stranger = makeAddr("stranger");

    uint256 constant USD = 1e6;
    uint256 constant SH = 1e18;
    uint256 constant RATE = 1600e6;

    function setUp() public {
        usdc = new MockUSDC();
        v = new FundVault(address(usdc), owner, operator, manager, feeTo, treasury, 1500, 1 * USD, 0, 0);
        for (uint256 i = 0; i < 3; i++) {
            address m = [alice, bob, feeTo][i];
            usdc.mint(m, 10_000 * USD);
            vm.prank(m); usdc.approve(address(v), type(uint256).max);
            vm.prank(manager); v.setAllowed(m, true);
        }
        usdc.mint(treasury, 100_000 * USD);
        vm.prank(treasury); usdc.approve(address(v), type(uint256).max);
    }

    // ---------------------------------------------------------------- helpers
    function deposit(address m, uint256 usd) internal { vm.prank(m); v.requestDeposit(usd); }
    function redeem(address m, uint256 shares) internal { vm.prank(m); v.requestRedeem(shares); }
    function settle(uint256 nav) internal { vm.prank(operator); v.settle(nav, RATE); _invariant(); }
    function _invariant() internal view {
        assertEq(usdc.balanceOf(address(v)), v.totalPendingDeposits() + v.totalClaimable(), "vault holds only queued + claimable");
        assertEq(v.balanceOf(address(v)), v.totalPendingRedeem(), "escrow = queued shares");
    }
    function warp(uint256 dt) internal { vm.warp(block.timestamp + dt); }

    // ---------------------------------------------------------------- round trips
    function test_roundTripAtOneDollar() public {
        deposit(alice, 100 * USD);
        assertEq(usdc.balanceOf(address(v)), 100 * USD);
        settle(0);
        assertEq(v.balanceOf(alice), 100 * SH);
        assertEq(usdc.balanceOf(treasury), 100_100 * USD);   // deposit went to the treasury
        assertEq(v.costBasis(alice), 100 * USD);

        redeem(alice, 100 * SH);
        warp(1 days);
        settle(100 * USD);
        assertEq(v.balanceOf(alice), 0);
        assertEq(v.totalSupply(), 0);
        assertEq(usdc.balanceOf(alice), 10_000 * USD);        // all back, no fee at $1.00
        assertEq(v.feesPaid(alice), 0);
    }

    function test_roundTripAtMovedPrice() public {
        deposit(alice, 100 * USD); settle(0);
        warp(1 days);
        deposit(bob, 60 * USD);
        redeem(alice, 100 * SH);
        settle(120 * USD);                                   // price $1.20
        // alice: gross 120, profit 20, fee 3 (15%), paid 117
        assertEq(usdc.balanceOf(alice), 10_000 * USD + 17 * USD);
        assertEq(v.feesPaid(alice), 3 * USD);
        assertEq(v.balanceOf(feeTo), 2.5e18);                // fee as shares: $3 at $1.20
        // bob: 60 / 1.20 = 50 shares
        assertEq(v.balanceOf(bob), 50 * SH);
        assertEq(v.totalSupply(), 52.5e18);
        assertEq(v.lastNav(), 63 * USD);                     // 120 + 60 - 117
    }

    // ---------------------------------------------------------------- fee
    function test_feeOnlyOnProfit() public {
        deposit(alice, 100 * USD); settle(0);
        warp(1 days);
        redeem(alice, 100 * SH);
        settle(80 * USD);                                    // price $0.80: a loss
        assertEq(usdc.balanceOf(alice), 10_000 * USD - 20 * USD);
        assertEq(v.feesPaid(alice), 0);
        assertEq(v.balanceOf(feeTo), 0);
    }

    function test_partialRedemptionCostBasis() public {
        deposit(alice, 100 * USD); settle(0);
        warp(1 days);
        redeem(alice, 50 * SH);
        settle(120 * USD);
        // gross 60, cost part 50, fee 1.50, paid 58.50
        assertEq(usdc.balanceOf(alice), 10_000 * USD - 100 * USD + 58.5e6);
        assertEq(v.costBasis(alice), 50 * USD);
        assertEq(v.feesPaid(alice), 1.5e6);
        assertEq(v.balanceOf(alice), 50 * SH);
        // a second partial at the same price charges fee only on that half's profit
        warp(1 days);
        redeem(alice, 25 * SH);
        settle(61.5e6);                                      // 51.25 shares at $1.20
        assertEq(v.costBasis(alice), 25 * USD);
        assertEq(v.feesPaid(alice), 1.5e6 + 0.75e6);
    }

    function test_feeRecipientPaysNoFee() public {
        deposit(feeTo, 100 * USD); settle(0);
        warp(1 days);
        redeem(feeTo, 100 * SH);
        settle(125 * USD);
        assertEq(usdc.balanceOf(feeTo), 10_000 * USD + 25 * USD);
        assertEq(v.feesPaid(feeTo), 0);
    }

    function test_feeCap() public {
        vm.prank(manager); vm.expectRevert(FundVault.FeeTooHigh.selector); v.queueChange(FundVault.Kind.Fee, 2001);
        vm.prank(manager); v.queueChange(FundVault.Kind.Fee, 2000);
        vm.expectRevert(FundVault.FeeTooHigh.selector);
        new FundVault(address(usdc), owner, operator, manager, feeTo, treasury, 2001, 0, 0, 0);
    }

    // ---------------------------------------------------------------- pause, cancel, claim
    function test_cancelAndClaimWhilePaused() public {
        deposit(alice, 100 * USD); settle(0);
        deposit(alice, 40 * USD);
        redeem(alice, 30 * SH);
        vm.prank(manager); v.pause();

        vm.prank(alice); vm.expectRevert(FundVault.IsPaused.selector); v.requestDeposit(1 * USD);
        vm.prank(alice); vm.expectRevert(FundVault.IsPaused.selector); v.requestRedeem(1 * SH);
        vm.prank(operator); vm.expectRevert(FundVault.IsPaused.selector); v.settle(100 * USD, RATE);
        vm.prank(operator); vm.expectRevert(FundVault.IsPaused.selector); v.reportValue(100 * USD);

        vm.prank(alice); v.cancelDeposit();
        vm.prank(alice); v.cancelRedeem();
        assertEq(usdc.balanceOf(alice), 9_900 * USD);
        assertEq(v.balanceOf(alice), 100 * SH);
        _invariant();
    }

    function test_ownerPauseOnlyOwnerLifts() public {
        vm.prank(owner); v.pause();
        vm.prank(manager); vm.expectRevert(FundVault.Unauthorized.selector); v.unpause();
        vm.prank(owner); v.unpause();
        vm.prank(manager); v.pause();
        vm.prank(manager); v.unpause();
        vm.prank(stranger); vm.expectRevert(FundVault.Unauthorized.selector); v.pause();
    }

    function test_claimableFallback() public {
        deposit(alice, 100 * USD); deposit(bob, 100 * USD); settle(0);
        warp(1 days);
        redeem(alice, 100 * SH); redeem(bob, 100 * SH);
        usdc.setBlocked(alice, true);
        settle(200 * USD);                                   // alice's payout fails, bob's still goes out
        assertEq(v.claimable(alice), 100 * USD);
        assertEq(usdc.balanceOf(bob), 10_000 * USD);
        vm.prank(manager); v.pause();
        usdc.setBlocked(alice, false);
        vm.prank(alice); v.claim();                          // claim works while paused
        assertEq(usdc.balanceOf(alice), 10_000 * USD);
        _invariant();
    }

    // ---------------------------------------------------------------- value-jump guard
    function test_valueJumpGuard() public {
        deposit(alice, 100 * USD); settle(0);
        vm.prank(operator); vm.expectRevert(FundVault.ValueJump.selector); v.reportValue(125.01e6);
        vm.prank(operator); vm.expectRevert(FundVault.ValueJump.selector); v.reportValue(74.99e6);
        vm.prank(operator); v.reportValue(125 * USD);          // exactly 25% is allowed
        // still inside the same day: the reference stays at $1.00
        warp(12 hours);
        vm.prank(operator); vm.expectRevert(FundVault.ValueJump.selector); v.reportValue(130 * USD);
        // a new window starts from the last price ($1.25)
        warp(13 hours);
        vm.prank(operator); v.reportValue(150 * USD);
        assertEq(v.lastPrice(), 1.5e6);
        // settle obeys the guard too
        vm.prank(operator); vm.expectRevert(FundVault.ValueJump.selector); v.settle(10 * USD, RATE);
    }

    // ---------------------------------------------------------------- queue limit
    function test_queueLimit() public {
        for (uint256 i = 0; i < 100; i++) {
            address m = address(uint160(0x1000 + i));
            usdc.mint(m, 10 * USD);
            vm.prank(m); usdc.approve(address(v), type(uint256).max);
            vm.prank(manager); v.setAllowed(m, true);
            deposit(m, 1 * USD);
        }
        vm.prank(alice); vm.expectRevert(FundVault.QueueFull.selector); v.requestDeposit(1 * USD);
        address first = address(uint160(0x1000));
        deposit(first, 1 * USD);                             // topping up an existing entry is fine
        uint256 g = gasleft();
        settle(0);
        emit log_named_uint("settle gas, 100 deposits", g - gasleft());
        // 100 redemptions + 100 deposits in one settlement
        warp(1 days);
        for (uint256 i = 0; i < 100; i++) redeem(address(uint160(0x1000 + i)), 1 * SH);
        for (uint256 i = 0; i < 100; i++) deposit(address(uint160(0x1000 + i)), 1 * USD);
        g = gasleft();
        settle(101 * USD);
        uint256 used = g - gasleft();
        emit log_named_uint("settle gas, 100 + 100", used);
        assertLt(used, 15_000_000);
    }

    // ---------------------------------------------------------------- limits and allow-list
    function test_limitsAndAllowList() public {
        vm.prank(stranger); usdc.approve(address(v), type(uint256).max);
        vm.prank(stranger); vm.expectRevert(FundVault.NotAllowed.selector); v.requestDeposit(10 * USD);
        vm.prank(alice); vm.expectRevert(FundVault.BadAmount.selector); v.requestDeposit(0.5e6);
        vm.prank(manager); v.setLimits(1 * USD, 50 * USD, 0);
        deposit(alice, 30 * USD);
        vm.prank(alice); vm.expectRevert(FundVault.OverLimit.selector); v.requestDeposit(21 * USD);
        deposit(alice, 20 * USD);
        settle(0);
        vm.prank(alice); vm.expectRevert(FundVault.OverLimit.selector); v.requestDeposit(1 * USD);
        vm.prank(manager); v.setLimits(1 * USD, 0, 60 * USD);
        vm.prank(bob); vm.expectRevert(FundVault.OverLimit.selector); v.requestDeposit(11 * USD);
        deposit(bob, 10 * USD);
        // a removed wallet can still redeem and cancel
        vm.prank(manager); v.setAllowed(bob, false);
        vm.prank(bob); v.cancelDeposit();
        vm.prank(manager); v.setAllowed(alice, false);
        redeem(alice, 10 * SH);
        vm.prank(stranger); vm.expectRevert(FundVault.Unauthorized.selector); v.setAllowed(stranger, true);
        vm.prank(stranger); vm.expectRevert(FundVault.Unauthorized.selector); v.setLimits(0, 0, 0);
    }

    // ---------------------------------------------------------------- delayed changes
    function _roleChange(FundVault.Kind kind, address by, uint256 value) internal {
        vm.prank(stranger); vm.expectRevert(FundVault.Unauthorized.selector); v.queueChange(kind, value);
        address wrong = by == owner ? manager : owner;
        vm.prank(wrong); vm.expectRevert(FundVault.Unauthorized.selector); v.queueChange(kind, value);
        vm.prank(by); uint256 id = v.queueChange(kind, value);
        vm.expectRevert(FundVault.TooEarly.selector); v.executeChange(id);
        warp(48 hours - 1);
        vm.expectRevert(FundVault.TooEarly.selector); v.executeChange(id);
        warp(1);
        vm.prank(stranger); v.executeChange(id);              // anyone can execute after the delay
        vm.expectRevert(FundVault.BadChange.selector); v.executeChange(id);
    }

    function test_everyChangeWaits48h() public {
        address n = makeAddr("new");
        _roleChange(FundVault.Kind.Operator, owner, uint160(n)); assertEq(v.operator(), n);
        _roleChange(FundVault.Kind.Manager, owner, uint160(n)); assertEq(v.manager(), n);
        manager = n;
        _roleChange(FundVault.Kind.FeeRecipient, owner, uint160(n)); assertEq(v.feeRecipient(), n);
        _roleChange(FundVault.Kind.MaxNavChange, owner, 1000); assertEq(v.maxNavChangeBps(), 1000);
        _roleChange(FundVault.Kind.Treasury, owner, uint160(makeAddr("t2"))); assertEq(v.treasury(), makeAddr("t2"));
        _roleChange(FundVault.Kind.Fee, manager, 1000); assertEq(v.feeBps(), 1000);
        _roleChange(FundVault.Kind.Owner, owner, uint160(n)); assertEq(v.owner(), n);
    }

    function test_cancelChange() public {
        vm.prank(owner); uint256 id = v.queueChange(FundVault.Kind.Operator, uint160(stranger));
        vm.prank(stranger); vm.expectRevert(FundVault.Unauthorized.selector); v.cancelChange(id);
        vm.prank(manager); v.cancelChange(id);               // the manager can cancel a change they did not queue
        warp(48 hours);
        vm.expectRevert(FundVault.BadChange.selector); v.executeChange(id);
        vm.prank(manager); uint256 id2 = v.queueChange(FundVault.Kind.Fee, 500);
        vm.prank(owner); v.cancelChange(id2);
        assertEq(v.feeBps(), 1500);
    }

    function test_ownerNeverTheBotWallet() public {
        vm.expectRevert(FundVault.NotAllowed.selector);
        new FundVault(address(usdc), treasury, operator, manager, feeTo, treasury, 1500, 0, 0, 0);
        vm.prank(owner); vm.expectRevert(FundVault.BadChange.selector); v.queueChange(FundVault.Kind.Owner, uint160(treasury));
        vm.prank(owner); vm.expectRevert(FundVault.BadChange.selector); v.queueChange(FundVault.Kind.Treasury, uint160(owner));
    }

    // ---------------------------------------------------------------- non-transferable
    function test_nonTransferable() public {
        deposit(alice, 10 * USD); settle(0);
        vm.prank(alice); vm.expectRevert(FundVault.NonTransferable.selector); v.transfer(bob, 1);
        vm.prank(alice); vm.expectRevert(FundVault.NonTransferable.selector); v.transferFrom(alice, bob, 1);
        vm.prank(alice); vm.expectRevert(FundVault.NonTransferable.selector); v.approve(bob, 1);
        assertEq(v.allowance(alice, bob), 0);
    }

    // ---------------------------------------------------------------- settlement netting
    function test_settleDepositsExceedPayouts() public {
        deposit(alice, 100 * USD); settle(0);
        warp(1 days);
        redeem(alice, 10 * SH);
        deposit(bob, 50 * USD);
        uint256 t0 = usdc.balanceOf(treasury);
        settle(100 * USD);
        assertEq(usdc.balanceOf(treasury), t0 + 40 * USD);   // 50 in, 10 out
        assertEq(usdc.balanceOf(alice), 10_000 * USD - 90 * USD);
    }

    function test_settlePayoutsExceedDeposits() public {
        deposit(alice, 100 * USD); settle(0);
        warp(1 days);
        redeem(alice, 80 * SH);
        deposit(bob, 20 * USD);
        uint256 t0 = usdc.balanceOf(treasury);
        settle(100 * USD);
        assertEq(usdc.balanceOf(treasury), t0 - 60 * USD);   // 80 out, 20 in
        assertEq(usdc.balanceOf(alice), 10_000 * USD - 20 * USD);
    }

    function test_settleRevertsWhenTreasuryShort() public {
        deposit(alice, 100 * USD); settle(0);
        redeem(alice, 100 * SH);
        vm.prank(treasury); usdc.approve(address(v), 0);
        vm.prank(operator); vm.expectRevert(FundVault.TransferFailed.selector); v.settle(100 * USD, RATE);
        assertEq(v.pendingRedeem(alice), 100 * SH);          // nothing changed; retry later
    }

    function test_emptyFundSettle() public {
        settle(0);
        assertEq(v.totalSupply(), 0);
        warp(1 days);
        settle(0);
        vm.prank(stranger); vm.expectRevert(FundVault.Unauthorized.selector); v.settle(0, RATE);
    }

    // ---------------------------------------------------------------- opening shares
    function test_openingShares() public {
        vm.prank(manager); v.openingShares(manager, 40 * USD);
        assertEq(v.balanceOf(manager), 40 * SH);
        vm.prank(manager); vm.expectRevert(FundVault.NotAllowed.selector); v.openingShares(manager, 1 * USD);
        deposit(alice, 10 * USD);
        settle(44 * USD);                                    // price $1.10
        assertEq(v.balanceOf(alice), uint256(10 * USD) * 40 * SH / (44 * USD));
        FundVault v2 = new FundVault(address(usdc), owner, operator, manager, feeTo, treasury, 1500, 0, 0, 0);
        vm.prank(manager); v2.setAllowed(alice, true);
        vm.prank(alice); usdc.approve(address(v2), type(uint256).max);
        vm.prank(alice); v2.requestDeposit(5 * USD);
        vm.prank(operator); v2.settle(0, RATE);
        vm.prank(manager); vm.expectRevert(FundVault.NotAllowed.selector); v2.openingShares(manager, 1 * USD);
    }

    // ---------------------------------------------------------------- naira rate is stored on chain
    function test_settledEventCarriesNairaRate() public {
        deposit(alice, 10 * USD);
        vm.expectEmit(address(v));
        emit FundVault.Settled(0, 0, 1e6, RATE, 10 * USD, 0, 10 * USD, 10 * SH);
        settle(0);
    }

    // ---------------------------------------------------------------- fuzz: settlement keeps the books
    function testFuzz_settleKeepsBooks(uint64 a, uint64 b, uint16 moveBps, uint16 redeemBps) public {
        a = uint64(bound(a, 1 * USD, 5_000 * USD));
        b = uint64(bound(b, 1 * USD, 5_000 * USD));
        moveBps = uint16(bound(moveBps, 7600, 12400));
        redeemBps = uint16(bound(redeemBps, 1, 10_000));
        deposit(alice, a); settle(0);
        warp(1 days);
        uint256 nav = uint256(a) * moveBps / 10_000;
        if (nav == 0) return;
        uint256 s = v.balanceOf(alice) * redeemBps / 10_000;
        if (s == 0) return;
        redeem(alice, s);
        deposit(bob, b);
        uint256 t0 = usdc.balanceOf(treasury);
        settle(nav);
        // treasury change = deposits - payouts, and the fund's books match
        uint256 paid = usdc.balanceOf(alice) - (10_000 * USD - a);
        assertEq(int256(usdc.balanceOf(treasury)) - int256(t0), int256(uint256(b)) - int256(paid));
        assertEq(v.lastNav(), nav + b - paid);
        assertLe(paid, uint256(a) * moveBps / 10_000);
    }
}
