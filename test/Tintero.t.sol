// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {ERC4626Test} from "erc4626-tests/ERC4626.test.sol";
import {BaseTest} from "./Base.t.sol";

import {console2} from "forge-std/console2.sol";
import {PaymentLib} from "~/utils/PaymentLib.sol";
import {TinteroLoanFactory, TinteroLoan} from "~/TinteroLoan.factory.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {TinteroMock, Tintero} from "./mocks/TinteroMock.sol";

contract ERC20Mock is ERC20 {
    constructor() ERC20("ERC20Mock", "E20M") {}

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) external {
        _burn(account, amount);
    }
}

contract TinteroTest is BaseTest, ERC4626Test {
    ERC20 private _underlying = new ERC20Mock();

    function setUp() public override(BaseTest, ERC4626Test) {
        super.setUp();
        _underlying_ = address(_underlying);
        _vault_ = address(
            new TinteroMock(
                IERC20Metadata(_underlying_),
                address(accessManager)
            )
        );
        _delta_ = 0;
        _vaultMayBeEmpty = false;
        _unlimitedAmount = true;
    }

    function testMetadata() public view {
        assertEq(tintero.name(), "Tinted USD Coin");
        assertEq(tintero.symbol(), "tUSDC");
        assertEq(tintero.decimals(), usdc.decimals());
    }

    function testAsset() public view {
        assertEq(address(tintero.asset()), address(usdc));
    }

    function testAuthority() public view {
        assertEq(tintero.authority(), address(accessManager));
    }

    function testRequestLoan(
        address borrower,
        address beneficiary,
        bytes32 salt,
        uint16 nPayments
    ) public {
        vm.assume(nPayments <= 300);

        vm.assume(borrower != address(this));

        // Can't be 0 or transfer will fail
        vm.assume(borrower != address(0));
        vm.assume(beneficiary != address(0));

        // Any borrower can request a loan to any beneficiary
        (
            ,
            address loan,
            PaymentLib.Payment[] memory payments,
            uint256[] memory collateralTokenIds
        ) = _requestLoan(borrower, beneficiary, salt, nPayments);

        // Loan is added to the management list
        assertTrue(tintero.isLoan(loan));

        // Check payments and calculate total principal to be funded
        uint256 totalPrincipal = 0;
        for (uint256 i = 0; i < payments.length; i++) {
            (
                uint256 collateralTokenId,
                PaymentLib.Payment memory payment
            ) = TinteroLoan(loan).payment(i);
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
        assertEq(TinteroLoan(loan).totalPayments(), nPayments);
        assertEq(TinteroLoan(loan).currentPaymentIndex(), 0);
        if (nPayments > 0) {
            (
                uint256 currentCollateralId,
                PaymentLib.Payment memory currentPayment
            ) = TinteroLoan(loan).currentPayment();
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

        // Fails creating the loan again
        vm.startPrank(borrower);
        vm.expectRevert(Tintero.DuplicatedLoan.selector);
        tintero.requestLoan(
            address(endorser),
            beneficiary,
            nPayments,
            payments,
            collateralTokenIds,
            salt
        );
    }

    function testPushPayments(
        address borrower,
        address beneficiary,
        address manager,
        address fakeLoan,
        bytes32 salt,
        uint16 nPayments,
        uint256 nExtraPayments
    ) public {
        vm.assume(nPayments <= 300);
        vm.assume(nExtraPayments <= 300);

        vm.assume(borrower != address(this));
        vm.assume(manager != address(this));

        // Can't be 0 or transfer will fail
        vm.assume(borrower != address(0));
        vm.assume(beneficiary != address(0));

        (
            ,
            address loan,
            PaymentLib.Payment[] memory payments,
            uint256[] memory collateralTokenIds
        ) = _requestLoan(borrower, beneficiary, salt, nPayments);

        PaymentLib.Payment[] memory lastPayments = _mockPayments(
            nPayments,
            nExtraPayments
        );
        uint256[] memory lastCollateralIds = _mockCollateralIds(
            nPayments,
            nExtraPayments,
            borrower
        );

        // Must revert if the borrower is not a manager (role not assigned yet)
        vm.prank(manager);
        vm.expectRevert();
        tintero.pushPayments(
            TinteroLoan(loan),
            lastCollateralIds,
            lastPayments
        );

        // Grant manager role
        accessManager.grantRole(TINTERO_MANAGER_ROLE, manager, 0);

        // Must revert if the address is not a loan
        vm.prank(manager);
        vm.expectRevert();
        tintero.pushPayments(
            TinteroLoan(fakeLoan),
            collateralTokenIds,
            lastPayments
        );

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
        address fakeLoan,
        bytes32 salt,
        uint16 nPayments,
        uint16 nTranches,
        address trancheRecipient
    ) public {
        vm.assume(nTranches <= nPayments);
        vm.assume(nPayments <= 300);

        vm.assume(borrower != address(this));
        vm.assume(manager != address(this));

        // Can't be 0 or transfer will fail
        vm.assume(borrower != address(0));
        vm.assume(beneficiary != address(0));

        (, address loan, , ) = _requestLoan(
            borrower,
            beneficiary,
            salt,
            nPayments
        );

        uint96[] memory paymentIndexes = new uint96[](nTranches);
        address[] memory recipients = new address[](nTranches);
        for (uint256 i = 0; i < nTranches; i++) {
            paymentIndexes[i] = uint96(i + 1);
            recipients[i] = trancheRecipient;
        }

        // Must revert if the borrower is not a manager (role not assigned yet)
        vm.prank(manager);
        vm.expectRevert();
        tintero.pushTranches(TinteroLoan(loan), paymentIndexes, recipients);

        // Grant manager role
        accessManager.grantRole(TINTERO_MANAGER_ROLE, manager, 0);

        // Must revert if the address is not a loan
        vm.prank(manager);
        vm.expectRevert();
        tintero.pushTranches(TinteroLoan(fakeLoan), paymentIndexes, recipients);

        // Manager pushes tranches
        vm.prank(manager);
        tintero.pushTranches(TinteroLoan(loan), paymentIndexes, recipients);

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
        address fakeLoan,
        uint16 nPayments,
        uint16 nTranches,
        address trancheRecipient
    ) public {
        vm.assume(nPayments <= 300);
        nTranches = uint16(bound(nTranches, 1, 300));
        vm.assume(nTranches <= nPayments);

        vm.assume(borrower != address(this));
        vm.assume(manager != address(this));

        // Can't be 0 or transfer will fail
        vm.assume(borrower != address(0));
        vm.assume(beneficiary != address(0));

        (uint256 totalPrincipal, address loan, , ) = _requestLoan(
            borrower,
            beneficiary,
            bytes32(0),
            nPayments
        );

        // Avoid stack too deep error
        {
            uint96[] memory paymentIndexes = new uint96[](nTranches);
            address[] memory recipients = new address[](nTranches);
            for (uint256 i = 0; i < nTranches; i++) {
                paymentIndexes[i] = uint96(i + 1);
                recipients[i] = trancheRecipient;
            }
            // Must revert if the borrower is not a manager (role not assigned yet)
            vm.prank(manager);
            vm.expectRevert();
            tintero.pushTranches(TinteroLoan(loan), paymentIndexes, recipients);

            // Grant manager role
            accessManager.grantRole(TINTERO_MANAGER_ROLE, manager, 0);

            // Adds liquidity to Tintero
            uint256 amount = 1000 * 10 ** 6;
            _mintUSDCTo(address(this), amount);
            usdc.approve(address(tintero), amount);
            tintero.deposit(amount, address(this));

            // Fill the tranches
            vm.prank(manager);
            tintero.pushTranches(TinteroLoan(loan), paymentIndexes, recipients);

            // Must revert if the address is not a loan
            vm.prank(manager);
            vm.expectRevert();
            tintero.pushTranches(
                TinteroLoan(fakeLoan),
                paymentIndexes,
                recipients
            );
        }
        IERC20Metadata asset_ = IERC20Metadata(tintero.asset());

        uint256 tinteroAssetBalanceBefore = asset_.balanceOf(address(tintero));
        uint256 beneficiaryAssetBalanceBefore = asset_.balanceOf(beneficiary);
        uint256 reportedAssetsBefore = tintero.totalAssets();
        uint256 totalAssetsBefore = tintero.totalAssetsLent();

        {
            // Fund all payments
            vm.prank(manager);
            tintero.fundN(TinteroLoan(loan), nPayments);
        }

        // Actual assets are transferred to the beneficiary
        assertEq(
            asset_.balanceOf(beneficiary),
            beneficiaryAssetBalanceBefore + totalPrincipal
        );
        assertEq(
            asset_.balanceOf(address(tintero)),
            tinteroAssetBalanceBefore - totalPrincipal
        );
        // Reported assets remain the same
        assertEq(tintero.totalAssets(), reportedAssetsBefore);
        // Total assets lent are updated
        assertEq(tintero.totalAssetsLent(), totalAssetsBefore + totalPrincipal);
        assertEq(tintero.lentTo(loan), totalPrincipal);
    }

    function _requestLoan(
        address borrower,
        address beneficiary,
        bytes32 salt,
        uint16 nPayments
    )
        internal
        returns (
            uint256 totalPrincipal,
            address loan,
            PaymentLib.Payment[] memory payments,
            uint256[] memory collateralTokenIds
        )
    {
        payments = _mockPayments(0, nPayments);
        collateralTokenIds = _mockCollateralIds(0, nPayments, borrower);

        // User predicts the loan address before creating it (so that it can approve, for example)
        (loan, , ) = tintero.predictLoanAddress(
            address(endorser),
            beneficiary,
            nPayments,
            salt,
            borrower
        );

        vm.startPrank(borrower);

        // Approve the loan to operate their tokens
        endorser.setApprovalForAll(loan, true);

        // Loan event must be emitted
        vm.expectEmit(address(tintero));
        emit TinteroLoanFactory.LoanCreated(loan);

        // Execute loan request
        tintero.requestLoan(
            address(endorser),
            beneficiary,
            nPayments,
            payments,
            collateralTokenIds,
            salt
        );

        vm.stopPrank();

        // Calculate total principal
        for (uint256 i = 0; i < payments.length; i++)
            totalPrincipal += payments[i].principal;
    }

    function _mockPayments(
        uint256 start,
        uint256 n
    ) internal view returns (PaymentLib.Payment[] memory) {
        PaymentLib.Payment[] memory payments = new PaymentLib.Payment[](n);
        for (uint256 i = 0; i < payments.length; i++) {
            uint32 maturityPeriod = uint32((start + i + 1) * 1 days);
            uint32 gracePeriod = uint32((start + i + 2) * 1 days);
            payments[i] = PaymentLib.Payment(
                100 * (start + i + 1),
                uint48(block.timestamp),
                maturityPeriod,
                gracePeriod,
                12 * (10 ** 4), // 12% regular interest
                18 * (10 ** 4) // 18% premium interest
            );
        }
        return payments;
    }

    function _mockCollateralIds(
        uint256 start,
        uint256 n,
        address owner
    ) internal returns (uint256[] memory) {
        uint256[] memory collateralTokenIds = new uint256[](n);
        for (uint256 i = 0; i < collateralTokenIds.length; i++) {
            collateralTokenIds[i] = start + i;
            endorser.$_mint(owner, start + i);
        }
        return collateralTokenIds;
    }
}
