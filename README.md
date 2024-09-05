# Plumaa ID | Protocol

<img src="./images/logo.png" width="150" alt="Plumaa ID">

Plumaa ID Protocol is a set of open-source smart contracts that enable organizations to comply with the requirements of data preservation and non-interrumpted chain of endorsements under Mexican commercial and debt instruments law.

The protocol includes one main component:

- Endorser: An ERC721 token that uses a document hash as a token id. The chain of endorsements is represented by the transfer of the token and each transfer complies with data preservation requirements with the block timestamp, and the chain of endorsements is obtained from the previous token holder.

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

## Roles

- UPGRADER: 4853719658622747636 (`uint64(bytes8(keccak256("PlumaaID.UPGRADER")))`)
- PROVENANCE_AUTHORIZER: 12236269664351332516 (`uint64(bytes8(keccak256("PlumaaID.PROVENANCE_AUTHORIZER")))`)
- WITNESS_SETTER: 5639234726794575539 (`uint64(bytes8(keccak256("PlumaaID.WITNESS_SETTER")))`)

### Role mapping

| Role           | Function signature                | Selector | Target contract                            |
| -------------- | --------------------------------- | -------- | ------------------------------------------ |
| UPGRADER       | `upgradeToAndCall(address,bytes)` | 4f1ef286 | 0x0000c908D1104caD2867Ec2A8Bb178D78C9bAaaa |
| WITNESS_SETTER | `setWitness(address)`             | 0bc14f8b | 0x0000c908D1104caD2867Ec2A8Bb178D78C9bAaaa |

### Role members

| Role                  | Address                                    | Execution Delay |
| --------------------- | ------------------------------------------ | --------------- |
| PROVENANCE_AUTHORIZER | 0xD4FAa2Bcdd1A438C9E69699166eDc92E65954ED7 | 0               |
| UPGRADER              | 0x00fA8957dC3D2f6081360056bf2f6d4b5f1a49aa | 259200 (3 days) |
| WITNESS_SETTER        | 0x00fA8957dC3D2f6081360056bf2f6d4b5f1a49aa | 0               |
