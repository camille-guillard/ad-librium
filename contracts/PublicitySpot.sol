// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";

contract PublicitySpot is Ownable {
    uint256 public sellingPrice;    // Current price to occupy the ad spot
    uint256 public annualRate;      // Annual rate percentage (e.g. 410 means 4.10%)
    address public currentUser;     // The current user who controls the ad spot
    uint256 public endTime;         // Timestamp when the current ad spot ownership ends
    uint256 public purchasedPrice;  // purchased price by the current user
    uint256 public currentFuel;        // Total funds added by the current user to extend duration

    string private currentImage; // Ad image link (private, retrievable via getter)

    mapping(address => uint256) public balances; // Stores refunds for previous users

    // Custom errors for gas-efficient revert reasons
    error InvalidAmount();
    error NotCurrentUser();
    error AdSpotExpired();
    error NoFundsToWithdraw();

    // Events
    event PublicitySpotBought(address indexed user, uint256 amount, string image);
    event ImageUpdated(address indexed user, string newImage);
    event PublicityRefunded(address indexed user, uint256 refundAmount);
    event FundsAdded(address indexed user, uint256 additionalAmount);
    event FundsClaimed(address indexed user, uint256 claimedAmount);
    event SellingPriceUpdated(address indexed user, uint256 newPrice);

    // Restricts function access to the current ad spot holder
    modifier onlyCurrentUser() {
        if (msg.sender != currentUser) revert NotCurrentUser();
        _;
    }

    // Contract initialization with base price and interest rate
    constructor(uint256 _sellingPrice, uint256 _annualRate) Ownable(msg.sender) {
        if (_sellingPrice == 0 || _annualRate == 0) revert InvalidAmount();
        sellingPrice = _sellingPrice;
        annualRate = _annualRate;
    }

    // Main function to acquire or takeover the ad spot
    function buyPublicitySpot(string memory imageLink, uint256 newSellingPrice) external payable {
        if (msg.value < sellingPrice) revert InvalidAmount();
        if (newSellingPrice < 0) revert InvalidAmount();

        // Refund previous user if necessary
        if (currentUser != address(0)) {
            uint256 refundAmount = refundCurrentUser();
            emit PublicityRefunded(currentUser, refundAmount);
        }

        currentUser = msg.sender;
        purchasedPrice = sellingPrice;
        currentFuel = 0;
        currentImage = imageLink;
        sellingPrice = newSellingPrice;
        endTime = block.timestamp;

        emit PublicitySpotBought(msg.sender, msg.value, imageLink);
    }

    // Allows current user to extend their ad time by sending additional funds
    function addFuel() external payable onlyCurrentUser {
        currentFuel += msg.value;
        uint256 addedDuration = calculateDuration(msg.value, sellingPrice);
        endTime += addedDuration;

        emit FundsAdded(msg.sender, msg.value);
    }

    // Internal logic to compute refund amount based on unused time
    function refundCurrentUser() internal returns (uint256) {
        if (block.timestamp >= endTime) return 0;

        uint256 remaining = endTime - block.timestamp;
        uint256 total = calculateDuration(currentFuel, sellingPrice);
        uint256 refundFuelAmount = (remaining * currentFuel) / total;

        balances[currentUser] += refundFuelAmount;
        return refundFuelAmount;
    }

    function calculateDuration(uint256 amountPaid, uint256 sellPrice) internal view returns (uint256) {
        return (amountPaid * 365 days * 100) / (sellPrice * (annualRate / 100));
    }

    // Allows the user to change their ad image
    function updateImage(string memory newImage) external onlyCurrentUser {
        if (getRemainingTime() == 0) revert AdSpotExpired();
        currentImage = newImage;
        emit ImageUpdated(msg.sender, newImage);
    }

    // Lets the current user adjust the selling price; updates remaining time
    function updateSellingPrice(uint256 newPrice) external onlyCurrentUser {
        if (newPrice == 0) revert InvalidAmount();

        sellingPrice = newPrice;
        uint256 newTotal = calculateDuration(currentFuel, newPrice);
        endTime = block.timestamp + newTotal;

        emit SellingPriceUpdated(msg.sender, newPrice);
    }

    // Returns the remaining ad time in seconds
    function getRemainingTime() public view returns (uint256) {
        if (currentUser == address(0) || block.timestamp >= endTime) return 0;
        return endTime - block.timestamp;
    }

    // Owner can withdraw funds except for what is owed to the current user
    function withdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        uint256 valueRemaining = 0;

        if (block.timestamp < endTime) {
            uint256 remaining = getRemainingTime();
            uint256 total = calculateDuration(currentFuel, sellingPrice);
            valueRemaining = (remaining * currentFuel) / total;
        }

        uint256 amountToWithdraw = balance - valueRemaining;
        if (amountToWithdraw == 0) revert NoFundsToWithdraw();
        payable(owner()).transfer(amountToWithdraw);
    }

    // Allows a previous user to claim their refund
    function claim() external {
        uint256 amount = balances[msg.sender];
        if (amount == 0) revert InvalidAmount();

        balances[msg.sender] = 0;
        payable(msg.sender).transfer(amount);
        emit FundsClaimed(msg.sender, amount);
    }

    // Public getter: returns the ad image only if still active
    function getCurrentImage() external view returns (string memory) {
        return getRemainingTime() > 0 ? currentImage : "";
    }
}
