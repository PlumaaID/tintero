// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {ERC4626Test} from "erc4626-tests/ERC4626.test.sol";
import {BaseTest} from "./Base.t.sol";

import {PaymentLib} from "~/utils/PaymentLib.sol";
import {TinteroLoan} from "~/TinteroLoan.factory.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {TinteroMock, Tintero} from "./mocks/TinteroMock.sol";

contract TinteroLoanVN is TinteroLoan {
    function initializeVN() public reinitializer(2) {}

    function version() public pure returns (string memory) {
        return "N";
    }
}

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
        _sanitizeActors(borrower, beneficiary);
        vm.assume(nPayments <= 1000);

        // Any borrower can request a loan to any beneficiary
        (
            address loan,
            ,
            PaymentLib.Payment[] memory payments,
            uint256[] memory collateralTokenIds
        ) = _requestLoan(borrower, beneficiary, salt, nPayments, nPayments);

        // Loan is added to the management list
        assertTrue(tintero.isLoan(loan));

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

    function testLoanPushPayments(
        address borrower,
        address beneficiary,
        address manager,
        address fakeLoan,
        bytes32 salt,
        uint16 nPayments,
        uint256 nExtraPayments
    ) public {
        _sanitizeActors(borrower, beneficiary);
        vm.assume(nPayments <= 1000);
        vm.assume(nExtraPayments <= 1000);

        (address loan, , , ) = _requestLoan(
            borrower,
            beneficiary,
            salt,
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
            lastCollateralIds,
            lastPayments
        );

        // Manager pushes extra payments
        vm.prank(manager);
        tintero.pushPayments(
            TinteroLoan(loan),
            lastCollateralIds,
            lastPayments
        );
    }

    function testLoanPushTranches(
        address borrower,
        address beneficiary,
        address manager,
        address fakeLoan,
        bytes32 salt,
        uint16 nPayments,
        uint16 nTranches,
        address trancheRecipient
    ) public {
        _sanitizeActors(borrower, beneficiary);
        nTranches = _sanitizeTranches(nPayments, nTranches);

        (address loan, , , ) = _requestLoan(
            borrower,
            beneficiary,
            salt,
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

        // Must revert if the address is not a loan
        vm.prank(manager);
        vm.expectRevert();
        tintero.pushTranches(TinteroLoan(fakeLoan), paymentIndexes, recipients);
    }

    function testLoanFundN(
        address borrower,
        address beneficiary,
        address manager,
        address fakeLoan,
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

        uint256 reportedAssetsBefore = tintero.totalAssets();
        uint256 totalAssetsBefore = tintero.totalAssetsLent();

        // Must revert if the address is not a loan
        vm.prank(manager);
        vm.expectRevert();
        tintero.fundN(TinteroLoan(fakeLoan), nPayments);

        // Fund all payments
        _fund(loan, manager, nPayments);

        // Reported assets remain the same
        assertEq(tintero.totalAssets(), reportedAssetsBefore);
        // Total assets lent are updated
        assertEq(tintero.totalAssetsLent(), totalAssetsBefore + totalPrincipal);
        assertEq(tintero.lentTo(loan), totalPrincipal);
    }

    function testLoanRepossess(
        address borrower,
        address beneficiary,
        address manager,
        address fakeLoan,
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

        vm.assume(repossessReceiver.code.length == 0); // EOAs (and also simulates ERC721Holders)
        (
            address loan,
            uint256 totalPrincipal,
            PaymentLib.Payment[] memory payments,

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

        // Must revert if default threshold is not reached
        vm.prank(manager);
        vm.expectRevert();
        tintero.repossess(TinteroLoan(loan), 0, nPayments, repossessReceiver);

        // Must revert if the address is not a loan
        vm.prank(manager);
        vm.expectRevert();
        tintero.repossess(
            TinteroLoan(fakeLoan),
            0,
            nPayments,
            repossessReceiver
        );

        _repossess(
            loan,
            manager,
            payments,
            defaultThreshold,
            repossessReceiver
        );
    }

    function testLoanUpgradeLoan(
        address borrower,
        address beneficiary,
        address manager,
        address fakeLoan,
        uint16 nPayments,
        uint16 nTranches,
        address repossessReceiver
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

        TinteroLoanVN newTinteroLoan = new TinteroLoanVN();
        address newTinteroLoanImpl = address(newTinteroLoan);

        // Must revert if the borrower is not a manager (role not assigned yet)
        vm.prank(manager);
        vm.expectRevert();
        tintero.upgradeLoan(
            TinteroLoan(loan),
            newTinteroLoanImpl,
            abi.encodeCall(newTinteroLoan.initializeVN, ())
        );

        // Grant manager role
        accessManager.grantRole(TINTERO_MANAGER_ROLE, manager, 0);

        // Must revert if the loan is not a TinteroLoan
        vm.prank(manager);
        vm.expectRevert();
        tintero.upgradeLoan(
            TinteroLoan(fakeLoan),
            newTinteroLoanImpl,
            abi.encodeCall(newTinteroLoan.initializeVN, ())
        );

        vm.prank(manager);
        vm.expectEmit(loan);
        emit ERC1967Utils.Upgraded(newTinteroLoanImpl);
        tintero.upgradeLoan(
            TinteroLoan(loan),
            newTinteroLoanImpl,
            abi.encodeCall(newTinteroLoan.initializeVN, ())
        );
    }
}
