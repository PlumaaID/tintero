// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BaseTest} from "./Base.t.sol";
import {ICreateX} from "createx/ICreateX.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {IWitness, Proof} from "@WitnessCo/interfaces/IWitness.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

import {console2} from "forge-std/console2.sol";

contract EndorserTest is BaseTest {
    function testInitialized() public {
        vm.expectRevert();
        endorser.initialize(address(accessManager), WITNESS);
    }

    function testAccessManager() public view {
        assertEq(address(endorser.authority()), address(accessManager));
    }

    function testWitness() public view {
        assertEq(address(endorser.WITNESS()), address(WITNESS));
    }

    function testMint(address minter, address receiver, bytes32 digest) public {
        vm.assume(receiver.code.length == 0 && receiver != address(0));

        // The leaf is the receiver and the digest concatenated
        bytes32 leaf = sha256(abi.encode(receiver, digest));

        // Create an authorization signature
        (address authorizer, uint256 authorizerPk) = makeAddrAndKey(
            "authorizer"
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            authorizerPk,
            MessageHashUtils.toEthSignedMessageHash(leaf)
        );
        bytes memory authorizationSignature = abi.encodePacked(r, s, v);
        accessManager.grantRole(PROVENANCE_AUTHORIZER_ROLE, authorizer, 0);

        vm.warp(block.timestamp + 1); // Make the role to go in effect

        // Mint
        vm.prank(minter);
        endorser.setMockVal(true);
        endorser.mint(
            receiver,
            digest,
            Proof({
                index: uint256(0),
                leaf: leaf,
                leftRange: new bytes32[](0),
                rightRange: new bytes32[](0),
                targetRoot: bytes32(0)
            }),
            authorizer,
            authorizationSignature
        );
        assertEq(endorser.ownerOf(uint256(digest)), receiver);
        assertNotEq(block.timestamp, 0);

        // Can't mint the same digest again
        vm.prank(minter);
        vm.expectRevert();
        endorser.mint(
            receiver,
            digest,
            Proof({
                index: uint256(0),
                leaf: leaf,
                leftRange: new bytes32[](0),
                rightRange: new bytes32[](0),
                targetRoot: bytes32(0)
            }),
            authorizer,
            authorizationSignature
        );
    }

    function testFailMint(
        address minter,
        address receiver,
        bytes32 digest,
        Proof calldata proof
    ) public {
        vm.prank(minter);
        vm.expectRevert(bytes4(keccak256("InvalidProof")));
        endorser.mint(receiver, digest, proof, address(0), "");
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
