// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Token } from "./Token.sol";
import "./NativeLiquidityPool.sol";
import "./CrossChainMessenger.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { OptionsBuilder } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import { OAppOptionsType3, EnforcedOptionParam } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OAppOptionsType3.sol";

contract Factory is Ownable {
    uint256 public constant TARGET = 3 ether;
    uint256 public constant TOKEN_LIMIT = 500_000 ether;
    
    uint constant BASE_REWARD_PERCENTAGE = 3; // 3% reward
    uint256 public immutable fee;
    uint32 public immutable chainId; // Chain identifier
    address public immutable lzEndpoint;

    uint256 public totalTokens;
    address[] public tokens;
    mapping(string => address) public tokenBySymbol; // Maps token symbol to token address
    mapping(address => TokenSale) public tokenToSale;
    mapping(address => mapping(address => uint256)) public userTokenContributions;
    mapping(address => mapping(address => uint256)) public userEthContributions;
    mapping(address => mapping(address => bool)) public hasClaimedReward;
    mapping(address => address[]) public tokenContributors;
    mapping(bytes32 => bool) public processedMessages; // Track processed cross-chain messages

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

    NativeLiquidityPool public nativeLiquidityPool;
    CrossChainMessenger public crossChainMessenger;
    
    event Created(address indexed token, string symbol, bool isOriginChain);
    event RewardClaimed(address indexed user, address indexed token, uint256 amount);
    event TokenCreatedOnOtherChain(address indexed token, string symbol, uint32 indexed chainId);
    event TokensBridged(address indexed token, string symbol, address indexed user, uint256 amount, uint32 targetChainId);
    event TokensReceived(address indexed token, string symbol, address indexed user, uint256 amount, uint32 sourceChainId);
    event LiquidityCreatedNotified(string symbol, uint32 sourceChainId);

    constructor(uint256 _fee, uint32 _chainId, address _lzEndpoint) Ownable(msg.sender) {
        fee = _fee;
        chainId = _chainId;
        lzEndpoint = _lzEndpoint;
    }

    function setLiquidityPool(address _liquidityPool) external onlyOwner {
        nativeLiquidityPool = NativeLiquidityPool(_liquidityPool);
    }

    function setCrossChainMessenger(address _messenger) external onlyOwner {
        crossChainMessenger = CrossChainMessenger(_messenger);
    }

    function create(
        string memory _name, 
        string memory _symbol,
        string memory _metadataURI,
        address _creator
    ) external payable {
        require(msg.value >= fee, "Creator fee not met");
        require(tokenBySymbol[_symbol] == address(0), "already exists");
        if (_creator == address(0)) {
            _creator = msg.sender;
        }

        // Create token on this chain with full supply since we're the origin
        Token token = new Token(
            _creator,
            _name,
            _symbol,
            _metadataURI,
            TOKEN_LIMIT, // Mint full supply since we're the origin chain
            lzEndpoint,
            address(this)
        );

        // Add token to list and mappings
        tokens.push(address(token));
        totalTokens++;
        tokenBySymbol[_symbol] = address(token);

        TokenSale memory sale = TokenSale(
            address(token),
            _name,
            _symbol,
            _metadataURI,
            _creator,
            0,
            0,
            true,
            false,
            true // This is the origin chain for this token
        );
        tokenToSale[address(token)] = sale;

        // Send message to all peer chains to create token
        uint32[] memory peers = crossChainMessenger.getPeerChainIds();
        uint256 msgValuePerChain = msg.value / peers.length;
        
        for (uint i = 0; i < peers.length; i++) {
            crossChainMessenger.sendCreateTokenToOtherChain{value: msgValuePerChain}(
                peers[i],
                _name,
                _symbol,
                _metadataURI,
                _creator
            );
        }

        emit Created(address(token), _symbol, true);
    }

    function handleTokenCreatedOnOtherChain(
        string memory _name,
        string memory _symbol,
        string memory _metadataURI,
        address _creator,
        uint32 _sourceChainId,
        bytes32 _messageId
    ) external {
        require(msg.sender == address(crossChainMessenger), "Only messenger can call");
        require(!processedMessages[_messageId], "Message already processed");
        processedMessages[_messageId] = true;
        
        Token token = new Token(
            _creator,
            _name,
            _symbol,
            _metadataURI,
            0, // No initial supply since we're not the origin chain
            lzEndpoint,
            address(this)
        );

        // Add token to list and mappings
        tokens.push(address(token));
        totalTokens++;
        tokenBySymbol[_symbol] = address(token);

        TokenSale memory sale = TokenSale(
            address(token),
            _name,
            _symbol,
            _metadataURI,
            _creator,
            0,
            0,
            false, // Not open for sale on non-origin chain
            false,
            false // This is not the origin chain for this token
        );
        tokenToSale[address(token)] = sale;

        emit TokenCreatedOnOtherChain(address(token), _symbol, _sourceChainId);
    }

    function bridgeTokens(
        string memory _symbol,
        uint256 _amount,
        uint32 targetChainId
    ) external {
        require(_amount > 0, "Amount must be greater than 0");
        
        address tokenAddress = tokenBySymbol[_symbol];
        require(tokenAddress != address(0), "Token does not exist");
        
        Token token = Token(tokenAddress);
        require(token.balanceOf(msg.sender) >= _amount, "Insufficient balance");
        
        // Send message to target chain to mint tokens
        crossChainMessenger.sendBridgeTokensToOtherChain(
            targetChainId,
            _symbol,
            msg.sender,
            _amount
        );

        emit TokensBridged(tokenAddress, _symbol, msg.sender, _amount, targetChainId);
    }

    function handleBridgeTokensReceived(
        string memory _symbol,
        address _recipient,
        uint256 _amount,
        uint32 _sourceChainId,
        bytes32 _messageId
    ) external {
        require(msg.sender == address(crossChainMessenger), "Only messenger can call");
        require(!processedMessages[_messageId], "Message already processed");
        processedMessages[_messageId] = true;

        address tokenAddress = tokenBySymbol[_symbol];
        require(tokenAddress != address(0), "Token does not exist");

        // Mint tokens on this chain
        Token(tokenAddress).mint(_recipient, _amount);

        emit TokensReceived(tokenAddress, _symbol, _recipient, _amount, _sourceChainId);
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

        // After liquidity is created, notify all peer chains
        if (sale.isOriginChain) {
            uint32[] memory peers = crossChainMessenger.getPeerChainIds();
            for (uint i = 0; i < peers.length; i++) {
                crossChainMessenger.sendLiquidityCreatedToOtherChain(
                    peers[i],
                    sale.symbol
                );
            }
        }
    }

    function calculateReward(address _token, address user) internal view returns (uint256) {
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

    function withdraw(uint256 _amount) external onlyOwner {
        (bool success, ) = payable(owner()).call{value: _amount}("");
        require(success, "Factory: ETH transfer failed");
    }
    
    function getTokenSale(uint256 _index) external view returns (TokenSale memory) {
        require(_index < tokens.length, "Index out of bounds");
        return tokenToSale[tokens[_index]];
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

    function handleLiquidityCreatedOnOtherChain(
        string memory _symbol,
        uint32 _sourceChainId,
        bytes32 _messageId
    ) external {
        require(msg.sender == address(crossChainMessenger), "Only messenger can call");
        require(!processedMessages[_messageId], "Message already processed");
        processedMessages[_messageId] = true;

        address tokenAddress = tokenBySymbol[_symbol];
        require(tokenAddress != address(0), "Token does not exist");

        TokenSale storage sale = tokenToSale[tokenAddress];
        require(!sale.isOriginChain, "Must not be origin chain");
        
        sale.isLiquidityCreated = true;
        
        emit LiquidityCreatedNotified(_symbol, _sourceChainId);
    }
} 