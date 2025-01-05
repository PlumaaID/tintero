// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BaseTest} from "./Base.t.sol";

import {console2} from "forge-std/console2.sol";
import {PaymentLib} from "~/utils/PaymentLib.sol";
import {TinteroLoanFactory} from "~/TinteroLoan.factory.sol";

contract TinteroTest is BaseTest {
    function testMetadata() public view {
        assertEq(tintero.name(), "Tinted USD Coin");
        assertEq(tintero.symbol(), "tUSDC");
        assertEq(tintero.decimals(), usdc.decimals() + 3); // Virtual offset
    }

    function testAsset() public view {
        assertEq(address(tintero.asset()), address(usdc));
    }

    function testAuthority() public view {
        assertEq(tintero.authority(), address(accessManager));
    }

    function testRequestLoan(address caller) public {
        vm.assume(caller != address(this));
        vm.assume(caller != address(0));

        PaymentLib.Payment[] memory payments = _mockPayments(3);
        uint256[] memory collateralTokenIds = _mockCollateralIds(3, caller);

        bytes32 salt = bytes32(uint256(0xdeadbeef));
        (address loan, , ) = tintero.predictLoanAddress(
            address(endorser),
            beneficiary,
            3,
            payments,
            collateralTokenIds,
            salt,
            caller
        );

        vm.startPrank(caller);
        endorser.setApprovalForAll(loan, true);
        vm.expectEmit(address(tintero));
        emit TinteroLoanFactory.LoanCreated(loan);
        tintero.requestLoan(
            address(endorser),
            beneficiary,
            3,
            payments,
            collateralTokenIds,
            salt
        );
        assertTrue(tintero.isLoan(loan));
        vm.stopPrank();

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
