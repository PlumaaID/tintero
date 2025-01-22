// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Endorser} from "~/Endorser.sol";
import {TinteroLoanFactory, TinteroLoan} from "~/TinteroLoan.factory.sol";
import {PaymentLib} from "~/utils/PaymentLib.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {IWitness, Proof} from "@WitnessCo/interfaces/IWitness.sol";
import {EndorserMock} from "./mocks/EndorserMock.sol";
import {TinteroMock, Tintero} from "./mocks/TinteroMock.sol";
import {USDCTest} from "./USDCTest.t.sol";

contract BaseTest is Test, USDCTest {
    AccessManager internal accessManager;
    EndorserMock internal endorser;
    TinteroMock internal tintero;

    uint256 internal constant ARBITRARY_MAX_PAYMENTS = 1000;

    uint64 internal constant UPGRADER_ROLE =
        uint64(bytes8(keccak256("PlumaaID.UPGRADER")));
    uint64 internal constant PROVENANCE_AUTHORIZER_ROLE =
        uint64(bytes8(keccak256("PlumaaID.PROVENANCE_AUTHORIZER")));
    uint64 internal constant WITNESS_SETTER_ROLE =
        uint64(bytes8(keccak256("PlumaaID.WITNESS_SETTER")));
    uint64 internal constant TINTERO_MANAGER_ROLE =
        uint64(bytes8(keccak256("PlumaaID.TINTERO_MANAGER")));

    // From https://docs.witness.co/additional-notes/deployments
    IWitness constant WITNESS =
        IWitness(0x0000000e143f453f45B2E1cCaDc0f3CE21c2F06a);

    function setUp() public virtual override {
        super.setUp();

        accessManager = new AccessManager(address(this));
        endorser = EndorserMock(
            address(
                new ERC1967Proxy(
                    address(new EndorserMock()),
                    abi.encodeCall(
                        Endorser.initialize,
                        (address(accessManager), WITNESS)
                    )
                )
            )
        );

        tintero = new TinteroMock(
            IERC20Metadata(address(usdc)),
            address(accessManager)
        );

        _setupManagerRole(address(tintero));
        _setupWitnessSetterRole(address(endorser));
        _setupUpgradeRole(address(endorser));
    }

    /***********************/
    /*** Roles Functions ***/
    /***********************/

    function _setupManagerRole(address target) internal {
        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = Tintero.pushPayments.selector;
        selectors[1] = Tintero.pushTranches.selector;
        selectors[2] = Tintero.fundN.selector;
        selectors[3] = Tintero.repossess.selector;
        selectors[4] = Tintero.upgradeLoan.selector;

        accessManager.setTargetFunctionRole(
            target,
            selectors,
            TINTERO_MANAGER_ROLE
        );
    }

    function _setupWitnessSetterRole(address target) internal {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = Endorser.setWitness.selector;

        accessManager.setTargetFunctionRole(
            target,
            selectors,
            WITNESS_SETTER_ROLE
        );
    }

    function _setupUpgradeRole(address target) internal {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = UUPSUpgradeable.upgradeToAndCall.selector;
        accessManager.setTargetFunctionRole(target, selectors, UPGRADER_ROLE);
    }

    /*************************/
    /*** Tintero Functions ***/
    /*************************/

    function _requestLoan(
        address borrower,
        address beneficiary,
        bytes32 salt,
        uint16 nPayments,
        uint16 defaultThreshold
    )
        internal
        returns (
            address loan,
            uint256 totalPrincipal,
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
            defaultThreshold,
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
            defaultThreshold,
            payments,
            collateralTokenIds,
            salt
        );

        vm.stopPrank();

        // Calculate total principal
        for (uint256 i = 0; i < payments.length; i++)
            totalPrincipal += payments[i].principal;
    }

    function _pushTranches(
        address manager,
        address loan,
        uint16 nTranches,
        address trancheRecipient,
        uint16 lastPaymentIndex
    )
        internal
        returns (uint96[] memory paymentIndexes, address[] memory recipients)
    {
        paymentIndexes = new uint96[](nTranches);
        recipients = new address[](nTranches);
        uint256 last = nTranches - 1;
        for (uint256 i = 0; i < last; i++) {
            paymentIndexes[i] = uint96(i + 1);
            recipients[i] = trancheRecipient;
        }

        // Fill the last tranche so that it covers all payments
        paymentIndexes[last] = lastPaymentIndex;
        recipients[last] = trancheRecipient;

        // Must revert if the borrower is not a manager (role not assigned yet)
        vm.prank(manager);
        vm.expectRevert();
        tintero.pushTranches(TinteroLoan(loan), paymentIndexes, recipients);

        // Grant manager role
        accessManager.grantRole(TINTERO_MANAGER_ROLE, manager, 0);

        // Manager pushes tranches
        vm.prank(manager);
        tintero.pushTranches(TinteroLoan(loan), paymentIndexes, recipients);
    }

    function _addLiquidity(uint256 amount) internal {
        _mintUSDCTo(address(this), amount);
        usdc.approve(address(tintero), amount);
        tintero.deposit(amount, address(this));
    }

    function _fund(address loan, address manager, uint256 nPayments) internal {
        vm.prank(manager);
        tintero.fundN(TinteroLoan(loan), nPayments);
    }

    function _repossess(
        address loan,
        address manager,
        PaymentLib.Payment[] memory payments,
        uint16 defaultThreshold,
        address repossessReceiver
    ) internal {
        // Miss `defaultThreshold` payments
        PaymentLib.Payment memory lastPayment = payments[defaultThreshold - 1];
        skip(lastPayment.maturityPeriod);

        vm.prank(manager);
        tintero.repossess(
            TinteroLoan(loan),
            0,
            payments.length,
            repossessReceiver
        );
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

    function _sanitizeActors(
        address borrower,
        address beneficiary
    ) internal pure {
        // Can't be 0 or transfer will fail
        vm.assume(borrower != address(0)); // Reverts collecting collateral
        vm.assume(beneficiary != address(0)); // Reverts transferring the lent asset
    }

    function _sanitizeTranches(
        uint256 nPayments,
        uint256 nTranches
    ) internal pure returns (uint16 sanitizedTranches) {
        vm.assume(nPayments <= ARBITRARY_MAX_PAYMENTS);
        // There must be at least 1 tranche, otherwise reverts
        sanitizedTranches = uint16(bound(nTranches, 1, ARBITRARY_MAX_PAYMENTS));
        // There can be only as much tranches as payments
        vm.assume(sanitizedTranches <= nPayments);
        return sanitizedTranches;
    }

    function _sanitizeDefaultThreshold(
        uint16 nPayments,
        uint16 defaultThreshold
    ) internal pure returns (uint16 sanitizedDefaultThreshold) {
        // Must be at least 1 so that there's at least 1 payment
        // otherwise it can't push tranches as it would be already defaulted
        uint16 minThreshold = 1;
        return uint16(bound(defaultThreshold, minThreshold, nPayments));
    }
}
