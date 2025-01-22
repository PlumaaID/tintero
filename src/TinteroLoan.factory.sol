// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {AccessManaged} from "@openzeppelin/contracts/access/manager/AccessManaged.sol";

import {PaymentLib} from "./utils/PaymentLib.sol";
import {TinteroLoan} from "./TinteroLoan.sol";

abstract contract TinteroLoanFactory is AccessManaged {
    /// @dev Emitted when a Loan contract is created by this vault.
    event LoanCreated(address loan);

    using Create2 for *;

    address public immutable INITIAL_ERC721_COLLATERAL_LOAN_IMPLEMENTATION =
        address(new TinteroLoan());

    /// @dev Predict the address of a Loan contract using the provided parameters.
    function predictLoanAddress(
        address collateralCollection_,
        address beneficiary_,
        uint24 defaultThreshold_,
        bytes32 salt,
        address caller_
    )
        public
        view
        returns (address loan, bytes memory bytecode, bytes32 bytecodeHash)
    {
        bytecode = _loanProxyBytecode(
            collateralCollection_,
            beneficiary_,
            defaultThreshold_
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
        address collateralCollection_,
        address beneficiary_,
        uint24 defaultThreshold_,
        bytes32 salt
    ) internal returns (address loan) {
        (address predicted, bytes memory bytecode, ) = predictLoanAddress(
            collateralCollection_,
            beneficiary_,
            defaultThreshold_,
            salt,
            msg.sender
        );

        if (predicted.code.length == 0) {
            Create2.deploy(0, _salt(salt, msg.sender), bytecode);
            emit LoanCreated(predicted);
        }

        return predicted;
    }

    /// @dev Returns the bytecode to be used when deploying a new Loan contract.
    function _loanProxyBytecode(
        address collateralCollection_,
        address beneficiary_,
        uint24 defaultThreshold_
    ) internal view returns (bytes memory) {
        return
            bytes.concat(
                type(ERC1967Proxy).creationCode,
                abi.encode(
                    INITIAL_ERC721_COLLATERAL_LOAN_IMPLEMENTATION,
                    abi.encodeCall(
                        TinteroLoan.initialize,
                        (
                            address(this),
                            collateralCollection_,
                            beneficiary_,
                            defaultThreshold_
                        )
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
