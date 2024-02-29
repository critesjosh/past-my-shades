# Can't see past my shades

A privacy suite of products built for the EVM.

- Private Fundraising
- Sealed bid auctions
- Private voting

This application is built on the [Bank of Jubjub private payments protocol](https://bankofjubjub.com).

## How it works

- An extension contract is deployed to an EVM blockchain. Users can use any ERC20 token with the bank of jubjub protocol, and by extension, any of these extensions.
- Users lock their bank of jubjub account to the extension contract
- Users can interact with the extension contract, defined by the logic specified in the specific extension contract

## Features

### Private Fundraising

- Raise money without revealing how much is raised
- Only collect funds from donees if the fundraiser threshold was reached
- Fund raise private amounts to accounts controlled by multisig accounts (e.g. Gnosis Safe)

#### Contracts

- [Fundraiser.sol](./packages/hardhat/contracts/extensions/Fundraiser.sol)

#### Circuits

- [`correct_addition`](./circuits/extensions/fundraiser/correct_addition/src/main.nr) - contributors use this circuit to enforce correctness of adding their encrypted contribution to the fundraiser
- [`correct_encrypted_zero`](./circuits/extensions/fundraiser/correct_zero/src/main.nr) - the fundraiser creator uses this to enforce correctness of setting the initial encrypted value (0) of the fundraiser
- [`met_threshold`](./circuits/extensions/fundraiser/met_threshold/src/main.nr) - the fundraiser manager uses this circuit to enforce correctness of checking if the fundraiser has met the threshold
- [`revoke_contribution`](./circuits/extensions/fundraiser/revoke_contribution/src/main.nr) - contributors use this circuit to revoke their contribution to the fundraiser

### Sealed bid auctions

- Bid on NFTs without revealing how much you bid
- Bids can be private, coming from the Bank of Jubjub protocol, or public coming from Arbitrum/Base or other blockchains

#### Contracts

- [Auction.sol](./packages/hardhat/contracts/extensions/Auction.sol)

#### Circuits

### Private voting

Vote on proposals without revealing how you voted. Votes are encrypted to a vote manager. The vote manager is responsible for processing the result of the vote when the voting period has ended. The vote manager account can be controlled by multiple parties or a multisig to reduce the risk of a griefing attack. Note that anyone with the vote manager private key will be able to decrypt the vote totals, but will not be able to alter the outcome of the vote.

`Vote` structs include a destination contract and bytecode to be executed when a vote is passed. This bytecode can include:

- instructions to a bridging protocol to execute code on other chains
- bidding on a private NFT auction (or any purchase/sale)
- sending funds to a private crowdfunding fundraiser
- transferring funds from a DAO treasury

#### Contracts

- [Voting.sol](./packages/hardhat/contracts/extensions/Voting.sol)

#### Circuits

- [`check_vote`](./circuits/extensions/private_voting/check_vote/src/main.nr)
  - checks that a vote has correctly encrypted yay and nay votes to the vote manager
  - checks that the vote has the corresponding private key. checks that
  - checks that the voter does not vote with more than their token balance
- [`process_votes`](./circuits/extensions/private_voting/process_votes/src/main.nr)
  - checks if yay or nay received more votes, without revealing the vote totals
  - valid proofs can only be generated by the vote manager
- [`correct_zero`](./circuits/extensions/fundraiser/correct_zero/src/main.nr)
  - checks that the initial encrypted 0 value is correct
  - same circuit as used in the fundraiser

![](./shades_noun.png)
