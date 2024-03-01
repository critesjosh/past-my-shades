import hre from "hardhat";
import dotenv from "dotenv";
import { readDeploymentData, saveDeploymentData } from "./saveDeploy.js";
import { delay } from "boj-utils";
import { hardhat } from "viem/chains";
import { createPublicClient, createWalletClient, http } from "viem";
dotenv.config({ path: "../.env" });

export async function deployContracts(isTest: boolean = false) {
  // const [deployer] = await hre.viem.getWalletClients();
  // const publicClient = await hre.viem.getPublicClient();

  // const deployer = await createWalletClient({
  //   chain: hardhat,
  //   transport: http(),
  //   account: '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266'
  // })

  const publicClient = createPublicClient({
    chain: hardhat,
    transport: http()
  })

  // console.log(
  //   "Deploying contracts with the account:",
  //   deployer.account
  // );

  try {
    const token = await deployAndSave("FunToken", [], isTest);

    const pendingDepositVerifier = await deployAndSave(
      "contracts/process_pending_deposits/plonk_vk.sol:UltraVerifier",
      [],
      isTest
    );

    const pendingTransferVerifier = await deployAndSave(
      "contracts/process_pending_transfers/plonk_vk.sol:UltraVerifier",
      [],
      isTest
    );

    const transferVerifier = await deployAndSave(
      "contracts/transfer/plonk_vk.sol:UltraVerifier",
      [],
      isTest
    );

    const withdrawVerifier = await deployAndSave(
      "contracts/withdraw/plonk_vk.sol:UltraVerifier",
      [],
      isTest
    );

    const lockVerifier = await deployAndSave(
      "contracts/lock/plonk_vk.sol:UltraVerifier",
      [],
      isTest
    );

    const addEthSigners = await deployAndSave(
      "contracts/add_eth_signer/plonk_vk.sol:UltraVerifier",
      [],
      isTest
    );

    const accountController = await deployAndSave(
      "AccountController",
      [addEthSigners.address],
      isTest
    );

    const allTransferVerifier = await deployAndSave(
      "TransferVerify",
      [transferVerifier.address],
      isTest
    );

    const allWithdrawVerifier = await deployAndSave(
      "WithdrawVerify",
      [withdrawVerifier.address],
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
      ],
      isTest
    );

    /*
    
    Fundraiser deployments
    
    */

    const additionVerifier = await deployAndSave(
      "contracts/correct_addition/plonk_vk.sol:UltraVerifier",
      [],
      isTest
    )

    const thresholdVerifier = await deployAndSave(
      "contracts/met_threshold/plonk_vk.sol:UltraVerifier",
      [], isTest
    )

    const zeroVerifier = await deployAndSave(
      "contracts/correct_zero/plonk_vk.sol:UltraVerifier",
      [], isTest
    )

    const revokeVerifier = await deployAndSave(
      "contracts/revoke_contribution/plonk_vk.sol:UltraVerifier",
      [], isTest
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
      ],
      isTest
    )

    /*
    
      Auction deployments

    */

    const bidConsolidationVerifier = await deployAndSave(
      "contracts/consolidate_bids/plonk_vk.sol:UltraVerifier",
      [], isTest
    )

    const auctionSettlementVerifier = await deployAndSave(
      "contracts/private_bid_greater/plonk_vk.sol:UltraVerifier",
      [], isTest
    )

    const ownerVerifier = await deployAndSave(
      "contracts/check_owner/plonk_vk.sol:UltraVerifier",
      [], isTest
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
      ]
    )

    /*

      Voting deployments

    */





    console.log(
      "Deployment succeeded. Private token contract at: ",
      privateToken.address
    );
    return {
      privateToken,
      token,
      accountController,
      fundraiser
    };
  } catch (e) {
    console.log(e);
  }
}

async function deployAndSave(
  name: string,
  constructorArgs: any[],
  isTest: boolean = false
) {
  // const publicClient = await hre.viem.getPublicClient();
  // const [deployer] = await hre.viem.getWalletClients();

  const deployer = await createWalletClient({
    chain: hardhat,
    transport: http(),
    account: '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266'
  })

  const publicClient = createPublicClient({
    chain: hardhat,
    transport: http()
  })

  let contractName = name;
  if (name.startsWith("contracts/")) {
    const regex = /\/([^\/]+)\//;
    contractName = name.match(regex)![1];
  }
  const { data } = readDeploymentData(contractName);

  let artifact = await hre.artifacts.readArtifact(name);

  // If the saved bytecode matches the current, don't deploy, just return
  if (
    // hre.network.name != "hardhat" &&
    data[hre.network.name] &&
    data[hre.network.name].bytecode == artifact.bytecode &&
    !isTest
  ) {
    console.log(`${name} contract found, skipping deployment.`);
    return await hre.viem.getContractAt(name, data[hre.network.name].address);
  }

  const hash = await deployer.deployContract({
    abi: artifact.abi,
    account: (await deployer.getAddresses())[0],
    args: constructorArgs,
    bytecode: artifact.bytecode as `0x${string}`,
  });

  const receipt = await publicClient.getTransactionReceipt({ hash });

  console.log(`${name} contract deployed`);

  if (!isTest) {
    await delay(20000);
  }

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

deployContracts(true);