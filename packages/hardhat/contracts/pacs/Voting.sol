// contracts/FunToken.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../PrivateToken.sol";
import "../AccountController.sol";
import {UltraVerifier as ZeroVerifier} from "../correct_zero/plonk_vk.sol";
import {UltraVerifier as VoteVerifier} from "../check_vote/plonk_vk.sol";
import {UltraVerifier as ProcessVotesVerifier} from "../process_votes/plonk_vk.sol";

contract Voting {
    PrivateToken privateToken;
    ZeroVerifier zeroVerifier;
    AccountController accountController;
    VoteVerifier voteVerifier;
    ProcessVotesVerifier processVotesVerifier;

    // the manager is the account that will manage the Vote struct
    mapping(bytes32 manager => Vote[] votes) votesMap;
    mapping(bytes32 voter => uint256 pending) pendingVotes;
    uint256 BJJ_PRIME = 21888242871839275222246405745257275088548364400416034343698204186575808495617;
    mapping(bytes32 nullifier => bool) nullifiers;

    struct Vote {
        uint256 endTime;
        PrivateToken.EncryptedAmount yayVotes;
        PrivateToken.EncryptedAmount nayVotes;
        bool passed;
        bytes32[] pendingVotes;
        address destContract;
        bytes _calldata;
    }

    event VoteLog(bytes32 to, bytes32 from, uint256 voteIndex);

    /**
     * @notice Sets up the contract with all of the other contracts it will use.
     * @dev
     * @param _privateToken the address of the private token contract
     * @param _zeroVerifier the address of the zero verifier contract
     * @param _accountController the address of the account controller contract
     */
    constructor(
        address _privateToken,
        address _zeroVerifier,
        address _accountController,
        address _voteVerifier,
        address _processVotesVerifier
    ) {
        privateToken = PrivateToken(_privateToken);
        zeroVerifier = ZeroVerifier(_zeroVerifier);
        accountController = AccountController(_accountController);
        voteVerifier = VoteVerifier(_voteVerifier);
        processVotesVerifier = ProcessVotesVerifier(_processVotesVerifier);
    }

    function createVote(
        bytes32 _manager,
        uint256 _endTime,
        PrivateToken.EncryptedAmount memory _encryptedZero,
        address destContract,
        bytes memory _calldata,
        bytes memory _proof
    ) public {
        votesMap[_manager].push();
        Vote storage vote = votesMap[_manager][votesMap[_manager].length - 1];
        vote.endTime = _endTime;
        vote.yayVotes = _encryptedZero;
        vote.nayVotes = _encryptedZero;
        vote.passed = false;
        vote.destContract = destContract;
        vote._calldata = _calldata;

        bytes32[] memory publicInputs = new bytes32[](36);
        for (uint8 i = 0; i < 32; i++) {
            // Noir takes an array of 32 bytes32 as public inputs
            bytes1 aByte = bytes1((_manager << (i * 8)));
            publicInputs[i] = bytes32(uint256(uint8(aByte)));
        }
        publicInputs[32] = bytes32(_encryptedZero.C1x);
        publicInputs[33] = bytes32(_encryptedZero.C1y);
        publicInputs[34] = bytes32(_encryptedZero.C2x);
        publicInputs[35] = bytes32(_encryptedZero.C2y);
        zeroVerifier.verify(_proof, publicInputs);
    }

    function castVote(
        bytes32 _to,
        bytes32 _from,
        uint256 _electionIndex,
        PrivateToken.EncryptedAmount memory yayVote,
        PrivateToken.EncryptedAmount memory nayVote,
        bytes memory _proof
    ) public {
        require(privateToken.lockedTo(_from) == address(this), "Not locked to voting contract");
        pendingVotes[_from]++;
        (uint256 voterBalanceC1x, uint256 voterBalanceC1y, uint256 voterBalanceC2x, uint256 voterBalanceC2y) =
            privateToken.balances(_from);

        Vote storage v = votesMap[_to][_electionIndex];
        v.nayVotes = nayVote;
        v.yayVotes = yayVote;
        v.pendingVotes.push(_from);
        // circuit check that the votes are properly encrypted and incremented
        // circuit will check that the voter is incrementing by their token balance in PrivateToken, or less
        bytes32[] memory publicInputs = new bytes32[](13);
        publicInputs[0] = bytes32(fromRprLe(_to));
        publicInputs[1] = bytes32(voterBalanceC1x);
        publicInputs[2] = bytes32(voterBalanceC1y);
        publicInputs[3] = bytes32(voterBalanceC2x);
        publicInputs[4] = bytes32(voterBalanceC2y);
        publicInputs[5] = bytes32(yayVote.C1x);
        publicInputs[6] = bytes32(yayVote.C1y);
        publicInputs[7] = bytes32(yayVote.C2x);
        publicInputs[8] = bytes32(yayVote.C2y);
        publicInputs[9] = bytes32(nayVote.C1x);
        publicInputs[10] = bytes32(nayVote.C1y);
        publicInputs[11] = bytes32(nayVote.C2x);
        publicInputs[12] = bytes32(nayVote.C2y);

        voteVerifier.verify(_proof, publicInputs);

        // make sure no double voting
        bytes32 nullifier = keccak256(abi.encodePacked(_to, _from, _electionIndex));
        require(!nullifiers[nullifier], "Vote already cast");
        nullifiers[nullifier] = true;
    }

    function processVotes(bytes32 _manager, uint256 _index, uint256 yayWins, bytes memory _proof) public {
        Vote memory v = votesMap[_manager][_index];
        require(v.endTime < block.timestamp, "Vote isn't over");
        // circuit checks that yay or nay votes is greater
        bytes32[] memory publicInputs = new bytes32[](9);
        publicInputs[0] = bytes32(v.yayVotes.C1x);
        publicInputs[1] = bytes32(v.yayVotes.C1y);
        publicInputs[2] = bytes32(v.yayVotes.C2x);
        publicInputs[3] = bytes32(v.yayVotes.C2y);
        publicInputs[4] = bytes32(v.nayVotes.C1x);
        publicInputs[5] = bytes32(v.nayVotes.C1y);
        publicInputs[6] = bytes32(v.nayVotes.C2x);
        publicInputs[7] = bytes32(v.nayVotes.C2y);
        publicInputs[8] = bytes32(yayWins);
        processVotesVerifier.verify(_proof, publicInputs);
        // TODO: this unbounded loop is currenlty an attack vector. modify
        // could allow users to decrement, but degrades UX
        for (uint256 i = 0; i < v.pendingVotes.length; i++) {
            pendingVotes[v.pendingVotes[i]]--;
        }
        // call the destContract with the provided calldata
        address(v.destContract).call(v._calldata);

        votesMap[_manager][_index].passed = true;
    }

    /**
     * @notice Anyone can call this function to unlock an account from the fundraiser contract.
     * @dev
     * @param _account the account to unlock
     */
    function unlock(bytes32 _account, bytes memory _proof) public {
        require(pendingVotes[_account] == 0, "Can't unlock while voting");
        // use a proof to check that the caller has the _account private key
        privateToken.unlock(_account);
    }

    function fromRprLe(bytes32 publicKey) internal view returns (uint256) {
        uint256 y = 0;
        uint256 v = 1;
        bytes memory publicKeyBytes = bytes32ToBytes(publicKey);
        for (uint8 i = 0; i < 32; i++) {
            y += (uint8(publicKeyBytes[i]) * v) % BJJ_PRIME;
            if (i != 31) {
                v *= 256;
            }
        }
        return y;
    }

    function bytes32ToBytes(bytes32 _data) public pure returns (bytes memory) {
        bytes memory byteArray = new bytes(32);
        for (uint256 i = 0; i < 32; i++) {
            byteArray[i] = _data[i];
        }
        return byteArray;
    }
}
