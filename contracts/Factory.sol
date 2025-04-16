// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Token } from "./Token.sol";
import "./NativeLiquidityPool.sol";
import "./CrossChainMessenger.sol";
import "./TokenSaleManager.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { OptionsBuilder } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import { OAppOptionsType3, EnforcedOptionParam } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OAppOptionsType3.sol";

contract Factory is Ownable {
    uint256 public immutable fee;
    uint32 public immutable chainId; // Chain identifier
    address public immutable lzEndpoint;
    
    // Process tracking for cross-chain messages
    mapping(bytes32 => bool) public processedMessages; // Track processed cross-chain messages

    // External contracts
    TokenSaleManager public tokenSaleManager;
    CrossChainMessenger public crossChainMessenger;
    
    event TokenCreatedOnOtherChain(address indexed token, string symbol, uint32 indexed chainId);
    event TokensBridged(address indexed token, string symbol, address indexed user, uint256 amount, uint32 targetChainId);
    event TokensReceived(address indexed token, string symbol, address indexed user, uint256 amount, uint32 sourceChainId);
    event LiquidityCreatedNotified(string symbol, uint32 sourceChainId);

    constructor(uint256 _fee, uint32 _chainId, address _lzEndpoint) Ownable(msg.sender) {
        fee = _fee;
        chainId = _chainId;
        lzEndpoint = _lzEndpoint;
    }

    function setTokenSaleManager(address _manager) external onlyOwner {
        tokenSaleManager = TokenSaleManager(_manager);
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
        if (_creator == address(0)) {
            _creator = msg.sender;
        }

        // Create token on this chain with full supply since we're the origin
        Token token = new Token(
            _creator,
            _name,
            _symbol,
            _metadataURI,
            tokenSaleManager.TOKEN_LIMIT(), // Mint full supply since we're the origin chain
            lzEndpoint,
            address(tokenSaleManager)
        );

        // Register token with the TokenSaleManager
        tokenSaleManager.registerToken(
            address(token),
            _name,
            _symbol,
            _metadataURI,
            _creator,
            true // This is the origin chain for this token
        );

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
            address(tokenSaleManager)
        );

        // Register token with the TokenSaleManager
        tokenSaleManager.registerToken(
            address(token),
            _name,
            _symbol,
            _metadataURI,
            _creator,
            false // This is not the origin chain for this token
        );

        emit TokenCreatedOnOtherChain(address(token), _symbol, _sourceChainId);
    }

    function bridgeTokens(
        string memory _symbol,
        uint256 _amount,
        uint32 targetChainId
    ) external {
        require(_amount > 0, "Amount must be greater than 0");
        
        address tokenAddress = tokenSaleManager.tokenBySymbol(_symbol);
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

        address tokenAddress = tokenSaleManager.tokenBySymbol(_symbol);
        require(tokenAddress != address(0), "Token does not exist");

        // Mint tokens on this chain
        Token(tokenAddress).mint(_recipient, _amount);

        emit TokensReceived(tokenAddress, _symbol, _recipient, _amount, _sourceChainId);
    }

    function handleLiquidityCreatedOnOtherChain(
        string memory _symbol,
        uint32 _sourceChainId,
        bytes32 _messageId
    ) external {
        require(msg.sender == address(crossChainMessenger), "Only messenger can call");
        require(!processedMessages[_messageId], "Message already processed");
        processedMessages[_messageId] = true;

        // Notify the token sale manager that liquidity was created
        tokenSaleManager.setLiquidityCreated(_symbol);
        
        emit LiquidityCreatedNotified(_symbol, _sourceChainId);
    }

    function notifyPeerChainsLiquidityCreated(string memory _symbol) external {
        require(msg.sender == address(tokenSaleManager), "Only token sale manager can call");
        
        // Send notification to all peer chains
        uint32[] memory peers = crossChainMessenger.getPeerChainIds();
        for (uint i = 0; i < peers.length; i++) {
            crossChainMessenger.sendLiquidityCreatedToOtherChain(
                peers[i],
                _symbol
            );
        }
    }

    function withdraw(uint256 _amount) external onlyOwner {
        (bool success, ) = payable(owner()).call{value: _amount}("");
        require(success, "Factory: ETH transfer failed");
    }
} 