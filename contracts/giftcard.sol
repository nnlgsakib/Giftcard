// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

library RedeemCodeGenerator {
    function generateHumanReadableCode(uint256 seed, string memory customAlphabet) internal pure returns (bytes8) {
        bytes memory alphabet = bytes(customAlphabet);
        uint256 alphabetLength = alphabet.length;

        require(alphabetLength > 0, "Custom alphabet must not be empty");
        require(alphabetLength <= 256, "Custom alphabet is too long");

        bytes memory result = new bytes(8);

        for (uint256 i = 0; i < 8; i++) {
            bytes32 hash = keccak256(abi.encodePacked(seed, i));
            uint256 index = uint256(hash) % alphabetLength;

            result[i] = alphabet[index];
        }

        return bytes8(result);
    }
}

contract Giftcard is Ownable, ReentrancyGuard {
    using Counters for Counters.Counter;
    using ECDSA for bytes32;
    using SafeMath for uint256;
    using RedeemCodeGenerator for uint256;

    event GiftCardCreated(uint256 indexed cardId, bytes8 indexed redeemCode, address indexed creator, uint256 depositAmount);
    event EthRedeemed(uint256 indexed cardId, address indexed redeemer, bytes8 indexed redeemCode, uint256 redeemedAmount);

    struct Card {
        uint256 cardId;
        bytes8 redeemCode;
        address creator;
        uint256 depositAmount;
        bool redeemed;
    }

    mapping(bytes8 => bool) private isRedeemed;
    Card[] public giftCards;
    Counters.Counter private cardIdCounter;

    modifier notRedeemed(bytes8 redeemCode) {
        require(!isRedeemed[redeemCode], "Gift card already redeemed");
        _;
    }

    function generateRandomCode() internal view returns (bytes8) {
        uint256 seed = uint256(
            keccak256(
                abi.encodePacked(
                    block.timestamp,
                    block.coinbase,
                    blockhash(block.number - 1)
                )
            )
        );

        // Use a custom alphabet for the gift card code
        string memory customAlphabet = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ";
        return seed.generateHumanReadableCode(customAlphabet);
    }

    constructor(address initialOwner) Ownable(initialOwner) {}

    function createGiftCard() external payable nonReentrant returns (uint256, bytes8) {
        require(msg.value > 0, "Deposit amount must be greater than 0");

        bytes8 redeemCode;
        bool codeExists;

        do {
            redeemCode = generateRandomCode();
            codeExists = isRedeemed[redeemCode];
        } while (codeExists);

        uint256 cardId = cardIdCounter.current();
        cardIdCounter.increment();

        giftCards.push(Card({
            cardId: cardId,
            redeemCode: redeemCode,
            creator: msg.sender,
            depositAmount: msg.value,
            redeemed: false
        }));

        isRedeemed[redeemCode] = false;

        emit GiftCardCreated(cardId, redeemCode, msg.sender, msg.value);
        return (cardId, redeemCode);
    }

    function redeemMind(bytes8 redeemCode) external nonReentrant notRedeemed(redeemCode) {
        uint256 cardIndex = _getCardIndexByRedeemCode(redeemCode);
        Card storage card = giftCards[cardIndex];

        card.redeemed = true;
        isRedeemed[redeemCode] = true;
        payable(msg.sender).transfer(card.depositAmount);

        emit EthRedeemed(card.cardId, msg.sender, redeemCode, card.depositAmount);
    }

   

    function getGiftCardBalanceAndStatus(uint256 cardId) external view returns (uint256 depositAmount, bool redeemed) {
        require(cardId < cardIdCounter.current(), "Invalid card ID");
        uint256 cardIndex = cardId;

        return (giftCards[cardIndex].depositAmount, giftCards[cardIndex].redeemed);
    }

    function withdrawBalance() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No balance to withdraw");
        payable(owner()).transfer(balance);
    }

    function _getCardIndexByRedeemCode(bytes8 redeemCode) internal view returns (uint256) {
        for (uint256 i = 0; i < giftCards.length; i++) {
            if (giftCards[i].redeemCode == redeemCode) {
                return i;
            }
        }
        revert("Redeem code not found");
    }
}

