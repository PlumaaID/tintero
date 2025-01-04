// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";

/// @title Payment Library
///
/// @notice Library for managing loan payments.
///
/// Each payment has a principal amount that is due at the end of the maturity
/// period and defaults after the grace period.
///
/// An interest rate is applied linearly to the principal amount over time until
/// the payment is due. A premium rate is added to the rate thereafter.
library PaymentLib {
    using PaymentLib for Payment;

    uint256 private constant INTEREST_SCALE = 1e6; // ie. 6 decimal places
    uint256 private constant YEAR_IN_SECONDS = 365 days;

    struct Payment {
        uint256 principal;
        uint48 creation; // Up to the year 8,925,512
        uint32 maturityPeriod; // Up to ~136 years
        uint32 gracePeriod; // Up to ~136 years
        uint32 interestRate; // Up to ~4294% annualized
        uint32 premiumRate; // Up to ~4294% annualized
        // 80 bits gap
    }

    /// @dev Whether the principal is due.
    function matured(Payment memory self) internal view returns (bool) {
        return self.matured(Time.timestamp());
    }

    /// @dev Whether the principal is due at a given time.
    function matured(
        Payment memory self,
        uint48 at
    ) internal pure returns (bool) {
        return self.maturedAt() <= at;
    }

    /// @dev The time when the principal is due.
    function maturedAt(Payment memory self) internal pure returns (uint48) {
        return self.creation + self.maturityPeriod;
    }

    /// @dev Whether the payment is defaulted.
    function defaulted(Payment memory self) internal view returns (bool) {
        return self.defaulted(Time.timestamp());
    }

    /// @dev Whether the payment is defaulted at a given time.
    function defaulted(
        Payment memory self,
        uint48 at
    ) internal pure returns (bool) {
        return self.defaultedAt() <= at;
    }

    /// @dev The time when the payment is defaulted.
    function defaultedAt(Payment memory self) internal pure returns (uint48) {
        return self.maturedAt() + self.gracePeriod;
    }

    /// @dev The total amount of interest accrued. This includes both regular and premium interest.
    function accruedInterest(
        Payment memory self,
        uint48 at
    ) internal pure returns (uint256) {
        return
            regularAccruedInterest(self, at) + premiumAccruedInterest(self, at);
    }

    /// @dev The total amount of regular interest accrued.
    function regularAccruedInterest(
        Payment memory self,
        uint48 at
    ) internal pure returns (uint256) {
        uint48 creation = self.creation;
        if (at < creation) return 0;
        return _accruedInterest(self, self.interestRate, creation, at);
    }

    /// @dev The total amount of premium interest accrued.
    function premiumAccruedInterest(
        Payment memory self,
        uint48 at
    ) internal pure returns (uint256) {
        if (!self.matured(at)) return 0;
        return _accruedInterest(self, self.premiumRate, self.maturedAt(), at);
    }

    /// @dev Linear interpolation of the interest linearly accrued between two timepoints.
    /// Precision is maintained by scaling the rate by 1e6.
    function _accruedInterest(
        Payment memory self,
        uint88 rate,
        uint48 since,
        uint48 at
    ) private pure returns (uint256) {
        uint48 elapsed = since - at;
        return
            Math.mulDiv(self.principal * rate, elapsed, YEAR_IN_SECONDS) /
            INTEREST_SCALE;
    }
}
