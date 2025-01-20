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

    function testRequestLoan(address caller, bytes32 salt) public {
        vm.assume(caller != address(this));
        vm.assume(caller != address(0));

        PaymentLib.Payment[] memory payments = _mockPayments(3);
        uint256[] memory collateralTokenIds = _mockCollateralIds(3, caller);

        // User predicts the loan address before creating it (so that it can approve, for example)
        (address loan, , ) = tintero.predictLoanAddress(
            address(endorser),
            beneficiary,
            3,
            salt,
            caller
        );

        vm.startPrank(caller);

        // The caller approves the loan to operate their tokens
        endorser.setApprovalForAll(loan, true);

        // Loan event must be emitted
        vm.expectEmit(address(tintero));
        emit TinteroLoanFactory.LoanCreated(loan);

        // Execute loan request
        tintero.requestLoan(
            address(endorser),
            beneficiary,
            3,
            payments,
            collateralTokenIds,
            salt
        );

        // Loan is added to the management list
        assertTrue(tintero.isLoan(loan));

        vm.stopPrank();

        // Collateral tokens are transferred to the loan
        for (uint256 i = 0; i < collateralTokenIds.length; i++)
            assertEq(endorser.ownerOf(collateralTokenIds[i]), loan);

        // Fails creating the loan again
        vm.startPrank(caller);
        vm.expectRevert(Tintero.DuplicatedLoan.selector);
        tintero.requestLoan(
            address(endorser),
            beneficiary,
            3,
            payments,
            collateralTokenIds,
            salt
        );
    }

    function testPushPayments(
        address caller,
        address manager,
        bytes32 salt
    ) public {
        vm.assume(caller != address(this));
        vm.assume(caller != address(0));
        vm.assume(manager != address(this));

        PaymentLib.Payment[] memory payments = _mockPayments(6);
        uint256[] memory collateralTokenIds = _mockCollateralIds(6, caller);

        PaymentLib.Payment[] memory firstPayments = new PaymentLib.Payment[](3);
        uint256[] memory firstCollateralIds = new uint256[](3);
        for (uint256 i = 0; i < firstPayments.length; i++) {
            firstPayments[i] = payments[i];
            firstCollateralIds[i] = collateralTokenIds[i];
        }

        // User predicts the loan address before creating it (so that it can approve, for example)
        (address loan, , ) = tintero.predictLoanAddress(
            address(endorser),
            beneficiary,
            3,
            salt,
            caller
        );

        vm.startPrank(caller);

        // The caller approves the loan to operate their tokens
        endorser.setApprovalForAll(loan, true);

        // Execute loan request
        tintero.requestLoan(
            address(endorser),
            beneficiary,
            3,
            firstPayments,
            firstCollateralIds,
            salt
        );

        // Push payments
        PaymentLib.Payment[] memory lastPayments = new PaymentLib.Payment[](3);
        uint256[] memory lastCollateralIds = new uint256[](3);
        for (uint256 i = 0; i < lastPayments.length; i++) {
            lastPayments[i] = payments[i + 3];
            lastCollateralIds[i] = collateralTokenIds[i + 3];
        }

        vm.stopPrank();

        // Must revert if the caller is not a manager (role not assigned yet)
        vm.prank(manager);
        vm.expectRevert();
        tintero.pushPayments(
            TinteroLoan(loan),
            lastCollateralIds,
            lastPayments
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
    }

    function testPushTranches(address manager) public {
        vm.assume(manager != address(this));

        address loan = _setupLoan();

        uint96[] memory paymentIndexes = new uint96[](2);
        address[] memory recipients = new address[](2);

        paymentIndexes[0] = 1;
        paymentIndexes[1] = 2;
        recipients[0] = address(this);
        recipients[1] = address(this);

        // Must revert if the caller is not a manager (role not assigned yet)
        vm.prank(manager);
        vm.expectRevert();
        tintero.pushTranches(TinteroLoan(loan), paymentIndexes, recipients);

        // Grant manager role
        accessManager.grantRole(TINTERO_MANAGER_ROLE, manager, 0);

        // Manager pushes tranches
        vm.prank(manager);
        tintero.pushTranches(TinteroLoan(loan), paymentIndexes, recipients);

        // Does not revert
    }

    function testFundN(address manager) public {
        vm.assume(manager != address(this));

        address loan = _setupLoan();

        // Calculate total principal to be funded
        uint256 totalPrincipal = 0;
        for (uint256 i = 0; i < 3; i++) {
            (, PaymentLib.Payment memory payment) = TinteroLoan(loan).payment(
                i
            );
            totalPrincipal += payment.principal;
        }

        // Push tranches
        uint96[] memory paymentIndexes = new uint96[](2);
        address[] memory recipients = new address[](2);

        paymentIndexes[0] = 1;
        paymentIndexes[1] = 2;
        recipients[0] = address(this);
        recipients[1] = address(this);

        // Must revert if the caller is not a manager (role not assigned yet)
        vm.prank(manager);
        vm.expectRevert();
        tintero.pushTranches(TinteroLoan(loan), paymentIndexes, recipients);

        // Grant manager role
        accessManager.grantRole(TINTERO_MANAGER_ROLE, manager, 0);

        // Adds liquidity to Tintero
        _mintUSDCTo(address(this), 1000 * 10 ** 6);
        usdc.approve(address(tintero), 1000 * 10 ** 6);
        tintero.deposit(1000 * 10 ** 6, address(this));

        uint256 tinteroAssetBalanceBefore = IERC20Metadata(tintero.asset())
            .balanceOf(address(tintero));
        uint256 reportedAssetsBefore = tintero.totalAssets();
        uint256 totalAssetsBefore = tintero.totalAssetsLent();

        // Fill the tranches and fund all payments payments
        vm.startPrank(manager);
        tintero.pushTranches(TinteroLoan(loan), paymentIndexes, recipients);
        tintero.fundN(TinteroLoan(loan), 3);
        vm.stopPrank();

        // Actual assets are transferred to the loan
        assertEq(
            IERC20Metadata(tintero.asset()).balanceOf(address(tintero)),
            tinteroAssetBalanceBefore - totalPrincipal
        );
        // Reported assets remain the same
        assertEq(tintero.totalAssets(), reportedAssetsBefore);
        // Total assets lent are updated
        assertEq(tintero.totalAssetsLent(), totalAssetsBefore + totalPrincipal);
        assertEq(tintero.lentTo(loan), totalPrincipal);
    }

    function _setupLoan() internal returns (address) {
        PaymentLib.Payment[] memory payments = _mockPayments(3);
        uint256[] memory collateralTokenIds = _mockCollateralIds(
            3,
            address(this)
        );

        PaymentLib.Payment[] memory firstPayments = new PaymentLib.Payment[](3);
        uint256[] memory firstCollateralIds = new uint256[](3);
        for (uint256 i = 0; i < firstPayments.length; i++) {
            firstPayments[i] = payments[i];
            firstCollateralIds[i] = collateralTokenIds[i];
        }

        // User predicts the loan address before creating it (so that it can approve, for example)
        (address loan, , ) = tintero.predictLoanAddress(
            address(endorser),
            beneficiary,
            3,
            bytes32(0),
            address(this)
        );

        // Approve the loan to operate their tokens
        endorser.setApprovalForAll(loan, true);

        // Execute loan request
        tintero.requestLoan(
            address(endorser),
            beneficiary,
            3,
            firstPayments,
            firstCollateralIds,
            bytes32(0)
        );

        return loan;
    }

    function _mockPayments(
        uint256 n
    ) internal view returns (PaymentLib.Payment[] memory) {
        PaymentLib.Payment[] memory payments = new PaymentLib.Payment[](n);
        for (uint256 i = 0; i < payments.length; i++) {
            payments[i] = PaymentLib.Payment(
                100 * (i + 1),
                uint48(block.timestamp),
                60 days, // 60 days maturity period
                30 days, // 30 days grace period
                12 * (10 ** 4), // 12% regular interest
                18 * (10 ** 4) // 18% premium interest
            );
        }
        return payments;
    }

    function _mockCollateralIds(
        uint256 n,
        address owner
    ) internal returns (uint256[] memory) {
        uint256[] memory collateralTokenIds = new uint256[](n);
        for (uint256 i = 0; i < collateralTokenIds.length; i++) {
            collateralTokenIds[i] = i;
            endorser.$_mint(owner, i);
        }
        return collateralTokenIds;
    }
}
