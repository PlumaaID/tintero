// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {IERC1967} from "@openzeppelin/contracts/interfaces/IERC1967.sol";
import {ERC4626Test} from "erc4626-tests/ERC4626.test.sol";
import {BaseTest} from "./Base.t.sol";

import {PaymentLib} from "~/utils/PaymentLib.sol";
import {TinteroLoan} from "~/TinteroLoan.factory.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {TinteroVaultMock} from "./mocks/TinteroVaultMock.sol";
import {ITinteroVault} from "~/interfaces/ITinteroVault.sol";

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

contract TinteroVaultTest is BaseTest, ERC4626Test {
    ERC20 private _underlying = new ERC20Mock();

    function setUp() public override(BaseTest, ERC4626Test) {
        super.setUp();
        _underlying_ = address(_underlying);
        _vault_ = address(
            new TinteroVaultMock(
                IERC20Metadata(_underlying_),
                address(accessManager)
            )
        );
        _delta_ = 0;
        _vaultMayBeEmpty = false;
        _unlimitedAmount = true;
    }

    // Assume every user is an accredited investor for ERC4626 tests
    function setUpVault(Init memory init) public override {
        _setupTinteroInvestorRole(_vault_);
        for (uint256 i = 0; i < init.user.length; i++) {
            accessManager.grantRole(TINTERO_INVESTOR_ROLE, init.user[i], 0);
        }
        super.setUpVault(init);
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

    function testDelegationFlow(
        uint256 initialLiquidity,
        uint256 amount,
        address delegate
    ) public {
        vm.assume(delegate != address(0));
        // See https://github.com/circlefin/stablecoin-evm/blob/master/contracts/v2/FiatTokenV2_2.sol#L215-L218
        initialLiquidity = bound(initialLiquidity, 1, (1 << 255) - 1);
        amount = bound(amount, 1, initialLiquidity);
        _addLiquidity(initialLiquidity);

        uint256 totalAssetsDelegatedBefore = tintero.totalAssetsDelegated();
        uint256 delegatedToBefore = tintero.delegatedTo(delegate);

        // Must revert if the caller is not an approved delegate
        vm.prank(delegate);
        vm.expectRevert();
        tintero.askDelegation(amount);

        // Delegate is approved
        accessManager.grantRole(TINTERO_DELEGATE_ROLE, delegate, 0);

        // Delegate asks for delegation
        vm.prank(delegate);
        tintero.askDelegation(amount);

        // Delegated assets are updated
        assertEq(
            tintero.totalAssetsDelegated(),
            totalAssetsDelegatedBefore + amount
        );
        assertEq(tintero.delegatedTo(delegate), delegatedToBefore + amount);

        // Delegate returns delegation
        vm.startPrank(delegate);
        usdc.approve(address(tintero), amount);
        tintero.refundDelegation(amount);
        vm.stopPrank();

        // Delegated assets are updated
        assertEq(tintero.totalAssetsDelegated(), totalAssetsDelegatedBefore);
        assertEq(tintero.delegatedTo(delegate), delegatedToBefore);
    }

    function testDelegationWithForcedRefund(
        uint256 initialLiquidity,
        uint256 amount,
        address delegate
    ) public {
        vm.assume(delegate != address(0));
        // See https://github.com/circlefin/stablecoin-evm/blob/master/contracts/v2/FiatTokenV2_2.sol#L215-L218
        initialLiquidity = bound(initialLiquidity, 1, (1 << 255) - 1);
        amount = bound(amount, 1, initialLiquidity);
        _addLiquidity(initialLiquidity);

        uint256 totalAssetsDelegatedBefore = tintero.totalAssetsDelegated();
        uint256 delegatedToBefore = tintero.delegatedTo(delegate);

        // Must revert if the caller is not an approved delegate
        vm.prank(delegate);
        vm.expectRevert();
        tintero.askDelegation(amount);

        // Delegate is approved
        accessManager.grantRole(TINTERO_DELEGATE_ROLE, delegate, 0);

        // Delegate asks for delegation
        vm.prank(delegate);
        tintero.askDelegation(amount);

        // Delegated assets are updated
        assertEq(
            tintero.totalAssetsDelegated(),
            totalAssetsDelegatedBefore + amount
        );
        assertEq(tintero.delegatedTo(delegate), delegatedToBefore + amount);

        // Delegate deposits into the vault. It shouldn't happen with the list of
        // accredited investors, but is possible if we want to lift restrictions
        // in the future.
        accessManager.grantRole(TINTERO_INVESTOR_ROLE, delegate, 0);
        vm.startPrank(delegate);
        usdc.approve(address(tintero), amount);
        tintero.deposit(amount, delegate);
        vm.stopPrank();

        // Force refund
        tintero.forceRefundDelegation(delegate, amount);

        // Delegated assets are updated
        assertEq(tintero.totalAssetsDelegated(), totalAssetsDelegatedBefore);
        assertEq(tintero.delegatedTo(delegate), delegatedToBefore);
        assertEq(usdc.balanceOf(delegate), 0);
        assertEq(tintero.balanceOf(delegate), 0);
    }

    function testRequestLoan(
        address borrower,
        address beneficiary,
        bytes32 salt,
        uint24 nPayments
    ) public {
        _sanitizeActors(borrower, beneficiary);
        nPayments = uint24(bound(nPayments, 0, ARBITRARY_MAX_PAYMENTS));

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
        vm.expectRevert(ITinteroVault.DuplicatedLoan.selector);
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
        uint24 nPayments,
        uint256 nExtraPayments
    ) public {
        _sanitizeAccessManagerCaller(manager);
        _sanitizeActors(borrower, beneficiary);
        nPayments = uint24(bound(nPayments, 0, ARBITRARY_MAX_PAYMENTS));
        nExtraPayments = uint24(
            bound(nExtraPayments, 0, ARBITRARY_MAX_PAYMENTS)
        );

        (address loan, uint256 totalPrincipal, , ) = _requestLoan(
            borrower,
            beneficiary,
            salt,
            nPayments,
            nPayments
        );

        assertEq(usdc.allowance(address(tintero), loan), totalPrincipal);

        PaymentLib.Payment[] memory lastPayments = _mockPayments(
            nPayments,
            nExtraPayments
        );
        uint256[] memory lastCollateralIds = _mockCollateralIds(
            nPayments,
            nExtraPayments,
            borrower
        );

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
        uint24 nPayments,
        uint24 nTranches
    ) public {
        _sanitizeAccessManagerCaller(manager);
        _sanitizeActors(borrower, beneficiary);
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

        uint256 reportedAssetsBefore = tintero.totalAssets();
        uint256 totalAssetsBefore = tintero.totalAssetsLent();

        // Must revert if the address is not a loan
        vm.prank(manager);
        vm.expectRevert();
        tintero.fundN(TinteroLoan(fakeLoan), nPayments);

        // Fund all payments
        _fund(loan, manager, nPayments);

        // Allowance is reset
        assertEq(usdc.allowance(address(tintero), loan), 0);

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

        ) = _requestLoan(
                borrower,
                beneficiary,
                bytes32(0),
                nPayments,
                defaultThreshold
            );

        _sanitizeERC721Receiver(repossessReceiver, loan);

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
        emit IERC1967.Upgraded(newTinteroLoanImpl);
        tintero.upgradeLoan(
            TinteroLoan(loan),
            newTinteroLoanImpl,
            abi.encodeCall(newTinteroLoan.initializeVN, ())
        );
    }
}
