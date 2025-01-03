// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {AccessManaged} from "@openzeppelin/contracts/access/manager/AccessManaged.sol";

import {PaymentLib} from "./utils/PaymentLib.sol";
import {TinteroLoan} from "./TinteroLoan.sol";

abstract contract TinteroLoanFactory is AccessManaged {
    using Create2 for *;

    address public immutable INITIAL_ERC721_COLLATERAL_LOAN_IMPLEMENTATION =
        address(new TinteroLoan());

    /// @dev Predict the address of a Loan contract using the provided parameters.
    function predictLoanAddress(
        bytes32 salt,
        address collateralCollection_,
        address beneficiary_,
        uint16 defaultThreshold_,
        PaymentLib.Payment[] calldata payments_,
        uint256[] calldata collateralTokenIds_,
        address caller_
    )
        public
        view
        returns (address loan, bytes memory bytecode, bytes32 bytecodeHash)
    {
        bytecode = _loanProxyBytecode(
            collateralCollection_,
            beneficiary_,
            defaultThreshold_,
            payments_,
            collateralTokenIds_
        );
        bytecodeHash = keccak256(bytecode);
        return (
            _salt(salt, caller_).computeAddress(bytecodeHash, address(this)),
            bytecode,
            bytecodeHash
        );
    }

    /// @dev Deploy a new Loan contract using the provided parameters.
    function _deployLoan(
        bytes32 salt,
        address collateralCollection_,
        address beneficiary_,
        uint16 defaultThreshold_,
        PaymentLib.Payment[] calldata payments_,
        uint256[] calldata collateralTokenIds_
    ) internal returns (address loan) {
        salt = _salt(salt, msg.sender);
        (address predicted, bytes memory bytecode, ) = predictLoanAddress(
            salt,
            collateralCollection_,
            beneficiary_,
            defaultThreshold_,
            payments_,
            collateralTokenIds_,
            msg.sender
        );

        if (predicted.code.length == 0) Create2.deploy(0, salt, bytecode);
        return predicted;
    }

    /// @dev Returns the bytecode to be used when deploying a new Loan contract.
    function _loanProxyBytecode(
        address collateralCollection_,
        address beneficiary_,
        uint16 defaultThreshold_,
        PaymentLib.Payment[] calldata payments_,
        uint256[] calldata collateralTokenIds_
    ) internal view returns (bytes memory) {
        return
            abi.encode(
                type(ERC1967Proxy).creationCode,
                INITIAL_ERC721_COLLATERAL_LOAN_IMPLEMENTATION,
                abi.encodeCall(
                    TinteroLoan.initialize,
                    (
                        authority(),
                        address(this),
                        collateralCollection_,
                        beneficiary_,
                        defaultThreshold_,
                        payments_,
                        collateralTokenIds_
                    )
                )
            );
    }

    /// @dev Implementation of keccak256(abi.encode(a, b)) that doesn't allocate or expand memory.
    function _salt(
        bytes32 salt,
        address caller_
    ) internal pure returns (bytes32 value) {
        assembly ("memory-safe") {
            mstore(0x00, salt)
            mstore(0x20, caller_)
            value := keccak256(0x00, 0x40)
        }
    }
}
