// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BaseTest} from "./Base.t.sol";

contract WitnesserTest is BaseTest {
    function testInitialized() public {
        vm.expectRevert();
        witnesser.initialize(address(0));
    }

    function testAccessManager() public view {
        assertEq(address(witnesser.authority()), address(accessManager));
    }
}
