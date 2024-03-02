# Can't see past my shades

A privacy suite of products built for the EVM.

- Private Fundraising
- Sealed bid auctions
- Private voting

Leverages zk-snarks written in [Noir](https://noir-lang.org) and [this nifty El Gamal library](https://github.com/jat9292/noir-elgamal) for homomorphic addition.

This application is built on the [Bank of Jubjub private payments protocol](https://bankofjubjub.com).

## How it works

- An private app contract is deployed to an EVM blockchain. Users can use any ERC20 token with the bank of jubjub protocol, and by extension, any of these private app contracts.
- Users lock their bank of jubjub account to the private app contract
- Users can interact with the private app contract, defined by the logic specified in the specific private app contract (vote, contribute, bid)
- Once the vote/contribution/bidding period has ended or the user removed themselves from participation, they can unlock their bank of jubjub account from the private application contract

## Features

### Private Fundraising

- Raise money without revealing how much is raised
- Only collect funds from donees if the fundraiser threshold was reached
- Fund raise private amounts to accounts controlled by multisig accounts (e.g. Gnosis Safe)

#### Contracts

- [Fundraiser.sol](./packages/hardhat/contracts/pacs/Fundraiser.sol)

#### Circuits

- [`correct_addition`](./circuits/pacs/fundraiser/correct_addition/src/main.nr) - contributors use this circuit to enforce correctness of adding their encrypted contribution to the fundraiser
- [`correct_encrypted_zero`](./circuits/pacs/fundraiser/correct_zero/src/main.nr) - the fundraiser creator uses this to enforce correctness of setting the initial encrypted value (0) of the fundraiser
- [`met_threshold`](./circuits/pacs/fundraiser/met_threshold/src/main.nr) - the fundraiser manager uses this circuit to enforce correctness of checking if the fundraiser has met the threshold
- [`revoke_contribution`](./circuits/pacs/fundraiser/revoke_contribution/src/main.nr) - contributors use this circuit to revoke their contribution to the fundraiser

### Sealed bid auctions

- Bid on NFTs without revealing how much you bid
- Bids can be private, coming from the Bank of Jubjub protocol, or public coming from Arbitrum/Base or other blockchains

#### Contracts

- [Auction.sol](./packages/hardhat/contracts/pacs/Auction.sol)

#### Circuits

- [`consolidate_bids`](./circuits/pacs/auction/consolidate_bids/src/main.nr)
  - used by the auction manager to reduce the list of private bids to the single, highest bid
- [`private_bid_greater`](./circuits/pacs/auction/private_bid_greater/src/main.nr)
  - used by the auction manager to indicate whether the top private bid or top public bid is higher without revealing the value of the top private bid

### Private voting

Vote on proposals without revealing how you voted. Votes are encrypted to a vote manager. The vote manager is responsible for processing the result of the vote when the voting period has ended. The vote manager account can be controlled by multiple parties or a multisig to reduce the risk of a griefing attack. Note that anyone with the vote manager private key will be able to decrypt the vote totals, but will not be able to alter the outcome of the vote.

`Vote` structs include a destination contract and bytecode to be executed when a vote is passed. This bytecode can include:

- instructions to a bridging protocol to execute code on other chains
- bidding on a private NFT auction (or any purchase/sale)
- sending funds to a private crowdfunding fundraiser
- transferring funds from a DAO treasury

#### Contracts

- [Voting.sol](./packages/hardhat/contracts/pacs/Voting.sol)

#### Circuits

- [`check_vote`](./circuits/pacs/private_voting/check_vote/src/main.nr)
  - checks that a vote has correctly encrypted yay and nay votes to the vote manager
  - checks that the vote has the corresponding private key. checks that
  - checks that the voter does not vote with more than their token balance
- [`process_votes`](./circuits/pacs/private_voting/process_votes/src/main.nr)
  - checks if yay or nay received more votes, without revealing the vote totals
  - valid proofs can only be generated by the vote manager
- [`correct_zero`](./circuits/pacs/fundraiser/correct_zero/src/main.nr)
  - checks that the initial encrypted 0 value is correct
  - same circuit as used in the fundraiser

## Deployments

### Sepolia

https://sepolia.etherscan.io/address/0x353654e70272693bf8916372b4e7cf3dccacde9f

### Arbitrum Sepolia

https://sepolia.arbiscan.io/address/0x353654e70272693bf8916372b4e7cf3dccacde9f

### Base Sepolia

https://sepolia.basescan.org/address/0x353654e70272693bf8916372b4e7cf3dccacde9f

![](./shades_noun.png)
