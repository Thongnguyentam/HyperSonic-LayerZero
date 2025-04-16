// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { OApp, Origin, MessagingFee, MessagingReceipt } from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
// Comment out OAppOptionsType3 since we're not using enforced options for now
// import { OAppOptionsType3 } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OAppOptionsType3.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Factory } from "./Factory.sol";

// Remove OAppOptionsType3 from inheritance
contract CrossChainMessenger is OApp {
    Factory public immutable factory;
    
    // Message types for different operations
    uint16 public constant MSG_TYPE_CREATE_TOKEN = 1;
    uint16 public constant MSG_TYPE_BRIDGE_TOKENS = 2;
    uint16 public constant MSG_TYPE_LIQUIDITY_CREATED = 3;

    // Track connected peer chains
    uint32[] private peerChainIds;
    mapping(uint32 => bool) private isPeerChain;
    
    event MessageSentToChain(
        bytes32 indexed guid,
        address indexed sender,
        uint32 indexed targetChainId,
        bytes data
    );
    
    event MessageReceivedFromChain(
        address indexed sender,
        uint32 indexed sourceChainId,
        bytes data
    );

    event PeerChainAdded(uint32 indexed chainId);
    event PeerChainRemoved(uint32 indexed chainId);
    
    constructor(
        address _lzEndpoint,
        address _owner,
        address _factory
    ) OApp(_lzEndpoint, _owner) Ownable(_owner) {
        factory = Factory(_factory);
    }

    modifier onlyFactory() {
        require(msg.sender == address(factory), "Only factory can call");
        _;
    }

    /**
     * @notice Add a new peer chain ID
     * @param chainId The chain ID to add
     */
    function addPeerChain(uint32 chainId) external onlyOwner {
        require(!isPeerChain[chainId], "Chain already added");
        peerChainIds.push(chainId);
        isPeerChain[chainId] = true;
        emit PeerChainAdded(chainId);
    }

    /**
     * @notice Remove a peer chain ID
     * @param chainId The chain ID to remove
     */
    function removePeerChain(uint32 chainId) external onlyOwner {
        require(isPeerChain[chainId], "Chain not found");
        
        // Find and remove the chain ID from the array
        for (uint i = 0; i < peerChainIds.length; i++) {
            if (peerChainIds[i] == chainId) {
                // Move the last element to this position and pop
                peerChainIds[i] = peerChainIds[peerChainIds.length - 1];
                peerChainIds.pop();
                break;
            }
        }
        
        isPeerChain[chainId] = false;
        emit PeerChainRemoved(chainId);
    }

    /**
     * @notice Get all peer chain IDs
     * @return Array of peer chain IDs
     */
    function getPeerChainIds() external view returns (uint32[] memory) {
        return peerChainIds;
    }

    /**
     * @notice Check if a chain ID is a peer
     * @param chainId The chain ID to check
     * @return bool True if the chain is a peer
     */
    function isPeer(uint32 chainId) external view returns (bool) {
        return isPeerChain[chainId];
    }

    /**
     * @notice Sends a message to create a token on another chain
     * @param _dstEid The target chain ID
     * @param _name Token name
     * @param _symbol Token symbol
     * @param _metadataURI Token metadata URI
     * @param _creator Token creator address
     */
    function sendCreateTokenToOtherChain(
        uint32 _dstEid,
        string memory _name,
        string memory _symbol,
        string memory _metadataURI,
        address _creator
    ) external payable onlyFactory {
        bytes32 messageId = keccak256(abi.encodePacked(
            block.timestamp,
            msg.sender,
            _name,
            _symbol,
            _creator
        ));

        // Encode the message data
        bytes memory payload = abi.encode(
            MSG_TYPE_CREATE_TOKEN,
            messageId,
            _name,
            _symbol,
            _metadataURI,
            _creator
        );

        // Instead of getting enforced options, just use empty options
        bytes memory options = "";

        // Send message to other chain
        MessagingReceipt memory receipt = _lzSend(
            _dstEid,
            payload,
            options,
            MessagingFee(msg.value, 0),
            payable(_creator)
        );
        
        emit MessageSentToChain(receipt.guid, msg.sender, _dstEid, payload);
    }

    /**
     * @notice Sends a message to bridge tokens to another chain
     * @param _dstEid The target chain ID
     * @param _symbol Token symbol
     * @param _recipient Recipient address
     * @param _amount Amount of tokens
     */ 
    function sendBridgeTokensToOtherChain(
        uint32 _dstEid,
        string memory _symbol,
        address _recipient,
        uint256 _amount
    ) external payable onlyFactory {
        bytes32 messageId = keccak256(abi.encodePacked(
            block.timestamp,
            msg.sender,
            _symbol,
            _recipient,
            _amount
        ));

        bytes memory payload = abi.encode(
            MSG_TYPE_BRIDGE_TOKENS,
            messageId,
            _symbol,
            _recipient,
            _amount
        );

        // Get enforced options for this message type
        bytes memory options = "";
        
        MessagingReceipt memory receipt = _lzSend(
            _dstEid,
            payload,
            options,
            MessagingFee(msg.value, 0),
            payable(msg.sender)
        );
        
        emit MessageSentToChain(receipt.guid, msg.sender, _dstEid, payload);
    }
    
    // /**
    //  * @notice Sends a message to notify other chains that liquidity has been created
    //  * @param targetChainId The target chain ID
    //  * @param _symbol Token symbol
    //  */
    function sendLiquidityCreatedToOtherChain(
        uint32 _dstEid,
        string memory _symbol
    ) external payable onlyFactory {
        bytes32 messageId = keccak256(abi.encodePacked(
            block.timestamp,
            msg.sender,
            _symbol,
            "LIQUIDITY_CREATED"
        ));

        bytes memory payload = abi.encode(
            MSG_TYPE_LIQUIDITY_CREATED,
            messageId,
            _symbol
        );

        // Get enforced options for this message type
        bytes memory options = "";
        
        MessagingReceipt memory receipt = _lzSend(
            _dstEid,
            payload,
            options,
            MessagingFee(msg.value, 0),
            payable(msg.sender)
        );
        
        emit MessageSentToChain(receipt.guid, msg.sender, _dstEid, payload);
    }

    /**
     * @notice Helper function to convert bytes32 to address
     * @param _bytes32 The bytes32 to convert
     */
    function _bytes32ToAddress(bytes32 _bytes32) internal pure returns (address) {
        return address(uint160(uint256(_bytes32)));
    }

    // Comment out enforced options helper since we're not using it
    // /**
    //  * @notice Helper function to get enforced options for a message type
    //  */
    // function _getEnforcedOptions(uint32 _dstEid, uint16 _msgType) internal view returns (bytes memory) {
    //     bytes memory enforcedOptions = enforcedOptions[_dstEid][_msgType];
    //     require(enforcedOptions.length > 0, "No enforced options set");
    //     return enforcedOptions;
    // }

    /**
     * @notice Processes messages received from other chains
     * @param _origin Origin information from the source chain
     * @param _guid Global unique identifier for the message
     * @param payload The message payload
     */
    function _lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata payload,
        address,  // Executor address
        bytes calldata  // Extra data
    ) internal override {
        (uint16 msgType) = abi.decode(payload, (uint16));
        
        if (msgType == MSG_TYPE_CREATE_TOKEN) {
            (
                ,
                bytes32 messageId,
                string memory name,
                string memory symbol,
                string memory metadataURI,
                address creator
            ) = abi.decode(payload, (uint16, bytes32, string, string, string, address));
            
            factory.handleTokenCreatedOnOtherChain(
                name,
                symbol,
                metadataURI,
                creator,
                _origin.srcEid,
                messageId
            );
        } else if (msgType == MSG_TYPE_BRIDGE_TOKENS) {
            (
                ,
                bytes32 messageId,
                string memory symbol,
                address recipient,
                uint256 amount
            ) = abi.decode(payload, (uint16, bytes32, string, address, uint256));
            
            factory.handleBridgeTokensReceived(
                symbol,
                recipient,
                amount,
                _origin.srcEid,
                messageId
            );
        } else if (msgType == MSG_TYPE_LIQUIDITY_CREATED) {
            (
                ,
                bytes32 messageId,
                string memory symbol
            ) = abi.decode(payload, (uint16, bytes32, string));
            
            factory.handleLiquidityCreatedOnOtherChain(
                symbol,
                _origin.srcEid,
                messageId
            );
        } else {
            revert("Invalid message type");
        }
        
        emit MessageReceivedFromChain(_bytes32ToAddress(_origin.sender), _origin.srcEid, payload);
    }
} 