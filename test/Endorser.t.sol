// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BaseTest} from "./Base.t.sol";

contract EndorserTest is BaseTest {
    function testInitialized() public {
        vm.expectRevert();
        endorser.initialize(address(this), address(this));
    }

    function testAccessManager() public view {
        assertEq(address(endorser.authority()), address(accessManager));
    }
}
