// contracts/FunToken.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../PrivateToken.sol";
import "../TransferVerify.sol";
import "../AccountController.sol";
import {UltraVerifier as AdditionVerifier} from "../correct_addition/plonk_vk.sol";
import {UltraVerifier as ThresholdVerifier} from "../met_threshold/plonk_vk.sol";
import {UltraVerifier as ZeroVerifier} from "../correct_zero/plonk_vk.sol";
import {UltraVerifier as RevokeVerifier} from "../revoke_contribution/plonk_vk.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract FundraiserContract {
    PrivateToken privateToken;
    TransferVerify transferVerify;
    AdditionVerifier additionVerifier;
    ThresholdVerifier thresholdVerifier;
    ZeroVerifier zeroVerifier;
    RevokeVerifier revokeVerifier;
    AccountController accountController;

    // the manager is the account that the bids will be encrypted to
    // users may want to verify that the recipient is the correct account (eg controlled by a multisig)
    mapping(bytes32 manager => Auction[] auctions) auctionsMap;
    mapping(bytes32 sender => bool isPending) hasPendingContribution;
    uint256 BJJ_PRIME = 21888242871839275222246405745257275088548364400416034343698204186575808495617;

    struct Auction {
        bytes32 recipient;
        uint256 endTime;
        address collection;
        uint256 tokenId;
        uint256 highPublicBid;
        uint256 privateBidCount;
        mapping(uint256 => PrivateBid) privateBids;
    }

    struct PrivateBid {
        bytes32 to;
        bytes32 from;
        uint40 relayFee; // this will only be paid by the winner
        address relayFeeRecipient;
        PrivateToken.EncryptedAmount bidAmount;
        PrivateToken.EncryptedAmount senderNewBalance;
        bytes proof_transfer;
    }

    event PublicBid(bytes32 manager, uint256 index, uint256 value);

    /**
     * @notice Sets up the contract with all of the other contracts it will use.
     * @dev
     * @param _privateToken the address of the private token contract
     * @param _transferVerify the address of the transfer verify contract
     * @param _additionVerifier the address of the addition verifier contract
     * @param _thresholdVerifier the address of the threshold verifier contract
     * @param _zeroVerifier the address of the zero verifier contract
     * @param _accountController the address of the account controller contract
     * @param _revokeVerifier the address of the revoke verifier contract
     */
    constructor(
        address _privateToken,
        address _transferVerify,
        address _thresholdVerifier,
        address _zeroVerifier,
        address _accountController
    ) {
        privateToken = PrivateToken(_privateToken);
        transferVerify = TransferVerify(_transferVerify);
        thresholdVerifier = ThresholdVerifier(_thresholdVerifier);
        zeroVerifier = ZeroVerifier(_zeroVerifier);
        accountController = AccountController(_accountController);
    }

    function createAuction(
        bytes32 _manager,
        bytes32 _recipient,
        uint256 _endTime,
        address _collection,
        uint256 _tokenId,
        address _owner
    ) public {
        auctionsMap[_manager].push();
        Auction storage auction = auctionsMap[_manager][auctionsMap[_manager].length - 1];
        auction.recipient = _recipient;
        auction.endTime = _endTime;
        auction.collection = _collection;
        auction.tokenId = _tokenId;
        auction.highPublicBid = 0;
        auction.privateBidCount = 0;

        IERC721(_collection).transferFrom(_owner, address(this), _tokenId);
    }

    function settleAuction() public {}

    function bidPrivate() public {}

    function bidPublic(bytes32 manager, uint256 index) external public payable {
        Auction storage auction = auctionsMap[manager][index];
        require(block.timestamp < auction.endTime, "Auction has ended");
        require(msg.value > auction.highPublicBid, "Bid is too low");
        auction.highPublicBid = msg.value;
        emit PublicBid(manager, index, msg.value);
    }

    /**
     * @notice Anyone can call this function to unlock an account from the fundraiser contract.
     * @dev
     * @param _account the account to unlock
     */
    function unlock(bytes32 _account) public {
        require(!hasPendingContribution[_account], "Has pending contribution");
        privateToken.unlock(_account);
    }
}
