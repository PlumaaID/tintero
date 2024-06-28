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
        0x00560ED8242bF346c162c668487BaCD86cc0B8aa;
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
        bytes memory code = abi.encodePacked(
            type(AccessManager).creationCode,
            abi.encode(PLUMAA_MULTISIG)
        );
        address manager = createX.deployCreate2(
            _toSalt(0xe1ea5c2e4c0ffd03f833b9),
            code
        );
        console2.log("AccessManager contract deployed to %s", address(manager));
        assert(0x000fcD69be90B1ABCAfC40D47Ba3f4eE628725Aa == manager);
        return manager;
    }

    function _deployWitness(address manager) internal returns (address) {
        address witnessImplementation = createX.deployCreate2(
            _toSalt(0x6f8bc95241def903fa0443),
            type(Witness).creationCode
        );
        bytes memory code = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(
                witnessImplementation,
                abi.encodeCall(Witness.initialize, (manager))
            )
        );
        address witnessProxy = createX.deployCreate2(
            _toSalt(0x2c6828624659e7039fb979),
            code
        );
        console2.log("Witness contract deployed to %s", address(witnessProxy));
        assert(0x00EcA6DC15966C282CF3aD953E559BC2d098D6aA == witnessProxy);
        return witnessProxy;
    }

    function _deployEndorser(
        address manager,
        address witness
    ) internal returns (address) {
        address endorserImplementation = createX.deployCreate2(
            _toSalt(0xdd461e9125fceb0358adb7),
            type(Endorser).creationCode
        );
        bytes memory code = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(
                endorserImplementation,
                abi.encodeCall(Endorser.initialize, (manager, witness))
            )
        );
        address endorserProxy = createX.deployCreate2(
            _toSalt(0xe7c84f9cd4d6eb037d8152),
            code
        );
        console2.log(
            "Endorser contract deployed to %s",
            address(endorserProxy)
        );
        assert(0x00956D2036740590C6752dC7CA3960A11aBeD1aa == endorserProxy);
        return endorserProxy;
    }

    function _toSalt(bytes11 mined) internal pure returns (bytes32) {
        return
            (bytes32(mined) >> 168) |
            (bytes32(0x00) >> 160) | // No cross-chain redeployment protection
            bytes32(bytes20(PLUMAA_DEPLOYER_EOA));
    }
}
