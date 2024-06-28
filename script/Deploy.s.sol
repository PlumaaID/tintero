// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {console2} from "forge-std/console2.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {BaseScript} from "./utils/Base.s.sol";
import {ICreateX} from "createx/ICreateX.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Witness} from "~/Witness.sol";
import {Endorser} from "~/Endorser.sol";

/// @dev See the Solidity Scripting tutorial: https://book.getfoundry.sh/tutorials/solidity-scripting
contract Deploy is BaseScript {
    address constant PLUMAA_DEPLOYER_EOA =
        0x171cE5a35e417F90B2D73858e0dedA632146A603;
    address constant PLUMAA_MULTISIG =
        0x00fA8957dC3D2f6081360056bf2f6d4b5f1a49aa;
    address constant CREATE_X = 0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed;
    ICreateX public createX;

    function setUp() public {
        createX = ICreateX(CREATE_X);
    }

    function run() public broadcast {
        address manager = _deployManager();
        address witness = _deployWitness(manager);
        _deployEndorser(manager, witness);
    }

    function _deployManager() internal returns (address) {
        address manager = createX.deployCreate2(
            _toSalt(0x6b43bfc879a9fa03533daf),
            abi.encodePacked(
                type(AccessManager).creationCode,
                abi.encode(PLUMAA_MULTISIG)
            )
        );
        console2.log("AccessManager contract deployed to %s", address(manager));
        assert(0x00Ea868de72CCaaF5fA05CAA80812dFcF9A531aA == manager);
        return manager;
    }

    function _deployWitness(address manager) internal returns (address) {
        address witnessImplementation = createX.deployCreate2(
            _toSalt(0xc667d3139828fd030a37e0),
            type(Witness).creationCode
        );
        address witnessProxy = createX.deployCreate2(
            _toSalt(0x73c40bb27a35f5034e2e41),
            abi.encodePacked(
                type(ERC1967Proxy).creationCode,
                abi.encode(
                    witnessImplementation,
                    abi.encodeCall(Witness.initialize, (manager))
                )
            )
        );
        console2.log("Witness contract deployed to %s", address(witnessProxy));
        assert(0x0022D40927C0E9561ac4D1Cf919115BBC3AadaAa == witnessProxy);
        return witnessProxy;
    }

    function _deployEndorser(
        address manager,
        address witness
    ) internal returns (address) {
        address endorserImplementation = createX.deployCreate2(
            _toSalt(0x9fe08fa42678fd03141080),
            type(Endorser).creationCode
        );
        address endorserProxy = createX.deployCreate2(
            _toSalt(0xd0cf5ad7789bf503cee991),
            abi.encodePacked(
                type(ERC1967Proxy).creationCode,
                abi.encode(
                    endorserImplementation,
                    abi.encodeCall(Endorser.initialize, (manager, witness))
                )
            )
        );
        console2.log(
            "Endorser contract deployed to %s",
            address(endorserProxy)
        );
        assert(0x004F084FD7180Cf971dC7A406073716880335aAa == endorserProxy);
        return endorserProxy;
    }

    function _toSalt(bytes11 mined) internal pure returns (bytes32) {
        return
            (bytes32(mined) >> 168) |
            (bytes32(0x00) >> 160) | // No cross-chain redeployment protection
            bytes32(bytes20(PLUMAA_DEPLOYER_EOA));
    }
}
