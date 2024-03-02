import dotenv from "dotenv";
dotenv.config({ path: "../.env" });
import hre from "hardhat";
import { readDeploymentData } from "./saveDeploy.js";
import { createPublicClient, getContract, http } from 'viem'
import { sepolia } from "viem/chains";

const params = {
  account: {
    packedPublicKey: process.env.BOJ_PACKED_PUBLIC_KEY as `0x${string}`,
    privateKey: process.env.BOJ_PRIVATE_KEY as `0x${string}`,
  },
};

async function main() {
  const chain = sepolia

  const publicClient = createPublicClient({
    chain,
    transport: http()
  })

  // const getContractAt = hre.viem.getContractAt
  const { data: privateTokenData } = readDeploymentData("PrivateToken");
  const { data: transferVerifyData } = readDeploymentData("TransferVerify");
  const { data: withdrawVerifyData } = readDeploymentData("WithdrawVerify");
  const { data: lockData } = readDeploymentData("contracts/lock/plonk_vk.sol:UltraVerifier");
  const { data: funTokenData } = readDeploymentData("FunToken");
  const { data: processTransferData } = readDeploymentData("contracts/process_pending_transfers/plonk_vk.sol:UltraVerifier");
  const { data: processDepositData } = readDeploymentData("contracts/process_pending_deposits/plonk_vk.sol:UltraVerifier");

  let privateTokenArtifact = await hre.artifacts.readArtifact("PrivateToken")
  let privateToken = getContract({
    abi: privateTokenArtifact.abi,
    address: privateTokenData[chain.name.toLowerCase()].address,
    client: publicClient
  });

  const allTransferVerifierArtifact = await hre.artifacts.readArtifact("TransferVerify")
  const allTransferVerifier = getContract({
    abi: allTransferVerifierArtifact.abi,
    address: transferVerifyData[chain.name.toLowerCase()].address,
    client: publicClient
  });

  const allWithdrawVerifierArtifact = await hre.artifacts.readArtifact("WithdrawVerify")
  const allWithdrawVerifier = getContract({
    abi: allWithdrawVerifierArtifact.abi,
    address: withdrawVerifyData[chain.name.toLowerCase()].address,
    client: publicClient
  });

  const lockVerifierArtifact = await hre.artifacts.readArtifact("contracts/lock/plonk_vk.sol:UltraVerifier")
  const lockVerifier = getContract({
    abi: lockVerifierArtifact.abi,
    address: lockData[chain.name.toLowerCase()].address,
    client: publicClient
  });

  const tokenArtifact = await hre.artifacts.readArtifact("FunToken")
  const token = getContract({
    abi: tokenArtifact.abi,
    address: funTokenData[chain.name.toLowerCase()].address,
    client: publicClient
  });

  const processDepositVerifier = await getContractAt(
    "contracts/process_pending_deposits/plonk_vk.sol:UltraVerifier", processDepositData[network].address
  );
  const processTransferVerifier = await getContractAt(
    "contracts/process_pending_transfers/plonk_vk.sol:UltraVerifier", processTransferData[network].address
  );

  const decimals = await token.read.decimals();

  console.log("Network ", hre.network.name);

  console.log(
    `npx hardhat verify --network ${hre.network.name} ${privateToken.address} ${processDepositVerifier.address} ${processTransferVerifier.address} ${allTransferVerifier.address} ${allWithdrawVerifier.address} ${lockVerifier.address} ${token.address} ${decimals}`
  );
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
