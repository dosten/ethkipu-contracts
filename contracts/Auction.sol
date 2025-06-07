// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

/**
 * @dev Auction contract
 */
contract Auction {
    event NewBid(address indexed account, uint256 amount);
    event Withdraw(address indexed account, uint256 amount);

    enum AuctionStatus { Closed, Open }

    struct Bid {
        uint256 amount;
        bool withdrawn;
    }

    mapping (address account => Bid bid) public bids;

    address public owner;
    uint256 public expiresAt;
    uint256 public fee;
    uint256 public minBid;

    address private _winningBidder;
    uint256 private _totalBid;
    uint256 private _totalWithdrawn;

    /**
     * @dev Defines the duration (in seconds), the fee (as percentage) and the minimum bid of the auction.
     */
    constructor(uint32 _duration, uint8 _fee, uint256 _minBid) {
        require(_duration <= 365 days, "duration should be less than 365 days (in seconds).");
        require(_fee <= 100, "fee should be in the 0-100 range.");

        owner = msg.sender;
        expiresAt = block.timestamp + _duration;
        fee = _fee;
        minBid = _minBid;
    }

    /**
     * @dev Reverts if it is not executed by the auction owner.
     */
    modifier onlyOwner() {
        require(msg.sender == owner, "Can only be executed by the auction owner.");
        _;
    }

    /**
     * @dev Reverts if the auction is closed.
     */
    modifier auctionOpen() {
        require(block.timestamp < expiresAt, "The auction is closed.");
        _;
    }

    /**
     * @dev Reverts if the auction is open.
     */
    modifier auctionClosed() {
        require(block.timestamp >= expiresAt, "The auction is open.");
        _;
    }

    /**
     * @dev Returns the auction status (closed = 0, open = 1).
     */
    function status() external view returns (AuctionStatus) {
        return block.timestamp < expiresAt ? AuctionStatus.Open : AuctionStatus.Closed;
    }

    /**
     * @dev Returns the current winning bid.
     *
     * NOTE: If the bid is closed, the winning bid is inmutable.
     */
    function winningBid() external view returns (address, uint256) {
        return (_winningBidder, bids[_winningBidder].amount);
    }

    /**
     * @dev Creates a new bid on this auction.
     *
     * If there was a previous bid for the same account, the previous one is replaced and the new one
     * is the sum of the value of the previous one + the value being bidded in this transaction.
     *
     * NOTE 1: The new bid should be 5% higher than the current winning bid.
     * NOTE 2: If the bid is made within the last 10 minutes before expiring, the auction time is extended 10 minutes.
     */
    function bid() external payable auctionOpen {
        // The new bid should be greater than the minimum bid defined at contract creation.
        require(bids[msg.sender].amount + msg.value >= minBid, "The bid should be greater than the minimum bid.");

        // The new bid should be 5% higher than the winning bid.
        require(bids[msg.sender].amount + msg.value >= bids[_winningBidder].amount * 105 / 100, "The bid should be 5% higher than the current winning bid.");

        // Add the value in case a previous bid was made
        bids[msg.sender].amount += msg.value;

        // If we are here, that means this is the new winning bid, save the bidder address.
        _winningBidder = msg.sender;

        // Track the total bid amount across all accounts
        _totalBid += msg.value;

        // If a valid bid is made within the last 10 minutes before expiring, extend the auction time 10 minutes
        if (expiresAt - block.timestamp <= 10 minutes) {
            expiresAt += 10 minutes;
        }

        emit NewBid(msg.sender, bids[msg.sender].amount);
    }

    /**
     * @dev Withdraw non-winning bids minus a fee after the auction is closed.
     */
    function withdraw() external payable auctionClosed {
        require(msg.sender != _winningBidder, "Winner cannot withdraw funds.");
        require(bids[msg.sender].withdrawn != true, "Funds already withdrawn.");
        require(bids[msg.sender].amount > 0, "No funds to withdrawn.");

        // Send back funds minus a fee.
        uint256 amount = bids[msg.sender].amount * (100 - fee) / 100;
        (bool sent,) = payable(msg.sender).call{value: amount}("");
        require(sent, "Failed to send funds.");

        // Mark this bid as withdrawn to avoid double spending.
        bids[msg.sender].withdrawn = true;
        _totalWithdrawn += bids[msg.sender].amount;

        emit Withdraw(msg.sender, amount);
    }

    /**
     * @dev Withdraw winning bid plus fees to owner's account after the auction is closed.
     *
     * NOTE: This function can be executed at any time, no need to wait for bidders to withdraw first.
     */
    function withdrawWinner() external payable onlyOwner auctionClosed {
        // Get actual balance as it can differ from what we are tracking inside the contract.
        uint256 _totalBalance = address(this).balance;

        // Get the winning bid amount as we need to withdraw it in full.
        uint256 _winningBid = bids[_winningBidder].amount;

        // Calculate amount to withdraw to owner's account.
        //
        // We need to send the following:
        //
        //  1. Full winning bid.
        //  2. Fee for non-winning bids.
        //  3. Any surplus from the difference between the real balance and the tracked balance.
        //
        // We can summarize those 3 requirements with the following formulas:
        //
        //  1. Get the total amount of funds not withdrawn yet: `_totalBid - _winningBid - _totalWithdrawn`
        //  2. Calculate the amount that should be sent back to bidders minus the fee
        //  3. Subtract the previous result to the real balance
        //
        // This way we can be sure that we are withdrawing the correct balance and keeping the required amount
        // to pay back to the remaining bidders that did not withdraw their funds yet.
        uint256 _amount = _totalBalance - (_totalBid - _winningBid - _totalWithdrawn) * (100 - fee) / 100;

        // This can revert in only two cases:
        //
        //  1. A bug makes `_amount < 0`. :(
        //  2. This function is executed again after a previous withdrawal. `_amount = 0`.
        require(_amount > 0, "No funds to withdraw.");

        // Send funds to owner.
        (bool sent,) = payable(owner).call{value: _amount}("");
        require(sent, "Failed to send funds.");
    }
}