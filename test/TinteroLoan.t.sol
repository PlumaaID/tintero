// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {BaseTest} from "./Base.t.sol";
import {TinteroLoan} from "~/TinteroLoan.sol";
import {PaymentLib} from "~/utils/PaymentLib.sol";
import {LoanState} from "~/interfaces/ITinteroLoan.types.sol";

contract TinteroLoanTest is BaseTest {
    using PaymentLib for PaymentLib.Payment;

    function testLoanCreation(
        address borrower,
        address beneficiary,
        uint24 nPayments,
        uint24 defaultThreshold
    ) public {
        _sanitizeActors(borrower, beneficiary);
        nPayments = uint24(bound(nPayments, 0, ARBITRARY_MAX_PAYMENTS));
        vm.assume(defaultThreshold != 0);

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
        assertEq(tinteroLoan.beneficiary(), beneficiary);
        assertEq(tinteroLoan.defaultThreshold(), defaultThreshold);

        // Check payments and calculate total principal to be funded
        uint256 totalPrincipal = 0;
        for (uint256 i = 0; i < payments.length; i++) {
            uint256 collateralTokenId = tinteroLoan.collateralId(i);
            PaymentLib.Payment memory payment = tinteroLoan.payment(i);
            totalPrincipal += payment.principal;
            assertEq(collateralTokenId, collateralTokenIds[i]);
            assertEq(payment.fundedAt, payments[i].fundedAt);
            assertEq(payment.fundedAt, uint48(0));
            assertEq(payment.maturityPeriod, payments[i].maturityPeriod);
            assertEq(payment.gracePeriod, payments[i].gracePeriod);
            assertEq(payment.interestRate, payments[i].interestRate);
            assertEq(payment.premiumRate, payments[i].premiumRate);
        }

        // Check state consistency
        assertEq(tinteroLoan.totalPayments(), nPayments);
        assertEq(tinteroLoan.currentPaymentIndex(), 0);
        if (nPayments > 0) {
            uint256 index = tinteroLoan.currentPaymentIndex();
            uint256 currentCollateralId = tinteroLoan.collateralId(index);
            PaymentLib.Payment memory currentPayment = tinteroLoan.payment(
                index
            );
            assertEq(currentCollateralId, collateralTokenIds[0]);
            assertEq(currentPayment.fundedAt, payments[0].fundedAt);
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
        uint24 nPayments,
        uint24 defaultThreshold
    ) public {
        _sanitizeActors(borrower, beneficiary);
        nPayments = uint24(bound(nPayments, 0, ARBITRARY_MAX_PAYMENTS));
        vm.assume(defaultThreshold != 0);

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
        uint24 nPayments,
        uint24 defaultThreshold
    ) public {
        vm.assume(borrower != address(0));
        nPayments = uint24(bound(nPayments, 0, ARBITRARY_MAX_PAYMENTS));

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

    function testRevertFundedAtNotZero(
        address borrower,
        address beneficiary,
        uint24 nPayments,
        uint24 defaultThreshold,
        uint48 fundedAt
    ) public {
        _sanitizeActors(borrower, beneficiary);
        nPayments = uint24(bound(nPayments, 0, ARBITRARY_MAX_PAYMENTS));
        vm.assume(defaultThreshold != 0);
        vm.assume(fundedAt != 0);

        PaymentLib.Payment[] memory payments = _mockPayments(0, nPayments);
        uint256[] memory collateralTokenIds = _mockCollateralIds(
            0,
            nPayments,
            borrower
        );

        // Set fundedAt to not zero
        for (uint256 i = 0; i < payments.length; i++) {
            payments[i].fundedAt = fundedAt;
        }

        if (payments.length != 0) vm.expectRevert();
        tintero.requestLoan(
            address(endorser),
            beneficiary,
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
        uint24 nPayments,
        uint24 nExtraPayments
    ) public {
        _sanitizeAccessManagerCaller(manager);
        _sanitizeActors(borrower, beneficiary);
        nPayments = uint24(bound(nPayments, 0, ARBITRARY_MAX_PAYMENTS));
        nExtraPayments = uint24(
            bound(nExtraPayments, 0, ARBITRARY_MAX_PAYMENTS)
        );

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
        accessManager.grantRole(TINTERO_MANAGER_USDC_V01_ROLE, manager, 0);

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
            uint256 collateralTokenId = TinteroLoan(loan).collateralId(i);
            PaymentLib.Payment memory payment = TinteroLoan(loan).payment(i);
            assertEq(collateralTokenId, collateralTokenIds[i]);
            assertEq(payment.fundedAt, payments[i].fundedAt);
            assertEq(payment.fundedAt, uint48(0));
            assertEq(payment.maturityPeriod, payments[i].maturityPeriod);
            assertEq(payment.gracePeriod, payments[i].gracePeriod);
            assertEq(payment.interestRate, payments[i].interestRate);
            assertEq(payment.premiumRate, payments[i].premiumRate);
        }

        // Check state consistency
        assertEq(TinteroLoan(loan).totalPayments(), nPayments + nExtraPayments);
        assertEq(TinteroLoan(loan).currentPaymentIndex(), 0);
        if (nPayments + nExtraPayments > 0) {
            uint256 index = TinteroLoan(loan).currentPaymentIndex();
            uint256 currentCollateralId = TinteroLoan(loan).collateralId(index);
            PaymentLib.Payment memory currentPayment = TinteroLoan(loan)
                .payment(index);
            if (nPayments > 0) {
                // Payments were added first
                assertEq(currentCollateralId, collateralTokenIds[0]);
                assertEq(currentPayment.fundedAt, payments[0].fundedAt);
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
                assertEq(currentPayment.fundedAt, lastPayments[0].fundedAt);
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

    function testPushPaymentsRevertMismatchedPaymentCollateralIds(
        address borrower,
        address beneficiary,
        address manager,
        uint24 nPayments,
        uint24 nExtraPayments
    ) public {
        _sanitizeAccessManagerCaller(manager);
        _sanitizeActors(borrower, beneficiary);
        nPayments = uint24(bound(nPayments, 0, ARBITRARY_MAX_PAYMENTS));
        nExtraPayments = uint24(
            bound(nExtraPayments, 0, ARBITRARY_MAX_PAYMENTS)
        );
        nExtraPayments = uint24(
            bound(nExtraPayments, 1, ARBITRARY_MAX_PAYMENTS)
        );

        (address loan, , , ) = _requestLoan(
            borrower,
            beneficiary,
            bytes32(0),
            nPayments,
            nPayments
        );

        PaymentLib.Payment[] memory lastPayments = _mockPayments(
            nPayments,
            nExtraPayments - 1
        );
        uint256[] memory lastCollateralIds = _mockCollateralIds(
            nPayments,
            nExtraPayments,
            borrower
        );

        // Mismatched payment and collateral ids
        accessManager.grantRole(TINTERO_MANAGER_USDC_V01_ROLE, manager, 0);
        vm.prank(manager);
        vm.expectRevert();
        tintero.pushPayments(
            TinteroLoan(loan),
            lastCollateralIds,
            lastPayments
        );
    }

    function testPushPaymentsRevertUnorderedPayments(
        address borrower,
        address beneficiary,
        address manager,
        uint24 nPayments
    ) public {
        _sanitizeAccessManagerCaller(manager);
        _sanitizeActors(borrower, beneficiary);
        nPayments = uint24(bound(nPayments, 1, ARBITRARY_MAX_PAYMENTS));

        (address loan, , PaymentLib.Payment[] memory payments, ) = _requestLoan(
            borrower,
            beneficiary,
            bytes32(0),
            nPayments,
            nPayments
        );

        PaymentLib.Payment[] memory lastPayments = _mockPayments(nPayments, 1);
        uint256[] memory lastCollateralIds = _mockCollateralIds(
            nPayments,
            1,
            borrower
        );

        lastPayments[0].maturityPeriod = payments[0].maturityPeriod - 1;

        accessManager.grantRole(TINTERO_MANAGER_USDC_V01_ROLE, manager, 0);
        vm.prank(manager);
        vm.expectRevert();
        tintero.pushPayments(
            TinteroLoan(loan),
            lastCollateralIds,
            lastPayments
        );
    }

    function testPushPaymentRevertDuplicatedCollateralTokenId(
        address borrower,
        address beneficiary,
        address manager,
        uint24 nPayments
    ) public {
        _sanitizeAccessManagerCaller(manager);
        _sanitizeActors(borrower, beneficiary);
        nPayments = uint24(bound(nPayments, 0, ARBITRARY_MAX_PAYMENTS));

        (address loan, , , ) = _requestLoan(
            borrower,
            beneficiary,
            bytes32(0),
            nPayments,
            nPayments
        );

        PaymentLib.Payment[] memory lastPayments = _mockPayments(nPayments, 2);
        uint256[] memory lastCollateralIds = _mockCollateralIds(
            nPayments,
            2,
            borrower
        );

        // Duplicated collateral token id
        lastCollateralIds[0] = lastCollateralIds[1];

        accessManager.grantRole(TINTERO_MANAGER_USDC_V01_ROLE, manager, 0);
        vm.prank(manager);
        vm.expectRevert();
        tintero.pushPayments(
            TinteroLoan(loan),
            lastCollateralIds,
            lastPayments
        );
    }

    function testPushPaymentsRevertNotLiquidityProvider(
        address borrower,
        address beneficiary,
        uint24 nPayments,
        uint24 nExtraPayments,
        address notLiquidityProvider
    ) public {
        _sanitizeActors(borrower, beneficiary);
        nPayments = uint24(bound(nPayments, 0, ARBITRARY_MAX_PAYMENTS));
        nExtraPayments = uint24(
            bound(nExtraPayments, 0, ARBITRARY_MAX_PAYMENTS)
        );
        vm.assume(notLiquidityProvider != address(tintero));

        (address loan, , , ) = _requestLoan(
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

        vm.prank(notLiquidityProvider);
        vm.expectRevert();
        TinteroLoan(loan).pushPayments(lastCollateralIds, lastPayments);
    }

    function testPushTranches(
        address borrower,
        address beneficiary,
        address manager,
        uint24 nPayments,
        uint24 nTranches,
        address trancheRecipient
    ) public {
        _sanitizeAccessManagerCaller(manager);
        _sanitizeActors(borrower, beneficiary);
        (nPayments, nTranches) = _sanitizeTranches(nPayments, nTranches);

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
        uint256 trancheIndex = TinteroLoan(loan).currentTrancheIndex();
        assertEq(trancheIndex, 0);
        assertEq(TinteroLoan(loan).totalTranches(), nTranches);
        if (nTranches > 0) {
            (
                uint96 currentPaymentIndex,
                address currentRecipient
            ) = TinteroLoan(loan).tranche(trancheIndex);
            assertEq(currentPaymentIndex, paymentIndexes[0]);
            assertEq(currentRecipient, recipients[0]);
        }
    }

    function testPushTranchesRevertMismatchedTranchePaymentIndexRecipient(
        address borrower,
        address beneficiary,
        address manager,
        uint24 nPayments,
        uint24 nTranches
    ) public {
        _sanitizeAccessManagerCaller(manager);
        _sanitizeActors(borrower, beneficiary);
        (nPayments, nTranches) = _sanitizeTranches(nPayments, nTranches);

        (address loan, , , ) = _requestLoan(
            borrower,
            beneficiary,
            bytes32(0),
            nPayments,
            nPayments
        );

        uint96[] memory paymentIndexes = new uint96[](nTranches - 1);
        for (uint256 i = 0; i < nTranches - 1; i++) {
            paymentIndexes[i] = uint96(i);
        }

        address[] memory recipients = new address[](nTranches);
        for (uint256 i = 0; i < nTranches; i++) {
            recipients[i] = address(this);
        }

        accessManager.grantRole(TINTERO_MANAGER_USDC_V01_ROLE, manager, 0);
        vm.prank(manager);
        vm.expectRevert();
        tintero.pushTranches(TinteroLoan(loan), paymentIndexes, recipients);
    }

    function testPushTranchesRevertNoLiquidityProvider(
        address borrower,
        address beneficiary,
        uint24 nPayments,
        uint24 nTranches,
        address notLiquidityProvider
    ) public {
        _sanitizeActors(borrower, beneficiary);
        (nPayments, nTranches) = _sanitizeTranches(nPayments, nTranches);

        (address loan, , , ) = _requestLoan(
            borrower,
            beneficiary,
            bytes32(0),
            nPayments,
            nPayments
        );

        vm.prank(notLiquidityProvider);
        vm.expectRevert();
        TinteroLoan(loan).pushTranches(
            new uint96[](nTranches),
            new address[](nTranches)
        );
    }

    function testPushTranchesRevertUnincreasingTranchePaymentIndex(
        address borrower,
        address beneficiary,
        address manager,
        uint24 nPayments,
        uint24 nTranches,
        address trancheRecipient
    ) public {
        _sanitizeAccessManagerCaller(manager);
        _sanitizeActors(borrower, beneficiary);
        (nPayments, nTranches) = _sanitizeTranches(nPayments, nTranches);
        vm.assume(nTranches > 1);

        (address loan, , , ) = _requestLoan(
            borrower,
            beneficiary,
            bytes32(0),
            nPayments,
            nPayments
        );

        uint96[] memory paymentIndexes = new uint96[](nTranches);
        address[] memory recipients = new address[](nTranches);
        uint256 last = nTranches - 1;
        for (uint256 i = 0; i < last; i++) {
            paymentIndexes[i] = uint96(i + 1);
            recipients[i] = trancheRecipient;
        }

        paymentIndexes[last] = paymentIndexes[last - 1]; // Unincreasing

        // Grant manager role
        accessManager.grantRole(TINTERO_MANAGER_USDC_V01_ROLE, manager, 0);

        // Manager pushes tranches
        vm.prank(manager);
        vm.expectRevert();
        tintero.pushTranches(TinteroLoan(loan), paymentIndexes, recipients);
    }

    function testPushTranchesTooManyTranches(
        address borrower,
        address beneficiary,
        address manager,
        uint24 nPayments,
        uint24 nTranches,
        address trancheRecipient
    ) public {
        _sanitizeAccessManagerCaller(manager);
        _sanitizeActors(borrower, beneficiary);
        (nPayments, nTranches) = _sanitizeTranches(nPayments, nTranches);

        (address loan, , , ) = _requestLoan(
            borrower,
            beneficiary,
            bytes32(0),
            nPayments,
            nPayments
        );

        nTranches = nPayments + 1;

        uint96[] memory paymentIndexes = new uint96[](nTranches);
        address[] memory recipients = new address[](nTranches);
        for (uint256 i = 0; i < nTranches; i++) {
            paymentIndexes[i] = uint96(i + 1);
            recipients[i] = trancheRecipient;
        }

        // Grant manager role
        accessManager.grantRole(TINTERO_MANAGER_USDC_V01_ROLE, manager, 0);

        // Manager pushes tranches
        vm.prank(manager);
        vm.expectRevert();
        tintero.pushTranches(TinteroLoan(loan), paymentIndexes, recipients);
    }

    function testFundN(
        address borrower,
        address beneficiary,
        address manager,
        uint24 nPayments,
        uint24 nTranches
    ) public {
        _sanitizeAccessManagerCaller(manager);
        _sanitizeActors(borrower, beneficiary);
        (nPayments, nTranches) = _sanitizeTranches(nPayments, nTranches);

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

        uint256 collateralTokenId = TinteroLoan(loan).collateralId(
            TinteroLoan(loan).currentFundingIndex()
        );
        PaymentLib.Payment memory firstPayment = TinteroLoan(loan).payment(
            TinteroLoan(loan).currentFundingIndex()
        );
        assertEq(firstPayment.principal, payments[0].principal); // First payment
        assertEq(collateralTokenId, collateralTokenIds[0]);

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
        assertEq(TinteroLoan(loan).currentFundingIndex(), nPayments);
    }

    function testPartialFundN(
        address borrower,
        address beneficiary,
        address manager,
        uint24 nPayments,
        uint24 nTranches
    ) public {
        _sanitizeAccessManagerCaller(manager);
        _sanitizeActors(borrower, beneficiary);
        (nPayments, nTranches) = _sanitizeTranches(nPayments, nTranches);
        vm.assume(nPayments > 1); // At least two payments

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

        totalPrincipal = totalPrincipal - payments[nPayments - 1].principal;

        uint256 collateralTokenId = TinteroLoan(loan).collateralId(
            TinteroLoan(loan).currentFundingIndex()
        );
        PaymentLib.Payment memory firstPayment = TinteroLoan(loan).payment(
            TinteroLoan(loan).currentFundingIndex()
        );
        assertEq(firstPayment.principal, payments[0].principal); // First payment
        assertEq(collateralTokenId, collateralTokenIds[0]);

        _pushTranches(manager, loan, nTranches, address(this), nPayments);
        _addLiquidity(totalPrincipal);

        IERC20 asset_ = IERC20(TinteroLoan(loan).lendingAsset());

        uint256 tinteroAssetBalanceBefore = asset_.balanceOf(address(tintero));
        uint256 beneficiaryAssetBalanceBefore = asset_.balanceOf(beneficiary);

        // Fund partial amount
        _fund(loan, manager, nPayments - 1);

        // Actual assets are transferred to the beneficiary
        assertEq(
            asset_.balanceOf(beneficiary),
            beneficiaryAssetBalanceBefore + totalPrincipal
        );
        assertEq(
            asset_.balanceOf(address(tintero)),
            tinteroAssetBalanceBefore - totalPrincipal
        );
        assertEq(uint8(TinteroLoan(loan).state()), uint8(LoanState.FUNDING));
    }

    function testFundNRevertUntranchedPayments(
        address borrower,
        address beneficiary,
        address manager,
        uint24 nPayments,
        uint24 nExtraPayments,
        uint24 nTranches
    ) public {
        _sanitizeAccessManagerCaller(manager);
        _sanitizeActors(borrower, beneficiary);
        nExtraPayments = uint24(
            bound(nExtraPayments, 1, ARBITRARY_MAX_PAYMENTS)
        );
        (nPayments, nTranches) = _sanitizeTranches(nPayments, nTranches);

        (address loan, uint256 totalPrincipal, , ) = _requestLoan(
            borrower,
            beneficiary,
            bytes32(0),
            nPayments,
            nPayments
        );

        _pushTranches(manager, loan, nTranches, address(this), nPayments);
        _addLiquidity(totalPrincipal);

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
        accessManager.grantRole(TINTERO_MANAGER_USDC_V01_ROLE, manager, 0);

        // Manager pushes extra payments
        vm.prank(manager);
        tintero.pushPayments(
            TinteroLoan(loan),
            lastCollateralIds,
            lastPayments
        );

        // // Fund all payments
        vm.expectRevert();
        _fund(loan, manager, nPayments);
    }

    function testWithdrawPaymentCollateral(
        address borrower,
        address beneficiary,
        uint24 nPayments
    ) public {
        _sanitizeActors(borrower, beneficiary);
        nPayments = uint24(bound(nPayments, 0, ARBITRARY_MAX_PAYMENTS));

        (address loan, , , uint256[] memory collateralTokenIds) = _requestLoan(
            borrower,
            beneficiary,
            bytes32(0),
            nPayments,
            nPayments
        );

        _sanitizeERC721Receiver(beneficiary, loan);

        vm.prank(beneficiary);
        TinteroLoan(loan).withdrawPaymentCollateral(0, nPayments);

        // Check collateral tokens are transferred to the beneficiary
        for (uint256 i = 0; i < collateralTokenIds.length; i++) {
            assertEq(endorser.ownerOf(collateralTokenIds[i]), beneficiary);
        }
    }

    function testWithdrawPaymentCollateralRevertNotBeneficiary(
        address borrower,
        address beneficiary,
        uint24 nPayments,
        address notBeneficiary
    ) public {
        _sanitizeActors(borrower, beneficiary);
        nPayments = uint24(bound(nPayments, 0, ARBITRARY_MAX_PAYMENTS));
        vm.assume(notBeneficiary != beneficiary);

        (address loan, , , ) = _requestLoan(
            borrower,
            beneficiary,
            bytes32(0),
            nPayments,
            nPayments
        );

        vm.prank(notBeneficiary);
        vm.expectRevert();
        TinteroLoan(loan).withdrawPaymentCollateral(0, nPayments);
    }

    function testRepayCurrent(
        address borrower,
        address beneficiary,
        address manager,
        uint24 nPayments,
        address collateralReceiver
    ) public {
        _sanitizeAccessManagerCaller(manager);
        _sanitizeActors(borrower, beneficiary);
        nPayments = uint24(bound(nPayments, 1, ARBITRARY_MAX_PAYMENTS));

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

        _sanitizeERC721Receiver(collateralReceiver, loan);
        _pushTranches(manager, loan, nPayments, address(tintero), nPayments);
        _addLiquidity(totalPrincipal);
        _fund(loan, manager, nPayments);

        IERC20 asset_ = IERC20(TinteroLoan(loan).lendingAsset());

        uint256 tinteroAssetBalanceBefore = asset_.balanceOf(address(tintero));
        uint256 beneficiaryAssetBalanceBefore = asset_.balanceOf(beneficiary);

        uint256 interestAccrued = 0;
        uint256 currentPrincipal = 0;
        // Avoid stack too deep error
        {
            PaymentLib.Payment memory payment = payments[0];
            skip(payment.maturityPeriod + payment.gracePeriod); // Skip to default
            currentPrincipal = payment.principal;
            interestAccrued = payment.accruedInterest(
                uint48(vm.getBlockTimestamp())
            );
        }

        if (interestAccrued > 0) {
            // Make sure user has enough to pay interests
            _mintUSDCTo(beneficiary, interestAccrued);
            beneficiaryAssetBalanceBefore += interestAccrued;
        }

        // Pay current payment
        vm.prank(beneficiary);
        usdc.approve(address(loan), currentPrincipal + interestAccrued);
        vm.prank(beneficiary);
        TinteroLoan(loan).repayCurrent(collateralReceiver);

        // Check collateral tokens are transferred to the collateral receiver
        if (collateralReceiver == address(0)) vm.expectRevert(); // Burned. Nonexistent
        assertEq(endorser.ownerOf(collateralTokenIds[0]), collateralReceiver);

        // Actual assets are transferred to the liquidity provider
        assertEq(
            tinteroAssetBalanceBefore + currentPrincipal + interestAccrued,
            asset_.balanceOf(address(tintero))
        );
        assertEq(
            asset_.balanceOf(address(beneficiary)),
            beneficiaryAssetBalanceBefore - currentPrincipal - interestAccrued
        );
    }

    function testRepayN(
        address borrower,
        address beneficiary,
        address manager,
        uint24 nPayments,
        uint24 nTranches,
        address collateralReceiver
    ) public {
        _sanitizeAccessManagerCaller(manager);
        _sanitizeActors(borrower, beneficiary);

        nPayments = uint24(bound(nPayments, 1, ARBITRARY_MAX_PAYMENTS));
        nTranches = uint24(bound(nTranches, 1, ARBITRARY_MAX_PAYMENTS));
        vm.assume(nTranches <= nPayments);

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

        _sanitizeERC721Receiver(collateralReceiver, loan);

        _pushTranches(manager, loan, nTranches, address(tintero), nPayments);
        _addLiquidity(totalPrincipal);
        _fund(loan, manager, nPayments);

        IERC20 asset_ = IERC20(TinteroLoan(loan).lendingAsset());

        uint256 tinteroAssetBalanceBefore = asset_.balanceOf(address(tintero));
        uint256 beneficiaryAssetBalanceBefore = asset_.balanceOf(beneficiary);

        uint256 interestAccrued = 0;
        {
            // Avoid stack too deep error
            PaymentLib.Payment memory lastPayment = payments[nTranches - 1];
            skip(lastPayment.maturityPeriod + lastPayment.gracePeriod); // Skip to last payment default
            for (uint256 i = 0; i < nPayments; i++) {
                PaymentLib.Payment memory payment = payments[i];
                interestAccrued += payment.accruedInterest(
                    uint48(vm.getBlockTimestamp())
                );
            }
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
            if (collateralReceiver == address(0)) vm.expectRevert(); // Burned. Nonexistent
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
        uint24 nPayments,
        uint24 nTranches,
        uint24 defaultThreshold,
        address repossessReceiver
    ) public {
        _sanitizeAccessManagerCaller(manager);
        _sanitizeActors(borrower, beneficiary);
        (nPayments, nTranches) = _sanitizeTranches(nPayments, nTranches);
        defaultThreshold = _sanitizeDefaultThreshold(
            nPayments,
            defaultThreshold
        );

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

        vm.assume(repossessReceiver != address(0));
        _sanitizeERC721Receiver(repossessReceiver, loan);

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

    function testRepossessRevertNotLiquidityProvider(
        address borrower,
        address beneficiary,
        uint24 nPayments,
        uint24 defaultThreshold,
        address notLiquidityProvider,
        address repossessReceiver
    ) public {
        _sanitizeActors(borrower, beneficiary);
        nPayments = uint24(bound(nPayments, 1, ARBITRARY_MAX_PAYMENTS));
        defaultThreshold = _sanitizeDefaultThreshold(
            nPayments,
            defaultThreshold
        );

        (address loan, , PaymentLib.Payment[] memory payments, ) = _requestLoan(
            borrower,
            beneficiary,
            bytes32(0),
            nPayments,
            defaultThreshold
        );

        vm.assume(repossessReceiver != address(0));
        _sanitizeERC721Receiver(repossessReceiver, loan);

        // Miss `defaultThreshold` payments
        PaymentLib.Payment memory lastPayment = payments[defaultThreshold - 1];
        skip(lastPayment.maturityPeriod + lastPayment.gracePeriod);

        vm.prank(notLiquidityProvider);
        vm.expectRevert();
        TinteroLoan(loan).repossess(0, payments.length, repossessReceiver);
    }
}
