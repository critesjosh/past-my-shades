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
    mapping(bytes32 bidder => bool isPending) hasPendingBid;
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
    event PrivateBid(bytes32 manager, uint256 index, bytes32 from);

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

    function bidPrivate(
        uint256 _auctionIndex,
        bytes32 _manager,
        bytes32 _from,
        uint40 _relayFee, // relay fee is only paid if the bid is successful
        address _relayFeeRecipient,
        PrivateToken.EncryptedAmount calldata _bidAmount,
        PrivateToken.EncryptedAmount calldata _senderNewBalance,
        bytes memory _proof_transfer
    ) public {
        require(privateToken.lockedTo(_from) == address(this), "Not locked to fundraiser");
        require(hasPendingBid[_from] == false, "Can only bid to 1 at a time");
        BidLocals memory bidLocals;
        bidLocals.txNonce = uint256(keccak256(abi.encode(_amountToSend))) % BJJ_PRIME;
        require(privateToken.nonce(_from, bidLocals.txNonce) == false, "Nonce must be unused");
        (bidLocals.senderBalanceC1x, bidLocals.senderBalanceC1y, bidLocals.senderBalanceC2x, bidLocals.senderBalanceC2y)
        = privateToken.balances(_from);
        bidLocals.senderBalance = PrivateToken.EncryptedAmount({
            C1x: bidLocals.senderBalanceC1x,
            C1y: bidLocals.senderBalanceC1y,
            C2x: bidLocals.senderBalanceC2x,
            C2y: bidLocals.senderBalanceC2y
        });

        (
            bidLocals.receiverBalanceC1x,
            bidLocals.receiverBalanceC1y,
            bidLocals.receiverBalanceC2x,
            bidLocals.receiverBalanceC2y
        ) = privateToken.balances(_to);
        bidLocals.receiverBalance = PrivateToken.EncryptedAmount({
            C1x: bidLocals.receiverBalanceC1x,
            C1y: bidLocals.receiverBalanceC1y,
            C2x: bidLocals.receiverBalanceC2x,
            C2y: bidLocals.receiverBalanceC2y
        });
        bidLocals.transferLocals = PrivateToken.TransferLocals({
            to: _to,
            from: _from,
            processFee: 0, // fundraisers are incentivized to pay the process fee if the fundraiser is successful
            relayFee: _relayFee,
            txNonce: bidLocals.txNonce,
            oldBalance: bidLocals.senderBalance,
            amountToSend: _amountToSend,
            receiverBalance: bidLocals.receiverBalance,
            senderNewBalance: _senderNewBalance,
            proof: _proof_transfer,
            // the following dont matter
            lockedByAddress: address(0x0),
            transferCount: 0,
            privateToken: PrivateToken(address(0x0))
        });
        transferVerify.verifyTransfer(bidLocals.transferLocals);
        hasPendingBid[_from] = true;

        PrivateBid bid = PrivateBid({
            to: _to,
            from: _from,
            relayFee: _relayFee,
            relayFeeRecipient: _relayFeeRecipient,
            bidAmount: _bidAmount,
            senderNewBalance: _senderNewBalance,
            proof_transfer: _proof_transfer
        });
        uint256 index = auctionsMap[_manager][_auctionIndex].privateBidCount;
        Auction storage a = auctionsMap[_manager][_auctionIndex];
        a.privateBids[index] = bid;

        emit PrivateBid(_manager, _auctionIndex, _from);
    }

    function bidPublic(bytes32 manager, uint256 index) external public payable {
        Auction storage auction = auctionsMap[manager][index];
        require(block.timestamp < auction.endTime, "Auction has ended");
        require(msg.value > auction.highPublicBid, "Bid is too low");
        auction.highPublicBid = msg.value;
        emit PublicBid(manager, index, msg.value);
    }

    // TODO: implement this
    function revokePrivateBid() public {}

    // this must be called by the manager
    // it takes several private bids and compares them, deleting the lower ones
    function compareAndRemovePrivateBid() public {}

    function processAuction(bytes32 manager, uint256 index) public {
        Auction storage auction = auctionsMap[manager][index];
        require(block.timestamp > auction.endTime, "Auction hasn't ended");
        // create a circuit that takes the highest public bid and the highest private bid
    }

    /**
     * @notice Anyone can call this function to unlock an account from the fundraiser contract.
     * @dev
     * @param _account the account to unlock
     */
    function unlock(bytes32 _account) public {
        require(!hasPendingBid[_account], "Has pending bid");
        privateToken.unlock(_account);
    }
}
