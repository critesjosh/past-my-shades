// contracts/FunToken.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../PrivateToken.sol";
import "../TransferVerify.sol";
import "../AccountController.sol";
import "../IERC721.sol";
import {UltraVerifier as ConsolidateVerifier} from "../consolidate_bids/plonk_vk.sol";
import {UltraVerifier as SettleVerifier} from "../private_bid_greater/plonk_vk.sol";
import {UltraVerifier as OwnerVerifier} from "../check_owner/plonk_vk.sol";

contract AuctionContract {
    PrivateToken privateToken;
    TransferVerify transferVerify;
    AccountController accountController;
    ConsolidateVerifier consolidateBidsVerifier;
    SettleVerifier settleVerifier;
    OwnerVerifier ownerVerifier;
    // the manager is the account that the bids will be encrypted to
    // users may want to verify that the recipient is the correct account (eg controlled by a multisig)
    mapping(bytes32 manager => Auction[] auctions) auctionsMap;
    mapping(bytes32 bidder => bool isPending) hasPendingBid;
    uint256 BJJ_PRIME = 21888242871839275222246405745257275088548364400416034343698204186575808495617;

    struct Auction {
        bytes32 recipient;
        address publicClaimAddress;
        uint256 endTime;
        address collection;
        uint256 tokenId;
        uint256 highPublicBid;
        PrivateBid[] privateBids;
        bytes32 privateWinner;
    }
    // uint256 privateBidCount;
    // mapping(uint256 => PrivateBid) privateBids;

    struct PrivateBid {
        bytes32 from;
        uint40 relayFee; // this will only be paid by the winner
        address relayFeeRecipient;
        PrivateToken.EncryptedAmount bidAmount;
        PrivateToken.EncryptedAmount senderNewBalance;
        bytes proof_transfer;
    }

    event PublicBid(bytes32 manager, uint256 index, uint256 value);
    event PrivateBidEmitted(bytes32 manager, uint256 index, bytes32 from);

    /**
     * @notice Sets up the contract with all of the other contracts it will use.
     * @dev
     * @param _privateToken the address of the private token contract
     * @param _transferVerify the address of the transfer verify contract
     * @param _accountController the address of the account controller contract
     */
    constructor(
        address _privateToken,
        address _transferVerify,
        address _thresholdVerifier,
        address _accountController,
        address _consolidateBidsVerifier,
        address _settleVerifier,
        address _ownerVerifier
    ) {
        privateToken = PrivateToken(_privateToken);
        transferVerify = TransferVerify(_transferVerify);
        accountController = AccountController(_accountController);
        consolidateBidsVerifier = ConsolidateVerifier(_consolidateBidsVerifier);
        settleVerifier = SettleVerifier(_settleVerifier);
        ownerVerifier = OwnerVerifier(_ownerVerifier);
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

    // Auction manager must call this function a number of times, until there is only 1 high bid left
    function consolidatePrivateBids(bytes32 _manager, uint256 _auctionIndex, uint256 _highIndex, bytes _proof) public {
        Auction memory auction = auctionsMap[_manager][_auctionIndex];
        require(block.timestamp > auction.endTime, "Auction hasn't ended");

        uint256 length = auction.privateBids;
        // the circuit can only reconcile 4 bids at a time (could optmize)
        if (length > 4) {
            length = 4;
        }
        uint256 lastIndex = auction.privateBids.length - 1;
        PrivateBid[] arrayToCompare = sliceArray(auction.privateBids, lastIndex - length, lastIndex);
        PrivateBid[] replacementArray = sliceArray(auction.privateBids, 0, lastIndex - length);
        // add the highest bid back to the array in storage, to keep processing, or settle the auction
        replacementArray.push(arrayToCompare[_highIndex]);
        auctionsMap[_manager][_auctionIndex].privateBids = replacementArray;

        for (uint256 i = 0; i < arrayToCompare.length; i++) {
            if (i != _highIndex) hasPendingBid[arrayToCompare[i].from] = false;
        }

        bytes32[] publicInputs = new bytes32[](17);
        publicInputs[0] = bytes32(arrayToCompare[0].bidAmount.C1x);
        publicInputs[1] = bytes32(arrayToCompare[0].bidAmount.C1y);
        publicInputs[2] = bytes32(arrayToCompare[0].bidAmount.C2x);
        publicInputs[3] = bytes32(arrayToCompare[0].bidAmount.C2y);
        publicInputs[4] = bytes32(arrayToCompare[1].bidAmount.C1x);
        publicInputs[5] = bytes32(arrayToCompare[1].bidAmount.C1y);
        publicInputs[6] = bytes32(arrayToCompare[1].bidAmount.C2x);
        publicInputs[7] = bytes32(arrayToCompare[1].bidAmount.C2y);
        publicInputs[8] = bytes32(arrayToCompare[2].bidAmount.C1x);
        publicInputs[9] = bytes32(arrayToCompare[2].bidAmount.C1y);
        publicInputs[10] = bytes32(arrayToCompare[2].bidAmount.C2x);
        publicInputs[11] = bytes32(arrayToCompare[2].bidAmount.C2y);
        publicInputs[12] = bytes32(arrayToCompare[3].bidAmount.C1x);
        publicInputs[13] = bytes32(arrayToCompare[3].bidAmount.C1y);
        publicInputs[14] = bytes32(arrayToCompare[3].bidAmount.C2x);
        publicInputs[15] = bytes32(arrayToCompare[3].bidAmount.C2y);
        publicInputs[16] = bytes32(_highIndex);

        consolidateBidsVerifier.verifyProof(_proof, publicInputs);
    }

    function settleAuction(bytes32 _manager, uint256 _auctionIndex, bool privateBidWins, bytes memory _proof) public {
        Auction memory auction = auctionsMap[_manager][_auctionIndex];
        require(block.timestamp > auction.endTime, "Auction hasn't ended");

        require(auction.privateBids.length == 1, "Private bids must be consolidated");
        bytes32[] publicInputs = new bytes32[](5);
        publicInputs[0] = bytes32(auction.privateBids[0].bidAmount.C1x);
        publicInputs[1] = bytes32(auction.privateBids[0].bidAmount.C1y);
        publicInputs[2] = bytes32(auction.privateBids[0].bidAmount.C2x);
        publicInputs[3] = bytes32(auction.privateBids[0].bidAmount.C2y);
        publicInputs[4] = bytes32(auction.highPublicBid);
        publicInputs[5] = bytes32(privateBidWins);
        settleVerifier.verify(_proof, publicInputs);

        hasPendingBid[auction.privateBids[0].from] = false;

        PrivateBid memory bid = auction.privateBids[0];
        // settle if private bid wins
        if (privateBidWins) {
            privateToken.transfer(
                auction.recipient, // to
                bid.from,
                0, // process fee
                bid.relayFee, // relay fee
                address(0), // relay fee recipient
                bid.amountToSend,
                bid.senderNewBalance,
                bid.proof_transfer
            );
            auctionsMap[_manager][_auctionIndex].privateWinner = bid.from;
        } else {
            auction.publicClaimAddress.transfer(auction.highPublicBid);
            IERC721(auction.collection).transferFrom(address(this), auction.publicClaimAddress, auction.tokenId);
        }
    }

    // this is called after the auction is settled, by someone that can produce a proof that they own the winning bid
    function claimNft(bytes32 _manager, uint256 _auctionIndex, address _recipient, bytes memory _proof) public {
        Auction memory auction = auctionsMap[_manager][_auctionIndex];
        require(auction.privateWinner != bytes32(0x0), "Auction not settled");

        bytes32[] memory publicInputs = new bytes32[](32);
        for (uint8 i = 0; i < 32; i++) {
            // Noir takes an array of 32 bytes32 as public inputs
            bytes1 aByte = bytes1((auction.privateWinner << (i * 8)));
            publicInputs[i] = bytes32(uint256(uint8(aByte)));
        }
        ownerVerifier.verify(_proof, publicInputs);
        IERC721(auction.collection).transferFrom(address(this), _recipient, auction.tokenId);
    }

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
        Auction memory auction = auctionsMap[_manager][_auctionIndex];

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
        ) = privateToken.balances(auction.recipient);
        bidLocals.receiverBalance = PrivateToken.EncryptedAmount({
            C1x: bidLocals.receiverBalanceC1x,
            C1y: bidLocals.receiverBalanceC1y,
            C2x: bidLocals.receiverBalanceC2x,
            C2y: bidLocals.receiverBalanceC2y
        });
        bidLocals.transferLocals = PrivateToken.TransferLocals({
            to: auction.recipient,
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
        // uint256 index = auctionsMap[_manager][_auctionIndex].privateBidCount;
        Auction storage a = auctionsMap[_manager][_auctionIndex];
        a.privateBids.push(bid);

        emit PrivateBid(_manager, _auctionIndex, _from);
    }

    function bidPublic(bytes32 manager, uint256 index) external payable {
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
        require(!hasPendingBid[_account], "Has pending bid");
        privateToken.unlock(_account);
    }

    function sliceArray(PrivateBid[] memory array, uint256 start, uint256 end) public pure returns (uint256[] memory) {
        require(start < end, "Start index must be less than end index.");
        require(end <= array.length, "End index out of bounds.");

        PrivateBid[] memory slice = new PrivateBid[](end - start);
        for (uint256 i = 0; i < slice.length; i++) {
            slice[i] = array[start + i];
        }
        return slice;
    }
}
