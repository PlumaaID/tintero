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
            endorser.$_safeMint(owner, i);
        }
        return collateralTokenIds;
    }
}
