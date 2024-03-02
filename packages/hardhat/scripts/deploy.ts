import hre from "hardhat";
import dotenv from "dotenv";
import { readDeploymentData, saveDeploymentData } from "./saveDeploy.js";
import { delay } from "boj-utils";
import { hardhat, sepolia, arbitrumSepolia, baseSepolia } from "viem/chains";
import { createPublicClient, createWalletClient, http } from "viem";
import { privateKeyToAccount } from 'viem/accounts'
dotenv.config({ path: "../.env" });

export async function deployContracts(chain: any, isTest: boolean = false) {
  // const [deployer] = await hre.viem.getWalletClients();
  // const publicClient = await hre.viem.getPublicClient();

  // const deployer = await createWalletClient({
  //   chain,
  //   transport: http(),
  //   account: privateKeyToAccount(process.env.PRIVATE_KEY as `0x${string}`).address
  // })

  // const publicClient = createPublicClient({
  //   chain: chain,
  //   transport: http()
  // })

  // console.log(
  //   "Deploying contracts with the account:",
  //   deployer.account
  // );

  try {
    const token = await deployAndSave("FunToken", [], chain, isTest);

    const pendingDepositVerifier = await deployAndSave(
      "contracts/process_pending_deposits/plonk_vk.sol:UltraVerifier",
      [], chain,
      isTest
    );

    const pendingTransferVerifier = await deployAndSave(
      "contracts/process_pending_transfers/plonk_vk.sol:UltraVerifier",
      [], chain,
      isTest
    );

    const transferVerifier = await deployAndSave(
      "contracts/transfer/plonk_vk.sol:UltraVerifier",
      [], chain,
      isTest
    );

    const withdrawVerifier = await deployAndSave(
      "contracts/withdraw/plonk_vk.sol:UltraVerifier",
      [], chain,
      isTest
    );

    const lockVerifier = await deployAndSave(
      "contracts/lock/plonk_vk.sol:UltraVerifier",
      [], chain,
      isTest
    );

    const addEthSigners = await deployAndSave(
      "contracts/add_eth_signer/plonk_vk.sol:UltraVerifier",
      [], chain,
      isTest
    );

    const accountController = await deployAndSave(
      "AccountController",
      [addEthSigners.address], chain,
      isTest
    );

    const allTransferVerifier = await deployAndSave(
      "TransferVerify",
      [transferVerifier.address], chain,
      isTest
    );

    const allWithdrawVerifier = await deployAndSave(
      "WithdrawVerify",
      [withdrawVerifier.address], chain,
      isTest
    );

    // const decimals = await publicClient.readContract({
    //   abi: token.abi,
    //   // @ts-ignore
    //   address: token.address,
    //   functionName: 'decimals'
    // })
    const decimals = 18;

    const privateToken = await deployAndSave(
      "PrivateToken",
      [
        pendingDepositVerifier.address,
        pendingTransferVerifier.address,
        allTransferVerifier.address,
        allWithdrawVerifier.address,
        lockVerifier.address,
        token.address,
        decimals,
        accountController.address
      ], chain,
      isTest
    );

    /*
    
    Fundraiser deployments
    
    */

    const additionVerifier = await deployAndSave(
      "contracts/correct_addition/plonk_vk.sol:UltraVerifier",
      [], chain,
      isTest
    )

    const thresholdVerifier = await deployAndSave(
      "contracts/met_threshold/plonk_vk.sol:UltraVerifier",
      [], chain, isTest
    )

    const zeroVerifier = await deployAndSave(
      "contracts/correct_zero/plonk_vk.sol:UltraVerifier",
      [], chain, isTest
    )

    const revokeVerifier = await deployAndSave(
      "contracts/revoke_contribution/plonk_vk.sol:UltraVerifier",
      [], chain, isTest
    )

    const fundraiser = await deployAndSave(
      "Fundraiser",
      [
        privateToken.address,
        transferVerifier.address,
        additionVerifier.address,
        thresholdVerifier.address,
        zeroVerifier.address,
        accountController.address,
        revokeVerifier.address
      ], chain,
      isTest
    )

    /*
    
      Auction deployments

    */

    const bidConsolidationVerifier = await deployAndSave(
      "contracts/consolidate_bids/plonk_vk.sol:UltraVerifier",
      [], chain, isTest
    )

    const auctionSettlementVerifier = await deployAndSave(
      "contracts/private_bid_greater/plonk_vk.sol:UltraVerifier",
      [], chain, isTest
    )

    const ownerVerifier = await deployAndSave(
      "contracts/check_owner/plonk_vk.sol:UltraVerifier",
      [], chain, isTest
    )

    const auction = await deployAndSave(
      "Auction",
      [
        privateToken.address,
        transferVerifier.address,
        accountController.address,
        bidConsolidationVerifier.address,
        auctionSettlementVerifier.address,
        ownerVerifier.address
      ], chain, isTest
    )

    /*

      Voting deployments

    */


    const voteVerifier = await deployAndSave(
      "contracts/check_vote/plonk_vk.sol:UltraVerifier",
      [], chain, isTest
    )

    const processVoteVerifier = await deployAndSave(
      "contracts/process_votes/plonk_vk.sol:UltraVerifier",
      [], chain, isTest
    )

    const voting = await deployAndSave(
      "Voting",
      [
        privateToken.address,
        zeroVerifier.address,
        accountController.address,
        voteVerifier.address,
        processVoteVerifier.address
      ], chain, isTest
    )

    console.log(
      "Deployment succeeded. Private token contract at: ",
      privateToken.address
    );
    return {
      privateToken,
      token,
      accountController,
      fundraiser,
      auction,
      voting
    };
  } catch (e) {
    console.log(e);
  }
}

