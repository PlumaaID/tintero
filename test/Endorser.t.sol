// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BaseTest} from "./Base.t.sol";
import {Merkle} from "murky/Merkle.sol";
import {Witness} from "~/Witness.sol";
import {ICreateX} from "createx/ICreateX.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {console2} from "forge-std/console2.sol";

contract EndorserTest is BaseTest {
    function testInitialized() public {
        vm.expectRevert();
        endorser.initialize(address(accessManager), address(witness));
    }

    function testAccessManager() public view {
        assertEq(address(endorser.authority()), address(accessManager));
    }

    function testWitness() public view {
        assertEq(address(endorser.witness()), address(witness));
    }

    function testMint(address minter, address receiver, bytes32 digest) public {
        vm.assume(receiver.code.length == 0 && receiver != address(0));

        // Setup roles
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = Witness.witness.selector;
        accessManager.setTargetFunctionRole(
            address(witness),
            selectors,
            relayerRole
        );
        // So we can witness the merkle root
        accessManager.grantRole(relayerRole, address(this), 0);

        // The leaf is the receiver and the digest
        bytes32 leaf = keccak256(
            bytes.concat(keccak256(abi.encode(receiver, digest)))
        );

        // Initialize
        Merkle m = new Merkle();
        // Toy Data
        bytes32[] memory data = new bytes32[](4);
        data[0] = bytes32("0x00");
        data[1] = bytes32("0x01");
        data[2] = bytes32("0x02");
        // The leaf
        data[3] = leaf;

        bytes32 root = m.getRoot(data);
        bytes32[] memory proof = m.getProof(data, 3); // Proof for our leaf

        // Witness root
        witness.witness(root);

        // Mint
        vm.prank(minter);
        endorser.mint(receiver, digest, root, proof);
        assertEq(endorser.ownerOf(uint256(digest)), receiver);
        assertNotEq(block.timestamp, 0);
    }

    function testFailMint(
        address minter,
        address receiver,
        bytes32 digest,
        bytes32 root,
        bytes32[] memory proof
    ) public {
        vm.prank(minter);
        vm.expectRevert(bytes4(keccak256("InvalidProof")));
        endorser.mint(receiver, digest, root, proof);
    }

    function testFailApproval(address to, uint256 tokenId) public {
        vm.prank(endorser.ownerOf(tokenId));
        vm.expectRevert();
        endorser.approve(to, tokenId);
    }

    function testFailSetApprovalForAll(
        address approver,
        address operator,
        bool approved
    ) public {
        vm.prank(approver);
        vm.expectRevert(bytes4(keccak256("UnsupportedOperation")));
        endorser.setApprovalForAll(operator, approved);
    }
}
