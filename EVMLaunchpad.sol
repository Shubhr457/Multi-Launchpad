// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract Launchpad is Ownable, ReentrancyGuard {
    struct ProjectInfo {
        address admin;
        address tokenAddress;
        uint256 startTime;
        uint256 endTime;
        uint256 tokenPrice;     // Price in wei per token (1 ether = 10^18 wei)
        uint256 totalTokens;
        uint256 tokensSold;
        uint256 minPurchase;
        uint256 maxPurchase;
    }

    mapping(address => ProjectInfo) public projects;
    
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
    
    constructor() Ownable(msg.sender) {}

    function initializeProject(
        address _tokenAddress,
        uint256 _startTime,
        uint256 _endTime,
        uint256 _tokenPrice,
        uint256 _totalTokens,
        uint256 _minPurchase,
        uint256 _maxPurchase
    ) external {
        // Validate time parameters
        if (_endTime <= _startTime) revert InvalidTimeRange();
        if (_startTime <= block.timestamp) revert InvalidStartTime();

        ProjectInfo storage project = projects[_tokenAddress];
        
        // Initialize project state
        project.admin = msg.sender;
        project.tokenAddress = _tokenAddress;
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
    ) external payable nonReentrant {
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
        if (msg.value != price) revert("Incorrect payment amount");

        // Transfer tokens to buyer
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
        
        // Transfer collected ETH to admin
        uint256 balance = address(this).balance;
        if (balance > 0) {
            (bool sent, ) = project.admin.call{value: balance}("");
            require(sent, "Failed to send ETH");
        }
    }

    // View functions
    function getProjectInfo(address _tokenAddress) external view returns (ProjectInfo memory) {
        return projects[_tokenAddress];
    }

    receive() external payable {}
}