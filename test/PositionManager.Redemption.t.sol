// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/console.sol";
import { IPositionManager } from "../contracts/Interfaces/IPositionManager.sol";
import { IRToken } from "../contracts/Interfaces/IRToken.sol";
import { MathUtils } from "../contracts/Dependencies/MathUtils.sol";
import { PositionManager } from "../contracts/PositionManager.sol";
import { SplitLiquidationCollateral } from "../contracts/SplitLiquidationCollateral.sol";
import { PriceFeedTestnet } from "./mocks/PriceFeedTestnet.sol";
import { PositionManagerUtils } from "./utils/PositionManagerUtils.sol";
import { TestSetup } from "./utils/TestSetup.t.sol";

contract PositionManagerRedistributionTest is TestSetup {
    PriceFeedTestnet public priceFeed;
    IRToken public rToken;

    function setUp() public override {
        super.setUp();

        priceFeed = new PriceFeedTestnet();
        positionManager.addCollateralToken(collateralToken, priceFeed);

        rToken = positionManager.rToken();

        collateralToken.mint(ALICE, 10e36);
        collateralToken.mint(BOB, 10e36);
        collateralToken.mint(CAROL, 10e36);
        collateralToken.mint(DAVE, 10e36);
        collateralToken.mint(EVE, 10e36);
    }
    // User to be liquidated sells his R tokens and collects redistribution fees
    function testRedistributeAndCollect() public {
        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            position: ALICE,
            icr: 20e18
        });
        vm.stopPrank();

        vm.startPrank(BOB);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            position: BOB,
            icr: 4e18
        });
        vm.stopPrank();

        uint256 price = priceFeed.getPrice();

        uint256 icrBefore = PositionManagerUtils.getCurrentICR(positionManager, collateralToken, BOB, price);
        assertEq(icrBefore, 4e18);

        // Bob increases debt to 180 R, lowering his ICR to 1.11
        uint256 targetICR = 1_111_111_111_111_111_111;
        vm.startPrank(BOB);
        PositionManagerUtils.withdrawDebt({
            positionManager: positionManager,
            collateralToken: collateralToken,
            priceFeed: priceFeed,
            position: BOB,
            icr: targetICR
        });
        vm.stopPrank();

        uint256 icrAfter = PositionManagerUtils.getCurrentICR(positionManager, collateralToken, BOB, price);
        assertEq(icrAfter, targetICR);

        // price drops to 1ETH:100R, reducing Bob's ICR below MCR
        priceFeed.setPrice(100e18);

        vm.startPrank(BOB);
        uint256 previousBobBalance = collateralToken.balanceOf(BOB);
        vm.stopPrank();

        vm.startPrank(BOB);
        // liquidate position
        positionManager.liquidate(collateralToken, BOB);
        vm.stopPrank();
        uint256 currentBobBalance = collateralToken.balanceOf(BOB);
        console.log(currentBobBalance - previousBobBalance);
        assertGe(currentBobBalance - previousBobBalance, 0);
    }
    // Closes a position that has ICR < 100%
    function testSuccessfulPositionRedistributionICRLessThan100Percent() public {
        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            position: ALICE,
            icr: 20e18
        });
        vm.stopPrank();

        vm.startPrank(BOB);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            position: BOB,
            icr: 4e18
        });
        vm.stopPrank();

        uint256 price = priceFeed.getPrice();

        uint256 icrBefore = PositionManagerUtils.getCurrentICR(positionManager, collateralToken, BOB, price);
        assertEq(icrBefore, 4e18);

        // Bob increases debt to 180 R, lowering his ICR to 1.11
        uint256 targetICR = 1_111_111_111_111_111_111;
        vm.startPrank(BOB);
        PositionManagerUtils.withdrawDebt({
            positionManager: positionManager,
            collateralToken: collateralToken,
            priceFeed: priceFeed,
            position: BOB,
            icr: targetICR
        });
        vm.stopPrank();

        uint256 icrAfter = PositionManagerUtils.getCurrentICR(positionManager, collateralToken, BOB, price);
        assertEq(icrAfter, targetICR);

        // price drops to 1ETH:100R, reducing Bob's ICR below MCR
        priceFeed.setPrice(100e18);

        // liquidate position
        positionManager.liquidate(collateralToken, BOB);

        // Bob's position is closed
        assertEq(positionManager.raftDebtToken().balanceOf(BOB), 0);
    }

    // Closes a position that has ICR = 100%
    function testSuccessfulPositionRedistributionICREqualTo100Percent() public {
        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            position: ALICE,
            icr: 20e18
        });
        vm.stopPrank();

        vm.startPrank(BOB);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            position: BOB,
            icr: 4e18
        });
        vm.stopPrank();

        // price drops to 1ETH:50R, reducing Bob's ICR = 100%
        priceFeed.setPrice(50e18);
        uint256 price = priceFeed.getPrice();

        uint256 bobICR = PositionManagerUtils.getCurrentICR(positionManager, collateralToken, BOB, price);
        assertEq(bobICR, 1e18);

        // liquidate position
        positionManager.liquidate(collateralToken, BOB);

        // Bob's position is closed
        assertEq(positionManager.raftDebtToken().balanceOf(BOB), 0);
    }

    function testRedistributeLastDebt() public {
        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            position: ALICE,
            icr: 20e18
        });
        vm.stopPrank();

        uint256 price = priceFeed.getPrice();

        // Bob increases debt to 180 R, lowering his ICR to 1.11
        uint256 targetICR = 1_111_111_111_111_111_111;
        vm.startPrank(ALICE);
        PositionManagerUtils.withdrawDebt({
            positionManager: positionManager,
            collateralToken: collateralToken,
            priceFeed: priceFeed,
            position: ALICE,
            icr: targetICR
        });
        vm.stopPrank();

        uint256 icrAfter = PositionManagerUtils.getCurrentICR(positionManager, collateralToken, ALICE, price);
        assertEq(icrAfter, targetICR);

        // price drops to 1ETH:100R, reducing Bob's ICR below MCR
        priceFeed.setPrice(100e18);

        // liquidate position
        vm.expectRevert(IPositionManager.CannotLiquidateLastPosition.selector);
        positionManager.liquidate(collateralToken, ALICE);
    }

    // Liquidates undercollateralized position if there are two positions in the system
    function testSuccessfulRedistributionTwoPositionsSystem() public {
        vm.prank(address(positionManager));
        rToken.mint(address(this), 1_000_000e18);

        vm.startPrank(BOB);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            position: BOB,
            extraDebtAmount: 0,
            icr: 200e18,
            amount: 100 ether
        });
        vm.stopPrank();

        // Alice creates a single position with 0.7 ETH and a debt of 70 R
        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            position: ALICE,
            icr: 2e18
        });
        vm.stopPrank();

        // Set ETH:USD price to 105
        priceFeed.setPrice(90e18);
        uint256 price = priceFeed.getPrice();

        uint256 aliceICR = PositionManagerUtils.getCurrentICR(positionManager, collateralToken, ALICE, price);
        assertEq(aliceICR, 90 * MathUtils._100_PERCENT / 100);

        // Liquidate the position
        positionManager.liquidate(collateralToken, ALICE);

        assertEq(positionManager.raftDebtToken().balanceOf(ALICE), 0);
        assertGt(positionManager.raftDebtToken().balanceOf(BOB), 0);
    }

    // Reverts if position is non-existent or has been closed
    function testLiquidateNonExistentPosition() public {
        vm.startPrank(ALICE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            position: ALICE,
            icr: 4e18
        });
        vm.stopPrank();

        vm.startPrank(BOB);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            position: BOB,
            icr: 2.1e18
        });
        vm.stopPrank();

        assertEq(positionManager.raftDebtToken().balanceOf(CAROL), 0);

        vm.expectRevert(IPositionManager.NothingToLiquidate.selector);
        positionManager.liquidate(collateralToken, CAROL);

        vm.startPrank(CAROL);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            position: CAROL,
            icr: 2e18
        });
        vm.stopPrank();

        assertGt(positionManager.raftDebtToken().balanceOf(CAROL), 0);

        // Price drops, Carol ICR falls below MCR
        priceFeed.setPrice(100e18);

        // Carol liquidated, and her position is closed
        positionManager.liquidate(collateralToken, CAROL);

        assertEq(positionManager.raftDebtToken().balanceOf(CAROL), 0);

        vm.expectRevert(IPositionManager.NothingToLiquidate.selector);
        positionManager.liquidate(collateralToken, CAROL);
    }

    // Liquidates based on entire collateral/debt (including pending rewards), not raw collateral/debt
    function testEntireCollateralDebtRedistribution() public {
        vm.prank(address(positionManager));
        rToken.mint(address(this), 1_000_000e18);

        vm.startPrank(ALICE);
        PositionManagerUtils.OpenPositionResult memory alicePosition = PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            position: ALICE,
            extraDebtAmount: 100e18,
            icr: 8e18
        });
        vm.stopPrank();

        vm.startPrank(BOB);
        PositionManagerUtils.OpenPositionResult memory bobPosition = PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            position: BOB,
            extraDebtAmount: 100e18,
            icr: 2.21e18
        });
        vm.stopPrank();

        vm.startPrank(CAROL);
        PositionManagerUtils.OpenPositionResult memory carolPosition = PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            position: CAROL,
            extraDebtAmount: 100e18,
            icr: 2e18
        });
        vm.stopPrank();

        // Dave opens with 60 R, 0.6 ETH
        vm.startPrank(DAVE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            position: DAVE,
            icr: 2e18
        });
        vm.stopPrank();

        // Price drops
        priceFeed.setPrice(100e18);
        uint256 price = priceFeed.getPrice();

        uint256 aliceICRBefore = PositionManagerUtils.getCurrentICR(positionManager, collateralToken, ALICE, price);
        uint256 bobICRBefore = PositionManagerUtils.getCurrentICR(positionManager, collateralToken, BOB, price);
        uint256 carolICRBefore = PositionManagerUtils.getCurrentICR(positionManager, collateralToken, CAROL, price);

        /* Before redistribution:
        Alice ICR: 2 * 100 / 50 = 400%
        Bob ICR: 1 * 100 / 90.5 = 110.5%
        Carol ICR: 1 * 100 / 100 = 100%

        Therefore Alice and Bob above the MCR, Carol is below */
        assertGe(aliceICRBefore, MathUtils.MCR);
        assertGe(bobICRBefore, MathUtils.MCR);
        assertLe(carolICRBefore, MathUtils.MCR);

        positionManager.liquidate(collateralToken, DAVE);

        uint256 aliceICRAfter = PositionManagerUtils.getCurrentICR(positionManager, collateralToken, ALICE, price);
        uint256 bobICRAfter = PositionManagerUtils.getCurrentICR(positionManager, collateralToken, BOB, price);
        uint256 carolICRAfter = PositionManagerUtils.getCurrentICR(positionManager, collateralToken, CAROL, price);

        assertGe(aliceICRAfter, MathUtils.MCR);
        assertLe(bobICRAfter, MathUtils.MCR);
        assertLe(carolICRAfter, MathUtils.MCR);

        // Though Bob's true ICR (including pending rewards) is below the MCR, check that Bob's raw collateral and debt
        // has not changed, and that his "raw" ICR is above the MCR
        uint256 bobDebt = positionManager.raftDebtToken().balanceOf(BOB);
        uint256 bobPositionCollateral = collateralToken.balanceOf(BOB);

        uint256 bobRawICR = bobPositionCollateral * price / bobDebt;
        assertGe(bobRawICR, MathUtils.MCR);

        vm.startPrank(EVE);
        PositionManagerUtils.openPosition({
            positionManager: positionManager,
            priceFeed: priceFeed,
            collateralToken: collateralToken,
            position: EVE,
            icr: 20e18
        });
        vm.stopPrank();

        // Liquidate Alice unsuccessfully and Bob and Carol successfully
        vm.expectRevert(IPositionManager.NothingToLiquidate.selector);
        positionManager.liquidate(collateralToken, ALICE);
        positionManager.liquidate(collateralToken, BOB);
        positionManager.liquidate(collateralToken, CAROL);

        // Confirm token balances have not changed
        assertEq(rToken.balanceOf(ALICE), alicePosition.debtAmount);
        assertEq(rToken.balanceOf(BOB), bobPosition.debtAmount);
        assertEq(rToken.balanceOf(CAROL), carolPosition.debtAmount);
    }
}
