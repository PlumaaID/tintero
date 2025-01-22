// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {BaseTest} from "./Base.t.sol";
import {TinteroLoan} from "~/TinteroLoan.sol";
import {PaymentLib} from "~/utils/PaymentLib.sol";

contract TinteroLoanTest is BaseTest {
    using PaymentLib for PaymentLib.Payment;

    function testLoanCreation(
        address borrower,
        address beneficiary,
        uint16 nPayments,
        uint16 defaultThreshold
    ) public {
        _sanitizeActors(borrower, beneficiary);
        vm.assume(nPayments <= 1000);

        (
            address loan,
            ,
            PaymentLib.Payment[] memory payments,
            uint256[] memory collateralTokenIds
        ) = _requestLoan(
                borrower,
                beneficiary,
                bytes32(0),
                nPayments,
                defaultThreshold
            );

        TinteroLoan tinteroLoan = TinteroLoan(loan);

        assertEq(address(tinteroLoan.lendingAsset()), tintero.asset());
        assertEq(address(tinteroLoan.collateralAsset()), address(endorser));
        assertEq(address(tinteroLoan.liquidityProvider()), address(tintero));

        // Check payments and calculate total principal to be funded
        uint256 totalPrincipal = 0;
        for (uint256 i = 0; i < payments.length; i++) {
            (
                uint256 collateralTokenId,
                PaymentLib.Payment memory payment
            ) = tinteroLoan.payment(i);
            totalPrincipal += payment.principal;
            assertEq(collateralTokenId, collateralTokenIds[i]);
            assertEq(payment.creation, payments[i].creation);
            assertEq(payment.creation, uint48(block.timestamp));
            assertEq(payment.maturityPeriod, payments[i].maturityPeriod);
            assertEq(payment.gracePeriod, payments[i].gracePeriod);
            assertEq(payment.interestRate, payments[i].interestRate);
            assertEq(payment.premiumRate, payments[i].premiumRate);
        }

        // Check state consistency
        assertEq(tinteroLoan.totalPayments(), nPayments);
        assertEq(tinteroLoan.currentPaymentIndex(), 0);
        if (nPayments > 0) {
            (
                uint256 currentCollateralId,
                PaymentLib.Payment memory currentPayment
            ) = tinteroLoan.currentPayment();
            assertEq(currentCollateralId, collateralTokenIds[0]);
            assertEq(currentPayment.creation, payments[0].creation);
            assertEq(currentPayment.maturityPeriod, payments[0].maturityPeriod);
            assertEq(currentPayment.gracePeriod, payments[0].gracePeriod);
            assertEq(currentPayment.interestRate, payments[0].interestRate);
            assertEq(currentPayment.premiumRate, payments[0].premiumRate);

            // Collateral tokens are transferred to the loan
            for (uint256 i = 0; i < collateralTokenIds.length; i++)
                assertEq(endorser.ownerOf(collateralTokenIds[i]), loan);
        }
    }

    function testRevertInitializeImplementation(
        address borrower,
        address beneficiary,
        uint16 nPayments,
        uint16 defaultThreshold
    ) public {
        _sanitizeActors(borrower, beneficiary);
        vm.assume(nPayments <= 1000);

        (address loan, , , ) = _requestLoan(
            borrower,
            beneficiary,
            bytes32(0),
            nPayments,
            defaultThreshold
        );

        vm.expectRevert();
        TinteroLoan(loan).initialize(
            address(tintero),
            address(endorser),
            beneficiary,
            defaultThreshold
        );
    }

    function testRevertInitializeZeroBeneficiary(
        address borrower,
        uint16 nPayments,
        uint16 defaultThreshold
    ) public {
        vm.assume(nPayments <= 1000);

        PaymentLib.Payment[] memory payments = _mockPayments(0, nPayments);
        uint256[] memory collateralTokenIds = _mockCollateralIds(
            0,
            nPayments,
            borrower
        );

        vm.expectRevert();
        tintero.requestLoan(
            address(endorser),
            address(0), // Zero beneficiary
            defaultThreshold,
            payments,
            collateralTokenIds,
            bytes32(0)
        );
    }

    function testPushPayments(
        address borrower,
        address beneficiary,
        address manager,
        uint16 nPayments,
        uint16 nExtraPayments
    ) public {
        _sanitizeActors(borrower, beneficiary);
        vm.assume(nPayments <= 1000);
        vm.assume(nExtraPayments <= 1000);

        (
            address loan,
            ,
            PaymentLib.Payment[] memory payments,
            uint256[] memory collateralTokenIds
        ) = _requestLoan(
                borrower,
                beneficiary,
                bytes32(0),
                nPayments,
                nPayments
            );

        PaymentLib.Payment[] memory lastPayments = _mockPayments(
            nPayments,
            nExtraPayments
        );
        uint256[] memory lastCollateralIds = _mockCollateralIds(
            nPayments,
            nExtraPayments,
            borrower
        );

        // Grant manager role
        accessManager.grantRole(TINTERO_MANAGER_ROLE, manager, 0);

        // Manager pushes extra payments
        vm.prank(manager);
        tintero.pushPayments(
            TinteroLoan(loan),
            lastCollateralIds,
            lastPayments
        );

        // Collateral tokens are transferred to the loan
        for (uint256 i = 0; i < collateralTokenIds.length; i++)
            assertEq(endorser.ownerOf(collateralTokenIds[i]), loan);
        for (uint256 i = 0; i < lastCollateralIds.length; i++)
            assertEq(endorser.ownerOf(lastCollateralIds[i]), loan);

        // Check payments
        for (uint256 i = 0; i < payments.length; i++) {
            (
                uint256 collateralTokenId,
                PaymentLib.Payment memory payment
            ) = TinteroLoan(loan).payment(i);
            assertEq(collateralTokenId, collateralTokenIds[i]);
            assertEq(payment.creation, payments[i].creation);
            assertEq(payment.creation, uint48(block.timestamp));
            assertEq(payment.maturityPeriod, payments[i].maturityPeriod);
            assertEq(payment.gracePeriod, payments[i].gracePeriod);
            assertEq(payment.interestRate, payments[i].interestRate);
            assertEq(payment.premiumRate, payments[i].premiumRate);
        }

        // Check state consistency
        assertEq(TinteroLoan(loan).totalPayments(), nPayments + nExtraPayments);
        assertEq(TinteroLoan(loan).currentPaymentIndex(), 0);
        if (nPayments + nExtraPayments > 0) {
            (
                uint256 currentCollateralId,
                PaymentLib.Payment memory currentPayment
            ) = TinteroLoan(loan).currentPayment();
            if (nPayments > 0) {
                // Payments were added first
                assertEq(currentCollateralId, collateralTokenIds[0]);
                assertEq(currentPayment.creation, payments[0].creation);
                assertEq(
                    currentPayment.maturityPeriod,
                    payments[0].maturityPeriod
                );
                assertEq(currentPayment.gracePeriod, payments[0].gracePeriod);
                assertEq(currentPayment.interestRate, payments[0].interestRate);
                assertEq(currentPayment.premiumRate, payments[0].premiumRate);
            } else {
                // First payments list is empty
                assertEq(currentCollateralId, lastCollateralIds[0]);
                assertEq(currentPayment.creation, lastPayments[0].creation);
                assertEq(
                    currentPayment.maturityPeriod,
                    lastPayments[0].maturityPeriod
                );
                assertEq(
                    currentPayment.gracePeriod,
                    lastPayments[0].gracePeriod
                );
                assertEq(
                    currentPayment.interestRate,
                    lastPayments[0].interestRate
                );
                assertEq(
                    currentPayment.premiumRate,
                    lastPayments[0].premiumRate
                );
            }
        }
    }

    function testPushTranches(
        address borrower,
        address beneficiary,
        address manager,
        uint16 nPayments,
        uint16 nTranches,
        address trancheRecipient
    ) public {
        _sanitizeActors(borrower, beneficiary);
        nTranches = _sanitizeTranches(nPayments, nTranches);

        (address loan, , , ) = _requestLoan(
            borrower,
            beneficiary,
            bytes32(0),
            nPayments,
            nPayments
        );

        (
            uint96[] memory paymentIndexes,
            address[] memory recipients
        ) = _pushTranches(
                manager,
                loan,
                nTranches,
                trancheRecipient,
                nPayments
            );

        // Check tranches
        for (uint256 i = 0; i < paymentIndexes.length; i++) {
            (uint96 paymentIndex, address recipient) = TinteroLoan(loan)
                .tranche(i);
            assertEq(paymentIndex, paymentIndexes[i]);
            assertEq(recipient, recipients[i]);
        }

        // Check state consistency
        assertEq(TinteroLoan(loan).totalTranches(), nTranches);
        assertEq(TinteroLoan(loan).currentTrancheIndex(), 0);
        if (nTranches > 0) {
            (
                uint96 currentPaymentIndex,
                address currentRecipient
            ) = TinteroLoan(loan).currentTranche();
            assertEq(currentPaymentIndex, paymentIndexes[0]);
            assertEq(currentRecipient, recipients[0]);
        }
    }

    function testFundN(
        address borrower,
        address beneficiary,
        address manager,
        uint16 nPayments,
        uint16 nTranches
    ) public {
        _sanitizeActors(borrower, beneficiary);
        nTranches = _sanitizeTranches(nPayments, nTranches);

        (address loan, uint256 totalPrincipal, , ) = _requestLoan(
            borrower,
            beneficiary,
            bytes32(0),
            nPayments,
            nPayments
        );

        _pushTranches(manager, loan, nTranches, address(this), nPayments);
        _addLiquidity(totalPrincipal);

        IERC20 asset_ = IERC20(TinteroLoan(loan).lendingAsset());

        uint256 tinteroAssetBalanceBefore = asset_.balanceOf(address(tintero));
        uint256 beneficiaryAssetBalanceBefore = asset_.balanceOf(beneficiary);

        // Fund all payments
        _fund(loan, manager, nPayments);

        // Actual assets are transferred to the beneficiary
        assertEq(
            asset_.balanceOf(beneficiary),
            beneficiaryAssetBalanceBefore + totalPrincipal
        );
        assertEq(
            asset_.balanceOf(address(tintero)),
            tinteroAssetBalanceBefore - totalPrincipal
        );
    }

    function testPayN(
        address borrower,
        address beneficiary,
        address manager,
        uint16 nPayments,
        uint16 nTranches,
        address collateralReceiver
    ) public {
        vm.assume(collateralReceiver != address(0));
        _sanitizeActors(borrower, beneficiary);

        nPayments = uint16(bound(nPayments, 1, 1000));
        nTranches = uint16(bound(nTranches, 1, 1000));
        vm.assume(nTranches <= nPayments);

        vm.assume(collateralReceiver.code.length == 0); // EOAs (and also simulates ERC721Holders)
        (
            address loan,
            uint256 totalPrincipal,
            PaymentLib.Payment[] memory payments,
            uint256[] memory collateralTokenIds
        ) = _requestLoan(
                borrower,
                beneficiary,
                bytes32(0),
                nPayments,
                nPayments
            );

        _pushTranches(manager, loan, nTranches, address(tintero), nPayments);
        _addLiquidity(totalPrincipal);
        _fund(loan, manager, nPayments);

        IERC20 asset_ = IERC20(TinteroLoan(loan).lendingAsset());

        uint256 tinteroAssetBalanceBefore = asset_.balanceOf(address(tintero));
        uint256 beneficiaryAssetBalanceBefore = asset_.balanceOf(beneficiary);

        uint256 interestAccrued = 0;
        skip(payments[payments.length - 1].maturityPeriod); // Skip to last payment maturity
        for (uint256 i = 0; i < nPayments; i++) {
            PaymentLib.Payment memory payment = payments[i];
            interestAccrued += payment.accruedInterest(uint48(block.timestamp));
        }

        if (interestAccrued > 0) {
            // Make sure user has enough to pay interests
            _mintUSDCTo(beneficiary, interestAccrued);
            beneficiaryAssetBalanceBefore += interestAccrued;
        }

        // Pay all payments
        vm.prank(beneficiary);
        usdc.approve(address(loan), totalPrincipal + interestAccrued);
        vm.prank(beneficiary);
        TinteroLoan(loan).repayN(nPayments, collateralReceiver);

        // Actual assets are transferred to the liquidity provider
        assertEq(
            tinteroAssetBalanceBefore + totalPrincipal + interestAccrued,
            asset_.balanceOf(address(tintero))
        );
        assertEq(
            asset_.balanceOf(address(beneficiary)),
            beneficiaryAssetBalanceBefore - totalPrincipal - interestAccrued
        );

        // Check collateral tokens are transferred to the collateral receiver
        for (uint256 i = 0; i < collateralTokenIds.length; i++) {
            if (collateralReceiver == address(0)) vm.expectRevert();
            assertEq(
                endorser.ownerOf(collateralTokenIds[i]),
                collateralReceiver
            );
        }
    }

    function testRepossess(
        address borrower,
        address beneficiary,
        address manager,
        uint16 nPayments,
        uint16 nTranches,
        uint16 defaultThreshold,
        address repossessReceiver
    ) public {
        _sanitizeActors(borrower, beneficiary);
        nTranches = _sanitizeTranches(nPayments, nTranches);
        defaultThreshold = _sanitizeDefaultThreshold(
            nPayments,
            defaultThreshold
        );

        // Can't be 0 or transfer will fail
        vm.assume(borrower != address(0));
        vm.assume(beneficiary != address(0));
        vm.assume(repossessReceiver != address(0));

        vm.assume(repossessReceiver != address(this));
        vm.assume(repossessReceiver.code.length == 0); // EOAs (and also simulates ERC721Holders)
        (
            address loan,
            uint256 totalPrincipal,
            PaymentLib.Payment[] memory payments,
            uint256[] memory collateralTokenIds
        ) = _requestLoan(
                borrower,
                beneficiary,
                bytes32(0),
                nPayments,
                defaultThreshold
            );

        _pushTranches(manager, loan, nTranches, address(this), nPayments);
        _addLiquidity(totalPrincipal);
        _fund(loan, manager, nPayments);
        _repossess(
            loan,
            manager,
            payments,
            defaultThreshold,
            repossessReceiver
        );

        // Check collateral tokens are transferred to the repossess receiver
        for (uint256 i = 0; i < collateralTokenIds.length; i++) {
            assertEq(
                endorser.ownerOf(collateralTokenIds[i]),
                repossessReceiver
            );
        }
    }
}
