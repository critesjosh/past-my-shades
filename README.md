# PGP-(F)

Pretty Good Private Fundraising.

This application is built on the [Bank of Jubjub private payments protocol](https://bankofjubjub.com).

## Features

- Raise money without revealing how much is raised
- Only collect funds from donees if the fundraiser threshold was reached
- Fund raise private amounts to accounts controlled by multisig accounts (e.g. Gnosis Safe)

## How it works

- A fundraiser contract is deployed to an EVM blockchain that has the Bank of Jubjub protocol
- Someone that wants to run a fundraiser registers a new fundraiser campaign with the contract
- Users lock their bank of jubjub account to the fundraiser contract
- Users deposit funds to the fundraiser contract from their bank of jubjub account. The amount sent to the fundraiser is encrypted

![](./gnu_sunglasses.png)
