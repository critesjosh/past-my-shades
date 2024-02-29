// contracts/FunToken.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../PrivateToken.sol";
import "../AccountController.sol";
import {UltraVerifier as AdditionVerifier} from "../correct_addition/plonk_vk.sol";
import {UltraVerifier as ZeroVerifier} from "../correct_zero/plonk_vk.sol";
import {UltraVerifier as OwnerVerifier} from "../check_owner/plonk_vk.sol";

contract FundraiserContract {
    PrivateToken privateToken;
    AdditionVerifier additionVerifier;
    ZeroVerifier zeroVerifier;
    AccountController accountController;

    // the manager is the account that will manage the Election struct
    mapping(bytes32 manager => Vote[] votes) votesMap;
    uint256 BJJ_PRIME = 21888242871839275222246405745257275088548364400416034343698204186575808495617;
    mapping(bytes32 nullifier => bool) nullifiers;
    mapping(bytes32 voter => Vote[]) pendingVotes;

    struct Vote {
        uint256 endTime;
        PrivateToken.EncryptedAmount yayVotes;
        uiPrivateToken.EncryptedAmount nayVotes;
        bool passed;
    }

    struct PendingVote {
        bytes32 manager;
        uint256 index;
        bool finished;
    }

    event Vote(bytes32 to, bytes32 from, uint256 voteIndex);

    /**
     * @notice Sets up the contract with all of the other contracts it will use.
     * @dev
     * @param _privateToken the address of the private token contract
     * @param _additionVerifier the address of the addition verifier contract
     * @param _zeroVerifier the address of the zero verifier contract
     * @param _accountController the address of the account controller contract
     */
    constructor(address _privateToken, address _additionVerifier, address _zeroVerifier, address _accountController) {
        privateToken = PrivateToken(_privateToken);
        additionVerifier = AdditionVerifier(_additionVerifier);
        zeroVerifier = ZeroVerifier(_zeroVerifier);
        accountController = AccountController(_accountController);
    }

    function createVote(bytes32 _manager, uint256 _endTime, PrivateToken.EncryptedAmount _encryptedZero) public {
        votesMap[_manager].push();
        Vote storage vote = votesMap[_manager][votesMap.manager.length - 1];
        vote.endTime = _endTime;
        vote.yayVotes = _encryptedZero;
        vote.nayVotes = _encryptedZero;
        vote.passed = false;

        // bytes32[] memory publicInputs = new bytes32[](36);
        // for (uint8 i = 0; i < 32; i++) {
        //     // Noir takes an array of 32 bytes32 as public inputs
        //     bytes1 aByte = bytes1((_recipient << (i * 8)));
        //     publicInputs[i] = bytes32(uint256(uint8(aByte)));
        // }
        // publicInputs[32] = bytes32(_encryptedZero.C1x);
        // publicInputs[33] = bytes32(_encryptedZero.C1y);
        // publicInputs[34] = bytes32(_encryptedZero.C2x);
        // publicInputs[35] = bytes32(_encryptedZero.C2y);
        // zeroVerifier.verify(_proof, publicInputs);
    }

    function castVote(
        bytes32 _to,
        bytes32 _from,
        uint256 _electionIndex,
        PrivateToken.EncryptedAmount yayVote,
        PrivateToken.EncryptedAmount nayVote
    ) public {
        require(privateToken.lockedTo(_from) == address(this), "Not locked to voting contract");
        pendingVotesCount[_from]++;
        // increment both yay and nay votes, to hide which is actually being cast
        // circuit check that the votes are properly encrypted and incremented
        // circuit will check that the voter is incrementing by their token balance in PrivateToken, or less
        bytes32 nullifier = keccak256(_to, _from, _electionIndex);
        require(!nullifiers[nullifier], "Vote already cast");
        nullifiers[nullifier] = true;
    }

    function processVote(bytes32 _manager, uint256 _index) public {
        // circuit checks that yay or nay votes is greater
        // check that endTime has passed
        // decrement pendingVotesCount
    }

    /**
     * @notice Anyone can call this function to unlock an account from the fundraiser contract.
     * @dev
     * @param _account the account to unlock
     */
    function unlock(bytes32 _account, bytes _proof) public {
        // use a proof to check that the caller has the _account private key
        // TODO: optimize this
        for (i = 0; i++; pendingVotes[_account].length) {
            require(pendingVotes[_account][i].finished, "Vote not finished");
        }
        privateToken.unlock(_account);
    }
}
