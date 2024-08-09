// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {IWitness, Proof} from "@WitnessCo/interfaces/IWitness.sol";
import {IWitnessConsumer} from "@WitnessCo/interfaces/IWitnessConsumer.sol";

/// General error for invalid proof.
error InvalidMockProof();

/// @title MockWitnessConsumer
/// @author sina.eth
/// @custom:coauthor runtheblocks.eth
/// @notice Test and prototyping utility for contracts that want to consume provenance.
/// @dev See IWitnessConsumer.sol for more information.
abstract contract MockWitnessConsumer is IWitnessConsumer {
    /*//////////////////////////////////////////////////////////////////////////
                                   PUBLIC STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Value to return from mock verify functions.
    bool public mockVal = true;

    /// @dev Function to set mockVal.
    function setMockVal(bool _mockVal) external {
        mockVal = _mockVal;
    }

    /// @inheritdoc IWitnessConsumer
    function getProvenanceHash(
        bytes memory data
    ) public pure virtual returns (bytes32) {
        return keccak256(data);
    }

    /// @inheritdoc IWitnessConsumer
    function verifyProof(Proof calldata) public view virtual {
        if (!mockVal) revert InvalidMockProof();
    }

    /// @inheritdoc IWitnessConsumer
    function safeVerifyProof(
        Proof calldata
    ) public view virtual returns (bool) {
        return mockVal;
    }
}
