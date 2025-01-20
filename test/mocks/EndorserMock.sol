// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {MockWitnessConsumer} from "./MockWitnessConsumer.sol";
import {Proof} from "@WitnessCo/interfaces/IWitness.sol";
import {WitnessConsumer} from "@WitnessCo/WitnessConsumer.sol";
import {Endorser} from "~/Endorser.sol";

contract EndorserMock is MockWitnessConsumer, Endorser {
    function getProvenanceHash(
        bytes memory data
    ) public pure override(Endorser, MockWitnessConsumer) returns (bytes32) {
        return Endorser.getProvenanceHash(data);
    }

    function verifyProof(
        Proof calldata proof
    ) public view override(WitnessConsumer, MockWitnessConsumer) {
        MockWitnessConsumer.verifyProof(proof);
    }

    function safeVerifyProof(
        Proof calldata proof
    )
        public
        view
        override(WitnessConsumer, MockWitnessConsumer)
        returns (bool)
    {
        return MockWitnessConsumer.safeVerifyProof(proof);
    }

    function $_mint(address to, uint256 id) external virtual {
        _mint(to, id);
    }
}
