# Plumaa ID | Protocol

<img src="./images/logo.png" width="150" alt="Plumaa ID">

Plumaa ID Protocol is a set of open-source smart contracts that enable organizations to comply with the requirements of data preservation and non-interrumpted chain of endorsements under Mexican commercial and debt instruments law.

The protocol includes two main components:

- Witness: A smart contract that witnesses `bytes32` hashes of documents to guarantee data preservation. A witness entry is similar to a NOM-151.
- Endorser: An ERC721 token that uses a document hash as a token id. The chain of endorsements is represented by the transfer of the token and each transfer complies with data preservation requirements with the block timestamp, and the chain of endorsements is obtained from the previous token holder.

The content of documents remains private since the system only track hashes.

### Getting started

```
make
```
