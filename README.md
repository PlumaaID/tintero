# Tintero | Protocol

<img src="./images/logo.png" width="200" alt="Tintero Protocol">

Tintero is an asset-backed security (ABS) lending protocol that provides liquidity in exchange for tokenized receivables (or any negotiable instrument). These negotiable instruments are represented as NFTs whose identifier is the hash of a document representing the underlying asset.

Investors can deposit their assets in a Tintero vault (e.g USDC) and receive shares in exchange. These shares are later allocated towards funding loans approved by a vault manager.

On the other side, asset originators can write loans, leases, or any other kind of Real World Asset (RWA) and tokenize them using [Plumaa ID](https://plumaa.id). These tokens are used as collateral to request a loan from a Tintero vault. If the manager approves the loan, the loan is funded and the principal is transferred to a beneficiary address.

Assets are represented through the Endorser contract, an ERC721 token that uses a document hash as a token id. It complies with data preservation requirements and a non-interrupted chain of endorsements under Mexican commercial and debt instruments law by indexing the chain of transfers (i.e. endorsements) whose signatures are non-repudiably linked to the user's address when transferring via Plumaa ID.

The content of documents remains private since the system only track hashes.

### Getting started

```
make
```

### Deployments

#### Endorser

| Network          | ChainID | Address                                    |
| ---------------- | ------- | ------------------------------------------ |
| Arbitrum         | 42161   | 0x0000c908D1104caD2867Ec2A8Bb178D78C9bAaaa |
| Arbitrum Sepolia | 421614  | 0x0000c908D1104caD2867Ec2A8Bb178D78C9bAaaa |

#### Access Manager

| Network          | ChainID | Address                                    |
| ---------------- | ------- | ------------------------------------------ |
| Arbitrum         | 42161   | 0x0000593Daa1e9E24FEe19AF6B258A268c97aAAAa |
| Arbitrum Sepolia | 421614  | 0x0000593Daa1e9E24FEe19AF6B258A268c97aAAAa |

#### Tintero Vaults

##### USDC

| Network          | ChainID | Address |
| ---------------- | ------- | ------- |
| Arbitrum         | 42161   | TBD     |
| Arbitrum Sepolia | 421614  | TBD     |

## Roles

- UPGRADER: 4853719658622747636 (`uint64(bytes8(keccak256("PlumaaID.UPGRADER")))`)
- PROVENANCE_AUTHORIZER: 12236269664351332516 (`uint64(bytes8(keccak256("PlumaaID.PROVENANCE_AUTHORIZER")))`)
- WITNESS_SETTER: 5639234726794575539 (`uint64(bytes8(keccak256("PlumaaID.WITNESS_SETTER")))`)
- TINTERO_MANAGER_USDC_V01: 4691003184040892619 (`uint64(bytes8(keccak256("PlumaaID.TINTERO_MANAGER_USDC_V01")))`)
- TINTERO_DELEGATE_USDC_V01: 13580011560138984285 (`uint64(bytes8(keccak256("PlumaaID.TINTERO_DELEGATE_USDC_V01")))`)
- TINTERO_INVESTOR_USDC_V01: 5277304099500357812 (`uint64(bytes8(keccak256("PlumaaID.TINTERO_INVESTOR_USDC_V01")))`)

### Role mapping

| Role                      | Function signature                                                               | Selector | Target contract                            |
| ------------------------- | -------------------------------------------------------------------------------- | -------- | ------------------------------------------ |
| UPGRADER                  | `upgradeToAndCall(address,bytes)`                                                | 4f1ef286 | 0x0000c908D1104caD2867Ec2A8Bb178D78C9bAaaa |
| WITNESS_SETTER            | `setWitness(address)`                                                            | 0bc14f8b | 0x0000c908D1104caD2867Ec2A8Bb178D78C9bAaaa |
| TINTERO_MANAGER_USDC_V01  | `pushPayments(address,uint256[],(uint256,uint48,uint32,uint32,uint32,uint32)[])` | 69b24c8a | TBD                                        |
| TINTERO_MANAGER_USDC_V01  | `pushTranches(address,uint96[],address[])`                                       | 1589cd5e | TBD                                        |
| TINTERO_MANAGER_USDC_V01  | `fundN(address,uint256)`                                                         | ae527b8a | TBD                                        |
| TINTERO_MANAGER_USDC_V01  | `repossess(address,uint256,uint256,address)`                                     | d3b500cf | TBD                                        |
| TINTERO_MANAGER_USDC_V01  | `upgradeLoan(address,uint256,uint256,address)`                                   | c3aacfe3 | TBD                                        |
| TINTERO_DELEGATE_USDC_V01 | `askDelegation(uint256)`                                                         | 30adbaff | TBD                                        |
| TINTERO_INVESTOR_USDC_V01 | `deposit(uint256,address)`                                                       | 6e553f65 | TBD                                        |
| TINTERO_INVESTOR_USDC_V01 | `mint(uint256,address)`                                                          | 94bf804d | TBD                                        |

### Role members

| Role                      | Address                                    | Execution Delay |
| ------------------------- | ------------------------------------------ | --------------- |
| PROVENANCE_AUTHORIZER     | 0xD4FAa2Bcdd1A438C9E69699166eDc92E65954ED7 | 0               |
| UPGRADER                  | 0x00fA8957dC3D2f6081360056bf2f6d4b5f1a49aa | 259200 (3 days) |
| WITNESS_SETTER            | 0x00fA8957dC3D2f6081360056bf2f6d4b5f1a49aa | 0               |
| TINTERO_MANAGER_USDC_V01  | TBD                                        | 0               |
| TINTERO_DELEGATE_USDC_V01 | TBD                                        | 32200 (12 hrs)  |
| TINTERO_INVESTOR_USDC_V01 | TBD                                        | 0               |
