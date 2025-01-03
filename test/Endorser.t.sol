// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BaseTest} from "./Base.t.sol";
import {ICreateX} from "createx/ICreateX.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {IWitness, Proof} from "@WitnessCo/interfaces/IWitness.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {Endorser} from "~/Endorser.sol";

contract EndorserTest is BaseTest {
    bytes32 internal constant _MINT_AUTHORIZATION_TYPEHASH =
        keccak256("MintRequest(bytes32 leaf,address to)");

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

    function testMintRequest(
        bytes32 leaf,
        address to,
        address minter,
        string memory authorizerSeed
    ) public {
        vm.assume(to.code.length == 0 && to != address(0));

        // Create a mint request with authorization signature
        (address authorizer, uint256 authorizerPk) = makeAddrAndKey(
            authorizerSeed
        );
        accessManager.grantRole(PROVENANCE_AUTHORIZER_ROLE, authorizer, 0);
        Endorser.MintRequestData memory mintRequest = Endorser.MintRequestData({
            authorizer: authorizer,
            to: to,
            signature: _getAuthorizationSignature(authorizerPk, leaf, to)
        });

        // Mock a Witness proof
        Proof memory mockProof = Proof({
            index: uint256(0),
            leaf: leaf,
            leftRange: new bytes32[](0),
            rightRange: new bytes32[](0),
            targetRoot: bytes32(0)
        });

        // Mint
        vm.prank(minter);
        endorser.setMockVal(true);
        endorser.mint(mintRequest, mockProof);
        assertEq(endorser.ownerOf(uint256(leaf)), mintRequest.to);
        assertNotEq(block.timestamp, 0);

        // Can't mint the same leaf again
        vm.prank(minter);
        vm.expectRevert();
        endorser.mint(mintRequest, mockProof);
    }

    function testFailMintRequest(
        address minter,
        Endorser.MintRequestData calldata mintRequest,
        Proof calldata proof
    ) public {
        vm.prank(minter);
        vm.expectRevert(bytes4(keccak256("InvalidProof")));
        endorser.mint(mintRequest, proof);
    }

    function testSetWitness(IWitness newWitness, address setter) public {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = Endorser.setWitness.selector;
        accessManager.setTargetFunctionRole(
            address(endorser),
            selectors,
            WITNESS_SETTER_ROLE
        );
        accessManager.grantRole(WITNESS_SETTER_ROLE, setter, 0);
        vm.prank(setter);
        endorser.setWitness(newWitness);
        assertEq(address(endorser.WITNESS()), address(newWitness));
    }

    function _getAuthorizationSignature(
        uint256 authorizerPk,
        bytes32 leaf,
        address to
    ) private view returns (bytes memory) {
        bytes32 structHash = keccak256(
            abi.encode(_MINT_AUTHORIZATION_TYPEHASH, leaf, to)
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            authorizerPk,
            keccak256(
                abi.encodePacked("\x19\x01", _getDomainSeparator(), structHash)
            )
        );

        return abi.encodePacked(r, s, v);
    }

    function _getDomainSeparator() private view returns (bytes32) {
        (
            ,
            string memory name,
            string memory version,
            uint256 chainId,
            address verifyingContract,
            ,

        ) = endorser.eip712Domain();
        return
            keccak256(
                abi.encode(
                    keccak256(
                        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                    ),
                    keccak256(bytes(name)),
                    keccak256(bytes(version)),
                    chainId,
                    verifyingContract
                )
            );
    }
}
