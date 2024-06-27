// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BaseTest} from "./Base.t.sol";
import {Witness} from "~/Witness.sol";

contract WitnessTest is BaseTest {
    function setUp() public override {
        super.setUp();
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = Witness.witness.selector;
        accessManager.setTargetFunctionRole(
            address(witness),
            selectors,
            relayerRole
        );
    }

    function testInitialized() public {
        vm.expectRevert();
        witness.initialize(address(accessManager));
    }

    function testAccessManager() public view {
        assertEq(address(witness.authority()), address(accessManager));
    }

    function testWitness(address relayer, bytes32 digest) public {
        accessManager.grantRole(relayerRole, relayer, 0);

        vm.expectEmit(true, false, false, false, address(witness));
        emit Witness.Witnessed(digest, uint48(block.timestamp));

        vm.prank(relayer);
        witness.witness(digest);

        assertEq(witness.witnessedAt(digest), uint48(block.timestamp));
        assertNotEq(uint48(block.timestamp), uint48(0)); // Sanity check

        accessManager.revokeRole(relayerRole, relayer);
    }

    function testFailWitness(address sender, bytes32 digest) public {
        vm.prank(sender);
        vm.expectRevert(
            abi.encodePacked(
                bytes4(keccak256("AccessManagedUnauthorized")),
                bytes32(bytes20(address(witness)))
            )
        );
        witness.witness(digest);
        assertEq(witness.witnessedAt(digest), uint32(0));
    }
}
