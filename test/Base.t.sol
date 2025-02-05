// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Endorser} from "~/Endorser.sol";
import {ITinteroLoan} from "~/interfaces/ITinteroLoan.sol";
import {ITinteroVault} from "~/interfaces/ITinteroVault.sol";
import {PaymentLib} from "~/utils/PaymentLib.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {IWitness, Proof} from "@WitnessCo/interfaces/IWitness.sol";
import {EndorserMock} from "./mocks/EndorserMock.sol";
import {TinteroVaultMock, TinteroVault} from "./mocks/TinteroVaultMock.sol";
import {USDCTest} from "./USDCTest.t.sol";
import {LoanState} from "~/interfaces/ITinteroLoan.types.sol";

contract BaseTest is Test, USDCTest {
    AccessManager internal accessManager;
    address endorserImplementation;
    EndorserMock internal endorser;
    TinteroVaultMock internal tintero;

    uint256 internal constant ARBITRARY_MAX_PAYMENTS = 100;

    uint64 internal constant UPGRADER_ROLE =
        uint64(bytes8(keccak256("PlumaaID.UPGRADER")));
    uint64 internal constant PROVENANCE_AUTHORIZER_ROLE =
        uint64(bytes8(keccak256("PlumaaID.PROVENANCE_AUTHORIZER")));
    uint64 internal constant WITNESS_SETTER_ROLE =
        uint64(bytes8(keccak256("PlumaaID.WITNESS_SETTER")));
    uint64 internal constant TINTERO_MANAGER_USDC_V01_ROLE =
        uint64(bytes8(keccak256("PlumaaID.TINTERO_MANAGER_USDC_V01")));
    uint64 internal constant TINTERO_DELEGATE_USDC_V01_ROLE =
        uint64(bytes8(keccak256("PlumaaID.TINTERO_DELEGATE_USDC_V01")));
    uint64 internal constant TINTERO_INVESTOR_USDC_V01_ROLE =
        uint64(bytes8(keccak256("PlumaaID.TINTERO_INVESTOR_USDC_V01")));

    // From https://docs.witness.co/additional-notes/deployments
    IWitness constant WITNESS =
        IWitness(0x0000000e143f453f45B2E1cCaDc0f3CE21c2F06a);

    function setUp() public virtual override {
        super.setUp();

        accessManager = new AccessManager(address(this));
        endorserImplementation = address(new EndorserMock());
        endorser = EndorserMock(
            address(
                new ERC1967Proxy(
                    endorserImplementation,
                    abi.encodeCall(
                        Endorser.initialize,
                        (address(accessManager), WITNESS)
                    )
                )
            )
        );

        tintero = new TinteroVaultMock(
            IERC20Metadata(address(usdc)),
            address(accessManager)
        );

        _setupDelegateRole(address(tintero));
        _setupManagerRole(address(tintero));
        _setupTinteroInvestorRole(address(tintero));
        _setupWitnessSetterRole(address(endorser));
        _setupUpgradeRole(address(endorser));
    }

    /***********************/
    /*** Roles Functions ***/
    /***********************/

    function _setupDelegateRole(address target) internal {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = TinteroVault.askDelegation.selector;

        accessManager.setTargetFunctionRole(
            target,
            selectors,
            TINTERO_DELEGATE_USDC_V01_ROLE
        );
    }

    function _setupManagerRole(address target) internal {
        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = TinteroVault.pushPayments.selector;
        selectors[1] = TinteroVault.pushTranches.selector;
        selectors[2] = TinteroVault.fundN.selector;
        selectors[3] = TinteroVault.repossess.selector;
        selectors[4] = TinteroVault.upgradeLoan.selector;

        accessManager.setTargetFunctionRole(
            target,
            selectors,
            TINTERO_MANAGER_USDC_V01_ROLE
        );
    }

    function _setupTinteroInvestorRole(address target) internal {
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = TinteroVault.deposit.selector;
        selectors[1] = TinteroVault.mint.selector;

        accessManager.setTargetFunctionRole(
            target,
            selectors,
            TINTERO_INVESTOR_USDC_V01_ROLE
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
        uint24 nPayments,
        uint24 defaultThreshold
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
        emit ITinteroVault.LoanCreated(
            loan,
            address(endorser),
            beneficiary,
            defaultThreshold
        );

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

        // Initial state
        assertEq(uint8(ITinteroLoan(loan).state()), uint8(LoanState.CREATED));

        // Calculate total principal
        for (uint256 i = 0; i < payments.length; i++)
            totalPrincipal += payments[i].principal;
    }

    function _pushTranches(
        address manager,
        address loan,
        uint24 nTranches,
        address trancheRecipient,
        uint24 lastPaymentIndex
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
        tintero.pushTranches(ITinteroLoan(loan), paymentIndexes, recipients);

        // Grant manager role
        accessManager.grantRole(TINTERO_MANAGER_USDC_V01_ROLE, manager, 0);

        // Manager pushes tranches
        vm.prank(manager);
        tintero.pushTranches(ITinteroLoan(loan), paymentIndexes, recipients);
    }

    function _addLiquidity(uint256 amount) internal {
        _mintUSDCTo(address(this), amount);
        usdc.approve(address(tintero), amount);
        accessManager.grantRole(TINTERO_INVESTOR_USDC_V01_ROLE, address(this), 0); // Grant investor role
        tintero.deposit(amount, address(this));
    }

    function _fund(address loan, address manager, uint256 nPayments) internal {
        vm.prank(manager);
        tintero.fundN(ITinteroLoan(loan), nPayments);
    }

    function _repossess(
        address loan,
        address manager,
        PaymentLib.Payment[] memory payments,
        uint24 defaultThreshold,
        address repossessReceiver
    ) internal {
        // Miss `defaultThreshold` payments
        PaymentLib.Payment memory lastPayment = payments[defaultThreshold - 1];
        skip(lastPayment.maturityPeriod + lastPayment.gracePeriod);

        vm.prank(manager);
        tintero.repossess(
            ITinteroLoan(loan),
            0,
            payments.length,
            repossessReceiver
        );
    }

    function _mockPayments(
        uint256 start,
        uint256 n
    ) internal pure returns (PaymentLib.Payment[] memory) {
        PaymentLib.Payment[] memory payments = new PaymentLib.Payment[](n);
        for (uint256 i = 0; i < payments.length; i++) {
            uint32 maturityPeriod = uint32((start + i + 1) * 1 days);
            uint32 gracePeriod = uint32((start + i + 2) * 1 days);
            payments[i] = PaymentLib.Payment(
                uint96(100 * (start + i + 1)),
                uint48(0),
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
    )
        internal
        pure
        returns (uint24 sanitizedNPayments, uint24 sanitizedNTranches)
    {
        sanitizedNPayments = uint24(
            bound(nPayments, 0, ARBITRARY_MAX_PAYMENTS)
        );
        // There must be at least 1 tranche, otherwise reverts
        sanitizedNTranches = uint24(
            bound(nTranches, 1, ARBITRARY_MAX_PAYMENTS)
        );
        // There can be only as much tranches as payments
        vm.assume(sanitizedNTranches <= sanitizedNPayments);
        return (sanitizedNPayments, sanitizedNTranches);
    }

    function _sanitizeDefaultThreshold(
        uint24 nPayments,
        uint24 defaultThreshold
    ) internal pure returns (uint24 sanitizedDefaultThreshold) {
        // Must be at least 1 so that there's at least 1 payment
        // otherwise it can't push tranches as it would be already defaulted
        uint24 minThreshold = 1;
        return uint24(bound(defaultThreshold, minThreshold, nPayments));
    }

    function _sanitizeAccessManagerCaller(address caller) internal view {
        vm.assume(caller != address(accessManager)); // The manager can't call other contracts and can't have a role itself.
    }

    function _sanitizeERC721Receiver(
        address receiver,
        address loan
    ) internal view {
        // None of these implements the IERC721Receiver interface
        vm.assume(receiver != 0x4e59b44847b379578588920cA78FbF26c0B4956C); // Create2Deployer
        vm.assume(receiver != loan);
        vm.assume(receiver != address(accessManager));
        vm.assume(receiver != address(tintero));
        vm.assume(receiver != address(endorser));
        vm.assume(receiver != endorserImplementation);
        vm.assume(receiver != address(this));
        vm.assume(receiver != address(usdc));
        vm.assume(
            receiver != tintero.INITIAL_ERC721_COLLATERAL_LOAN_IMPLEMENTATION()
        );
        vm.assume(receiver != address(vm));
    }
}
