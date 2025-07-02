// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract LuckyLoop is Ownable, ReentrancyGuard {
    using SafeMath for uint256;

    uint256 public constant MAX_ENTRIES = 100;
    uint256 public constant ENTRY_FEE = 0.01 ether;
    uint256 public constant PROFIT_PERCENT = 50;

    address public immutable prizePoolWallet = 0xdcbA84e0a9694C450aD9c385cf81C8bAc7C37Cc1;
    address public immutable profitWallet = 0x31Bd345293BB862A91393551ce0a0101efE5194;
    uint256 public currentRound;
    uint256 public entryCount;
    address[] public entries;
    address public winner;
    bool public roundActive;

    event EntryReceived(address indexed player, uint256 round, uint256 timestamp);
    event WinnerSelected(address indexed winner, uint256 round, uint256 prize, uint256 timestamp);
    event FundsSplit(uint256 prizeAmount, uint256 profitAmount, uint256 timestamp);

    constructor() Ownable(msg.sender) {
        currentRound = 1;
        roundActive = true;
        emit EntryReceived(msg.sender, currentRound, block.timestamp);
    }

    function enter() external payable nonReentrant {
        require(roundActive, "Round not active");
        require(msg.value == ENTRY_FEE, "Incorrect entry fee");
        require(entryCount < MAX_ENTRIES, "Round full");
        require(entries.length == 0 || entries[entries.length - 1] != msg.sender, "Already entered");

        entries.push(msg.sender);
        entryCount = entryCount.add(1);
        emit EntryReceived(msg.sender, currentRound, block.timestamp);

        uint256 prizeAmount = msg.value.mul(100 - PROFIT_PERCENT).div(100);
        uint256 profitAmount = msg.value.sub(prizeAmount);
        (bool sentPrize, ) = prizePoolWallet.call{value: prizeAmount}("");
        (bool sentProfit, ) = profitWallet.call{value: profitAmount}("");
        require(sentPrize && sentProfit, "Fund split failed");
        emit FundsSplit(prizeAmount, profitAmount, block.timestamp);

        if (entryCount == MAX_ENTRIES) {
            roundActive = false;
            selectWinner();
        }
    }

    function selectWinner() private {
        uint256 seed = uint256(keccak256(abi.encodePacked(
            block.prevrandao,
            block.timestamp,
            blockhash(block.number - 1),
            currentRound,
            entries.length
        )));
        uint256 index = seed % MAX_ENTRIES;
        winner = entries[index];
        uint256 prize = prizePoolWallet.balance;
        (bool sent, ) = winner.call{value: prize}("");
        require(sent, "Prize distribution failed");
        emit WinnerSelected(winner, currentRound, prize, block.timestamp);

        currentRound = currentRound.add(1);
        entryCount = 0;
        delete entries;
        roundActive = true;
    }

    function getEntries() external view returns (address[] memory) {
        return entries;
    }

    receive() external payable {}
}
