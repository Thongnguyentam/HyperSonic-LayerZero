// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Token } from "./Token.sol";
import "./NativeLiquidityPool.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract TokenSaleManager is Ownable {
    uint256 public constant TARGET = 3 ether;
    uint256 public constant TOKEN_LIMIT = 500_000 ether;
    uint constant BASE_REWARD_PERCENTAGE = 3; // 3% reward

    struct TokenSale {
        address token;
        string name;
        string symbol;
        string metadataURI;
        address creator;
        uint256 sold;
        uint256 raised;
        bool isOpen;
        bool isLiquidityCreated;
        bool isOriginChain; // Whether this chain originated the token
    }

    // Storage for token sales
    uint256 public totalTokens;
    address[] public tokens;
    mapping(string => address) public tokenBySymbol; // Maps token symbol to token address
    mapping(address => TokenSale) public tokenToSale;
    mapping(address => mapping(address => uint256)) public userTokenContributions;
    mapping(address => mapping(address => uint256)) public userEthContributions;
    mapping(address => mapping(address => bool)) public hasClaimedReward;
    mapping(address => address[]) public tokenContributors;

    // External contracts
    address public factoryAddress;
    NativeLiquidityPool public nativeLiquidityPool;
    
    event Created(address indexed token, string symbol, bool isOriginChain);
    event RewardClaimed(address indexed user, address indexed token, uint256 amount);
    event LiquidityCreated(address indexed token, string symbol);
    
    constructor(address _factory) Ownable(msg.sender) {
        factoryAddress = _factory;
    }
    
    modifier onlyFactory() {
        require(msg.sender == factoryAddress, "Only factory can call");
        _;
    }

    function setLiquidityPool(address _liquidityPool) external onlyOwner {
        nativeLiquidityPool = NativeLiquidityPool(_liquidityPool);
    }
    
    function setFactory(address _factory) external onlyOwner {
        factoryAddress = _factory;
    }

    function registerToken(
        address _token,
        string memory _name,
        string memory _symbol,
        string memory _metadataURI,
        address _creator,
        bool _isOriginChain
    ) external onlyFactory returns (bool) {
        require(tokenBySymbol[_symbol] == address(0), "Token already exists");
        
        // Add token to list and mappings
        tokens.push(_token);
        totalTokens++;
        tokenBySymbol[_symbol] = _token;

        TokenSale memory sale = TokenSale(
            _token,
            _name,
            _symbol,
            _metadataURI,
            _creator,
            0,
            0,
            _isOriginChain, // Only open on origin chain
            false,
            _isOriginChain
        );
        tokenToSale[_token] = sale;
        
        emit Created(_token, _symbol, _isOriginChain);
        return true;
    }

    function buy(address _token, uint256 _amount) external payable {
        TokenSale storage sale = tokenToSale[_token];
        require(sale.isOriginChain, "Can only buy on origin chain");
        require(sale.token != address(0) && sale.isOpen, "!available");
        require(_amount >= 1 ether && _amount <= 10000 ether, "!amount");
        
        // Calculate the price if 1 token based upon total bought
        uint256 price = getCost(sale.sold) * (_amount / 10 ** 18);
        require(msg.value >= price, "Insufficient ETH received");

        // Record the contribution
        if (userTokenContributions[_token][msg.sender] == 0) {
            tokenContributors[_token].push(msg.sender); // Store unique contributors
        }
        userTokenContributions[_token][msg.sender] += _amount;
        userEthContributions[_token][msg.sender] += msg.value;
        
        // transfer tokens to the buyer's wallet
        Token(_token).transfer(msg.sender, _amount);
        
        // Update the sale
        sale.sold += _amount;
        sale.raised += msg.value;
        // Make sure fund raising goal isn't met, since if its met we don't want people to keep buy tokens
        if (sale.sold >= TOKEN_LIMIT || sale.raised >= TARGET){
            sale.isOpen = false;
            if (!sale.isLiquidityCreated){
                triggerLiquidityCreation(_token);
                sale.isLiquidityCreated = true;
            }
        }
    }

    function triggerLiquidityCreation(address _token) internal {
        TokenSale storage sale = tokenToSale[_token];
        require(!sale.isLiquidityCreated, "Liquidity already created"); 
        Token memeTokenCt = Token(_token);
        uint256 tokenBalance = memeTokenCt.balanceOf(address(this));

        (address[] memory contributors, uint256[] memory contributorAmounts) = getContributors(_token);

        memeTokenCt.approve(address(nativeLiquidityPool), tokenBalance);
        nativeLiquidityPool.addLiquidity{value: sale.raised}(_token, tokenBalance, contributors, contributorAmounts);
        
        sale.isLiquidityCreated = true;
        emit LiquidityCreated(_token, sale.symbol);
        
        // Notify Factory to inform other chains
        if (sale.isOriginChain) {
            notifyLiquidityCreated(sale.symbol);
        }
    }

    function notifyLiquidityCreated(string memory _symbol) internal {
        // Call Factory to notify peer chains
        (bool success, ) = factoryAddress.call(
            abi.encodeWithSignature(
                "notifyPeerChainsLiquidityCreated(string)",
                _symbol
            )
        );
        require(success, "Failed to notify Factory");
    }

    function calculateReward(address _token, address user) public view returns (uint256) {
        if (!tokenToSale[_token].isLiquidityCreated || 
            hasClaimedReward[_token][user] ||
            userTokenContributions[_token][user] == 0) {
            return 0;
        }

        uint256 userTokens = userTokenContributions[_token][user];
        TokenSale storage sale = tokenToSale[_token];
        return (sale.raised * BASE_REWARD_PERCENTAGE * userTokens) / (sale.sold * 100);
    }
 
    function claimReward(address _token) public {
        require(tokenToSale[_token].isLiquidityCreated, "Liquidity not created yet");
        require(!hasClaimedReward[_token][msg.sender], "Reward already claimed");
        require(userTokenContributions[_token][msg.sender] > 0, "No contribution found");

        uint256 reward = calculateReward(_token, msg.sender);
        require(reward > 0, "No reward available");

        hasClaimedReward[_token][msg.sender] = true; 
        Token(_token).mint(msg.sender, reward); // distribute token to LPs

        emit RewardClaimed(msg.sender, _token, reward);
    }

    function setLiquidityCreated(string memory _symbol) external onlyFactory {
        address tokenAddress = tokenBySymbol[_symbol];
        require(tokenAddress != address(0), "Token does not exist");
        
        TokenSale storage sale = tokenToSale[tokenAddress];
        require(!sale.isOriginChain, "Must not be origin chain");
        
        sale.isLiquidityCreated = true;
    }

    function getCost(uint256 _sold) public pure returns(uint256) {
        uint256 floor = 0.0001 ether; // starting price of a token
        uint256 step = 0.0001 ether; // each time increase by this amount in price
        uint256 increment = 10000 ether;

        uint256 cost = (step * (_sold / increment)) + floor;
        return cost;
    }

    function getContributors(address _token) public view returns (address[] memory, uint256[] memory) {
        address[] memory contributors = tokenContributors[_token];
        uint256[] memory contributions = new uint256[](contributors.length);

        for (uint256 i = 0; i < contributors.length; i++) {
            contributions[i] = userEthContributions[_token][contributors[i]];
        }

        return (contributors, contributions);
    }

    function getPriceForTokens(address _token, uint256 _amount) public view returns (uint256) {
        TokenSale storage sale = tokenToSale[_token];
        require(_amount >= 1 ether && _amount <= 10000 ether, "!amount");
        require(sale.isOpen, "!available");

        return getCost(sale.sold) * (_amount / 10 ** 18);
    }
    
    function getTokenSale(uint256 _index) external view returns (TokenSale memory) {
        require(_index < tokens.length, "Index out of bounds");
        return tokenToSale[tokens[_index]];
    }
    
    function withdraw(uint256 _amount) external onlyOwner {
        (bool success, ) = payable(owner()).call{value: _amount}("");
        require(success, "TokenSaleManager: ETH transfer failed");
    }
} 