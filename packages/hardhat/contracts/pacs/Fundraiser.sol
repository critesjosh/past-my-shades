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

contract Fundraiser {
    PrivateToken privateToken;
    TransferVerify transferVerify;
    AdditionVerifier additionVerifier;
    ThresholdVerifier thresholdVerifier;
    ZeroVerifier zeroVerifier;
    RevokeVerifier revokeVerifier;
    AccountController accountController;

    // the recipient is the account that will receive the funds
    // users may want to verify that the recipient is the correct account (eg controlled by a multisig)
    mapping(bytes32 recipient => Fundraiser[] fundraisers) fundraisersMap;
    mapping(bytes32 sender => bool isPending) hasPendingContribution;
    uint256 BJJ_PRIME = 21888242871839275222246405745257275088548364400416034343698204186575808495617;

    struct Fundraiser {
        uint256 endTime;
        uint256 threshold;
        bool isThresholdMet;
        PrivateToken.EncryptedAmount amountContributed;
        uint256 contributionCount;
        mapping(uint256 => PendingContribution) contributions;
    }

    struct PendingContribution {
        bytes32 to;
        bytes32 from;
        uint40 relayFee; // this wont be paid until the fundraiser is over, and only if it's successful
        address relayFeeRecipient;
        uint40 processFee; // consider removing this, the fundraiser is incentivized to pay it if it's successful
        PrivateToken.EncryptedAmount amountToSend;
        PrivateToken.EncryptedAmount senderNewBalance;
        bytes proof_transfer;
    }

    event Contribution(bytes32 to, bytes32 from, uint256 fundraiserIndex);
    event RevokedContribution(bytes32 to, bytes32 from, uint256 fundraiserIndex, uint256 contributionIndex);
    event ThresholdMet(bytes32 recipient, uint256 fundraiserIndex);
    event ContributionProcessed(bytes32 to, bytes32 from, uint256 fundraiserIndex, uint256 contributionIndex);
    event ManyProcessed(bytes32 _to, uint256 _fundraiserIndex, uint256 _startIndex);

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
        address _additionVerifier,
        address _thresholdVerifier,
        address _zeroVerifier,
        address _accountController,
        address _revokeVerifier
    ) {
        privateToken = PrivateToken(_privateToken);
        transferVerify = TransferVerify(_transferVerify);
        additionVerifier = AdditionVerifier(_additionVerifier);
        thresholdVerifier = ThresholdVerifier(_thresholdVerifier);
        zeroVerifier = ZeroVerifier(_zeroVerifier);
        accountController = AccountController(_accountController);
        revokeVerifier = RevokeVerifier(_revokeVerifier);
    }

    /**
     * @notice creates a new fundraiser. The recipient is the account that will receive the funds
     * @dev
     * @param _recipient the account that will receive the funds
     * @param _threshold the amount that must be raised for the fundraiser to be successful
     * @param _encryptedZero the encrypted amount that the recipient currently has (0 value encrypted)
     * @param _proof the proof that the encrypted amount is 0
     * @param _endTime the time that the fundraiser will end
     *
     */
    function createFundriser(
        bytes32 _recipient,
        uint256 _threshold,
        PrivateToken.EncryptedAmount memory _encryptedZero,
        bytes memory _proof,
        uint256 _endTime
    ) public {
        bool isThresholdMet = false;
        if (_threshold == 0) {
            isThresholdMet = true;
        }
        fundraisersMap[_recipient].push();
        Fundraiser storage fundraiser = fundraisersMap[_recipient][fundraisersMap[_recipient].length - 1];
        fundraiser.endTime = _endTime;
        fundraiser.threshold = _threshold;
        fundraiser.isThresholdMet = isThresholdMet;
        fundraiser.amountContributed = _encryptedZero;
        fundraiser.contributionCount = 0;
        // Fundraiser memory fundraiser = Fundraiser(_endTime, _threshold, isThresholdMet, encryptedZero, 0);
        bytes32[] memory publicInputs = new bytes32[](36);
        for (uint8 i = 0; i < 32; i++) {
            // Noir takes an array of 32 bytes32 as public inputs
            bytes1 aByte = bytes1((_recipient << (i * 8)));
            publicInputs[i] = bytes32(uint256(uint8(aByte)));
        }
        publicInputs[32] = bytes32(_encryptedZero.C1x);
        publicInputs[33] = bytes32(_encryptedZero.C1y);
        publicInputs[34] = bytes32(_encryptedZero.C2x);
        publicInputs[35] = bytes32(_encryptedZero.C2y);
        zeroVerifier.verify(_proof, publicInputs);
    }

    struct ContributeLocals {
        uint256 txNonce;
        uint256 senderBalanceC1x;
        uint256 senderBalanceC1y;
        uint256 senderBalanceC2x;
        uint256 senderBalanceC2y;
        PrivateToken.EncryptedAmount senderBalance;
        uint256 receiverBalanceC1x;
        uint256 receiverBalanceC1y;
        uint256 receiverBalanceC2x;
        uint256 receiverBalanceC2y;
        PrivateToken.EncryptedAmount receiverBalance;
        PrivateToken.TransferLocals transferLocals;
        bytes32[] publicInputs;
    }

    /**
     * @notice A user calls this when they want to contriubte to a fundraiser. They pass all of the info
     * required to process a transfer transaction on the _privateToken contract, as well as info about the
     * fundraiser they are contributing to. They also need to pass info to prove that they have increased
     * their amount contributed to the fundraiser correctly.
     * @dev
     * @param _fundraiserIndex the index of the fundraiser in the fundraisers mapping
     * @param _to the account that will receive the funds (recipient account)
     * @param _from the account that will send the funds (users account)
     * @param _relayFee the amount that will be paid to the relay (if the fundraiser is successful)
     * @param _relayFeeRecipient the account that will receive the relay fee (if the fundraiser is successful)
     * @param _amountToSend the amount that the user wants to contribute
     * @param _senderNewBalance the new balance of the user after the contribution
     * @param _proof_transfer the proof that the transfer is valid
     * @param _proof_increaseAmountContributed the proof that the amount contributed has been increased correctly
     * @param _newTotalContributed the new encrypted total contributed to the fundraiser
     */
    function contribute(
        uint256 _fundraiserIndex,
        bytes32 _to,
        bytes32 _from,
        uint40 _relayFee, // relay fee is only paid if the fundraiser is successful
        address _relayFeeRecipient,
        PrivateToken.EncryptedAmount calldata _amountToSend,
        PrivateToken.EncryptedAmount calldata _senderNewBalance,
        bytes memory _proof_transfer,
        bytes memory _proof_increaseAmountContributed,
        PrivateToken.EncryptedAmount memory _newTotalContributed
    ) public {
        require(privateToken.lockedTo(_from) == address(this), "Not locked to fundraiser");
        require(hasPendingContribution[_from] == false, "Can only contribute to 1 at a time");
        ContributeLocals memory contributeLocals;
        contributeLocals.txNonce = uint256(keccak256(abi.encode(_amountToSend))) % BJJ_PRIME;
        require(privateToken.nonce(_from, contributeLocals.txNonce) == false, "Nonce must be unused");
        (
            contributeLocals.senderBalanceC1x,
            contributeLocals.senderBalanceC1y,
            contributeLocals.senderBalanceC2x,
            contributeLocals.senderBalanceC2y
        ) = privateToken.balances(_from);
        contributeLocals.senderBalance = PrivateToken.EncryptedAmount({
            C1x: contributeLocals.senderBalanceC1x,
            C1y: contributeLocals.senderBalanceC1y,
            C2x: contributeLocals.senderBalanceC2x,
            C2y: contributeLocals.senderBalanceC2y
        });

        (
            contributeLocals.receiverBalanceC1x,
            contributeLocals.receiverBalanceC1y,
            contributeLocals.receiverBalanceC2x,
            contributeLocals.receiverBalanceC2y
        ) = privateToken.balances(_to);
        contributeLocals.receiverBalance = PrivateToken.EncryptedAmount({
            C1x: contributeLocals.receiverBalanceC1x,
            C1y: contributeLocals.receiverBalanceC1y,
            C2x: contributeLocals.receiverBalanceC2x,
            C2y: contributeLocals.receiverBalanceC2y
        });
        contributeLocals.transferLocals = PrivateToken.TransferLocals({
            to: _to,
            from: _from,
            processFee: 0, // fundraisers are incentivized to pay the process fee if the fundraiser is successful
            relayFee: _relayFee,
            txNonce: contributeLocals.txNonce,
            oldBalance: contributeLocals.senderBalance,
            amountToSend: _amountToSend,
            receiverBalance: contributeLocals.receiverBalance,
            senderNewBalance: _senderNewBalance,
            proof: _proof_transfer,
            // the following dont matter
            lockedByAddress: address(0x0),
            transferCount: 0,
            privateToken: PrivateToken(address(0x0))
        });

        Fundraiser storage f = fundraisersMap[_to][_fundraiserIndex];

        // 1. verifies that the transfer is valid
        // this call ensures that if _from is controlled by an eth controller, the msg.sender is the eth controller
        transferVerify.verifyTransfer(contributeLocals.transferLocals);

        // 2. verify increaseAmountContributed
        contributeLocals.publicInputs = new bytes32[](12);
        contributeLocals.publicInputs[0] = bytes32(f.amountContributed.C1x);
        contributeLocals.publicInputs[1] = bytes32(f.amountContributed.C1y);
        contributeLocals.publicInputs[2] = bytes32(f.amountContributed.C2x);
        contributeLocals.publicInputs[3] = bytes32(f.amountContributed.C2y);
        contributeLocals.publicInputs[4] = bytes32(_amountToSend.C1x);
        contributeLocals.publicInputs[5] = bytes32(_amountToSend.C1y);
        contributeLocals.publicInputs[6] = bytes32(_amountToSend.C2x);
        contributeLocals.publicInputs[7] = bytes32(_amountToSend.C2y);
        contributeLocals.publicInputs[8] = bytes32(_newTotalContributed.C1x);
        contributeLocals.publicInputs[9] = bytes32(_newTotalContributed.C1y);
        contributeLocals.publicInputs[10] = bytes32(_newTotalContributed.C2x);
        contributeLocals.publicInputs[11] = bytes32(_newTotalContributed.C2y);

        // verifies that the amount contributed has been correctly updated
        additionVerifier.verify(_proof_increaseAmountContributed, contributeLocals.publicInputs);

        f.amountContributed = _newTotalContributed;

        uint256 index = fundraisersMap[_to][_fundraiserIndex].contributionCount;
        f.contributions[index] = PendingContribution(
            _to, _from, _relayFee, _relayFeeRecipient, 0, _amountToSend, _senderNewBalance, _proof_transfer
        );

        hasPendingContribution[_from] = true;
        emit Contribution(_to, _from, _fundraiserIndex);
    }

    /**
     * @notice Users can revoke their contriubtion if the fundraiser is not successful, meaning the endTime has passed
     * and the threshold was not met. If someone has contributed and the fundraiser was not successful, they must
     * call this function before they can unlock their account from the fundraiser contract. If the sender's
     * account is controlled by an EthController, as registered in the Account Controller contract, then the
     * registered EthController must call this function.
     * @dev
     * @param _to the account that was to receive the funds (recipient account)
     * @param _from the account that was to send the funds (users account)
     * @param _fundraiserIndex the index of the fundraiser in the fundraisers mapping
     * @param _contributionIndex the index of the contribution in the fundraisers mapping
     * @param _proof the proof that the user has the private key corresponding to the public key
     */
    function revokeContribution(
        bytes32 _to,
        bytes32 _from,
        uint256 _fundraiserIndex,
        uint256 _contributionIndex,
        bytes memory _proof
    ) public {
        require(hasPendingContribution[_from], "No pending contribution");
        Fundraiser storage f = fundraisersMap[_to][_fundraiserIndex];
        require(f.endTime >= block.timestamp, "End time must has passed");
        require(f.isThresholdMet == false, "Fundraiser must not be successful");

        delete fundraisersMap[_to][_fundraiserIndex].contributions[
            _contributionIndex
        ];
        hasPendingContribution[_from] = false;

        // check if the sender is controlled by an eth controller
        address controller = accountController.ethController(_from);
        if (controller != address(0x0)) {
            require(msg.sender == controller, "Transfer must be sent from the eth controller");
        }

        // check that the sender has the private key corresponding to the public key
        bytes32[] memory publicInputs = new bytes32[](32);
        for (uint8 i = 0; i < 32; i++) {
            // Noir takes an array of 32 bytes32 as public inputs
            bytes1 aByte = bytes1((_from << (i * 8)));
            publicInputs[i] = bytes32(uint256(uint8(aByte)));
        }
        revokeVerifier.verify(_proof, publicInputs);
        emit RevokedContribution(_to, _from, _fundraiserIndex, _contributionIndex);
    }

    /**
     * @notice The fundraiser recipient calls this function when they want to set the threshold as met. They generate
     * a proof that the encrypted amountContributed is greater than or equal to the threshold. This proof is verified.
     * Only someone that can decrypt the amountContributed will be able to generate a valid proof
     * @dev
     * @param recipient the account that will receive the funds (recipient account)
     * @param fundraiserIndex the index of the fundraiser in the fundraisers mapping
     * @param proof the proof that the fundraiser threshold has been met
     */
    function setThresholdMet(bytes32 recipient, uint256 fundraiserIndex, bytes memory proof) public {
        fundraisersMap[recipient][fundraiserIndex].isThresholdMet = true;
        Fundraiser storage f = fundraisersMap[recipient][fundraiserIndex];
        require(f.endTime < block.timestamp, "Fundraiser must be open");

        bytes32[] memory publicInputs = new bytes32[](5);
        publicInputs[0] = bytes32(f.amountContributed.C1x);
        publicInputs[1] = bytes32(f.amountContributed.C1y);
        publicInputs[2] = bytes32(f.amountContributed.C2x);
        publicInputs[3] = bytes32(f.amountContributed.C2y);
        publicInputs[4] = bytes32(f.threshold);

        // checks that the threshold has been met without revealing the specific amount raised
        thresholdVerifier.verify(proof, publicInputs);
        emit ThresholdMet(recipient, fundraiserIndex);
    }

    /**
     * @notice Anyone can call this function to process contributions and have them settle on the
     * private token contract. As written, this function will process up to 10 contributions at a time.
     * The recipient of the fundraiser is incentiviized to call this function, as they will receive the
     * funds. Relay fee recipients are also incentivized to call this function, as they will receive the
     * relay fees. This function could likely be optimized (change loop size, allow processors to pick contributions
     * to process).
     * @dev
     * @param _to the account that will receive the funds (recipient account)
     * @param _fundraiserIndex the index of the fundraiser in the fundraisers mapping
     * @param _startIndex the index of the contribution to start processing at. If the array is lager, it may take
     * multiple calls to process all of the contributions. Or if one is failing for some reason, it can be skipped.
     */
    function processContributions(bytes32 _to, uint256 _fundraiserIndex, uint256 _startIndex) public {
        Fundraiser storage f = fundraisersMap[_to][_fundraiserIndex];
        require(f.isThresholdMet, "Fundraising threshold must be met");
        // TODO: figure out how many loops this should do
        for (uint256 i = _startIndex; i < 10; i++) {
            PendingContribution memory contribution = f.contributions[i];
            privateToken.transfer(
                contribution.to,
                contribution.from,
                0, // process fee
                contribution.relayFee, // relay fee
                address(0), // relay fee recipient
                contribution.amountToSend,
                contribution.senderNewBalance,
                contribution.proof_transfer
            );
            // must not have a pending contribution to unlock the account
            hasPendingContribution[contribution.from] = false;
            emit ContributionProcessed(contribution.to, contribution.from, _fundraiserIndex, i);
        }
        emit ManyProcessed(_to, _fundraiserIndex, _startIndex);
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
