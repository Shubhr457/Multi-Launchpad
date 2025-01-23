// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract Launchpad is Ownable, ReentrancyGuard {
    struct ProjectInfo {
        address admin;
        address tokenAddress;
        address paymentToken; 
        uint256 startTime;
        uint256 endTime;
        uint256 tokenPrice; 
        uint256 totalTokens;
        uint256 tokensSold;
        uint256 minPurchase;
        uint256 maxPurchase;
    }

    mapping(address => ProjectInfo) projects;

    // Events
    event ProjectCreated(
        address indexed tokenAddress,
        address indexed admin,
        uint256 startTime,
        uint256 endTime
    );

    event TokensPurchased(
        address indexed buyer,
        address indexed tokenAddress,
        uint256 amount,
        uint256 cost
    );

    // Errors
    error SaleInactive();
    error BelowMinimum();
    error AboveMaximum();
    error InsufficientTokens();
    error InvalidTimeRange();
    error InvalidStartTime();
    error PaymentFailed();

    constructor() Ownable(msg.sender) {}

    function initializeProject(
        address _tokenAddress,
        address _paymentToken, 
        uint256 _startTime,
        uint256 _endTime,
        uint256 _tokenPrice,
        uint256 _totalTokens,
        uint256 _minPurchase,
        uint256 _maxPurchase
    ) external onlyOwner {
        // Validate time parameters
        if (_endTime <= _startTime) revert InvalidTimeRange();
        if (_startTime <= block.timestamp) revert InvalidStartTime();

        ProjectInfo storage project = projects[_tokenAddress];

        // Initialize project state
        project.admin = msg.sender;
        project.tokenAddress = _tokenAddress;
        project.paymentToken = _paymentToken;
        project.startTime = _startTime;
        project.endTime = _endTime;
        project.tokenPrice = _tokenPrice;
        project.totalTokens = _totalTokens;
        project.tokensSold = 0;
        project.minPurchase = _minPurchase;
        project.maxPurchase = _maxPurchase;

        // Transfer tokens to contract
        IERC20(_tokenAddress).transferFrom(
            msg.sender,
            address(this),
            _totalTokens
        );

        emit ProjectCreated(_tokenAddress, msg.sender, _startTime, _endTime);
    }

    function purchaseTokens(
        address _tokenAddress,
        uint256 _amount
    ) external nonReentrant onlyOwner{
        ProjectInfo storage project = projects[_tokenAddress];

        // Check if sale is active
        if (
            block.timestamp < project.startTime ||
            block.timestamp > project.endTime
        ) revert SaleInactive();

        // Validate purchase amount
        if (_amount < project.minPurchase) revert BelowMinimum();
        if (_amount > project.maxPurchase) revert AboveMaximum();
        if (project.tokensSold + _amount > project.totalTokens) revert InsufficientTokens();

        // Calculate price
        uint256 price = _amount * project.tokenPrice;

        // Transfer payment tokens from buyer to contract
        bool success = IERC20(project.paymentToken).transferFrom(
            msg.sender,
            address(this),
            price
        );
        if (!success) revert PaymentFailed();

        // Transfer purchased tokens to buyer
        IERC20(project.tokenAddress).transfer(msg.sender, _amount);

        // Update state
        project.tokensSold += _amount;

        emit TokensPurchased(msg.sender, _tokenAddress, _amount, price);
    }

    // Admin functions
    function withdrawFunds(address _tokenAddress) external {
        ProjectInfo storage project = projects[_tokenAddress];
        require(msg.sender == project.admin, "Not authorized");

        // Transfer remaining tokens back to admin
        uint256 remainingTokens = IERC20(_tokenAddress).balanceOf(address(this));
        if (remainingTokens > 0) {
            IERC20(_tokenAddress).transfer(project.admin, remainingTokens);
        }

        // Transfer collected payment tokens to admin
        uint256 paymentTokenBalance = IERC20(project.paymentToken).balanceOf(address(this));
        if (paymentTokenBalance > 0) {
            IERC20(project.paymentToken).transfer(project.admin, paymentTokenBalance);
        }
    }

    // View functions
    function getProjectInfo(address _tokenAddress) external view returns (ProjectInfo memory) {
        return projects[_tokenAddress];
    }
}
