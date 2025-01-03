// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BaseTest} from "./Base.t.sol";

import {console2} from "forge-std/console2.sol";

contract TinteroTest is BaseTest {
    function testAsset() public view {
        assertEq(address(tintero.asset()), address(usdc));
    }
}