async function deployAndSave(
  name: string,
  constructorArgs: any[],
  chain: any,
  isTest: boolean = false
) {

  // let account = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266" as `0x${string}`
  // if (chain.name !== "Hardhat") {
  //   let viemAccount = privateKeyToAccount(process.env.PRIVATE_KEY as `0x${string}`)
  //   account = viemAccount.address
  // }

  let account = privateKeyToAccount(process.env.PRIVATE_KEY as `0x${string}`)
  if (chain.name == "Hardhat") {
    account = privateKeyToAccount("0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80")
  }


  const deployer = await createWalletClient({
    chain,
    transport: http(),
    account
  })

  const publicClient = createPublicClient({
    chain,
    transport: http()
  })

  let contractName = name;
  if (name.startsWith("contracts/")) {
    const regex = /\/([^\/]+)\//;
    contractName = name.match(regex)![1];
  }
  const { data } = readDeploymentData(contractName);

  let artifact = await hre.artifacts.readArtifact(name);

  let networkName = chain.name.toLowerCase()
  // If the saved bytecode matches the current, don't deploy, just return
  if (
    networkName != "hardhat" &&
    data[networkName] &&
    data[networkName].bytecode == artifact.bytecode &&
    !isTest
  ) {
    console.log(`${name} contract found, skipping deployment.`);
    return await hre.viem.getContractAt(name, data[hre.network.name].address);
  }

  const hash = await deployer.deployContract({
    abi: artifact.abi,
    account,
    args: constructorArgs,
    bytecode: artifact.bytecode as `0x${string}`,
    chain
  });

  if (!isTest) {
    await delay(40000);
  }

  const receipt = await publicClient.getTransactionReceipt({ hash });

  console.log(`${name} contract deployed`);

  saveDeploymentData(contractName, {
    address: receipt.contractAddress as `0x${string}`,
    abi: artifact.abi,
    network: hre.network.name,
    chainId: hre.network.config.chainId,
    bytecode: artifact.bytecode,
    receipt,
  });

  return await hre.viem.getContractAt(name, receipt.contractAddress!);
}

deployContracts(baseSepolia, false);