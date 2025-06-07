// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

contract Auction {
    event NewBid(address indexed bidder, uint256 amount);
    event AuctionFinished(address indexed winner, uint256 bid);
    event Withdraw(address indexed aaa, uint256 amount);

    struct Bid {
        uint256 amount;
        bool withdrawn;
    }

    mapping (address => Bid) public bids;

    address public owner;
    uint256 public expiresAt;
    uint8 public fee;
    uint256 public minBid;

    address highestBidder;

    constructor(uint32 _duration, uint8 _fee, uint256 _minBid) {
        require(_duration <= 365 days, "duration should be less than 365 days (in seconds).");
        require(_fee <= 100, "fee should be in the 0-100 range.");

        owner = msg.sender;
        expiresAt = block.timestamp + _duration;
        fee = _fee;
        minBid = _minBid;
    }

    modifier auctionOpen() {
        require(block.timestamp < expiresAt, "The auction is closed.");
        _;
    }

    modifier auctionClosed() {
        require(block.timestamp >= expiresAt, "The auction is open.");
        _;
    }

    function bid() external payable auctionOpen {
        // The new bid should be greater than the minimum bid defined at contract creation.
        require(bids[msg.sender].amount + msg.value >= minBid, "The bid should be greater than the minimum bid.");

        // The new bid should be 5% higher than the winning bid.
        require(bids[msg.sender].amount + msg.value >= bids[highestBidder].amount * 105 / 100, "The bid should be 5% higher than the current winning bid.");

        // Add the value in case a previous bid was made
        bids[msg.sender].amount += msg.value;

        // If we are here, that means this is the new winning bid, save the bidder address.
        highestBidder = msg.sender;

        // If a valid bid is made within the last 10 minutes before expiring, extend the auction time 10 minutes
        if (expiresAt - block.timestamp <= 10 minutes) {
            expiresAt += 10 minutes;
        }

        emit NewBid(msg.sender, bids[msg.sender].amount);
    }

    function getWinningBid() external view returns (address, uint256) {
        return (highestBidder, bids[highestBidder].amount);
    }

    function withdraw() external payable auctionClosed {
        require(msg.sender != highestBidder, "Winner cannot withdraw funds.");
        require(bids[msg.sender].withdrawn != true, "Funds already withdrawn.");
        require(bids[msg.sender].amount > 0, "No funds to withdrawn.");

        // Send back funds minus a fee.
        uint256 amount = bids[msg.sender].amount * (100 - fee) / 100;
        (bool sent,) = payable(msg.sender).call{value: amount}("");
        require(sent, "Failed to send funds.");

        // Mark this bid as withdrawn to avoid double spending.
        bids[msg.sender].withdrawn = true;

        emit Withdraw(msg.sender, amount);
    }
}