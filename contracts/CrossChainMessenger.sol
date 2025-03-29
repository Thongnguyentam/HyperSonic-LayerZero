// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { OApp, Origin, MessagingFee } from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import "./BaseContract.sol";
import "hardhat/console.sol";
contract CrossChainMessenger is BaseContract, OApp {
    event TokenLaunchedOnRemoteChain(uint32 indexed dstEid, string name, string symbol);
    event TokenCreatedOnRemoteChain(string name, string symbol, address creator);

    address public factory;

    constructor(uint256 _fee, address _lzEndpoint) BaseContract(_fee, _lzEndpoint) OApp(_lzEndpoint, tx.origin) {}

    function setFactory(address _factory) external onlyOwner {
        factory = _factory;
    }

    function quote(
        uint32 _dstEid,
        string memory _name,
        string memory _symbol,
        string memory _metadataURI,
        address _creator,
        bytes calldata _options,
        bool _payInLzToken
    ) public view returns (uint256 nativeFee, uint256 lzTokenFee) {
        bytes memory payload = abi.encode(_name, _symbol, _metadataURI, _creator);
        MessagingFee memory crosschainFee = _quote(_dstEid, payload, _options, _payInLzToken);
        return (crosschainFee.nativeFee, crosschainFee.lzTokenFee);
    }

    function sendLaunchToRemoteChain(
        uint32 _dstEid,
        string calldata _name,
        string calldata _symbol,
        string calldata _metadataURI,
        address _creator,
        bytes calldata _options
    ) external payable {
        (uint256 nativeFee, ) = quote(_dstEid, _name, _symbol, _metadataURI, _creator, _options, true);
        require(msg.value >= nativeFee, "Insufficient fee");
        bytes memory payload = abi.encode(_name, _symbol, _metadataURI, _creator);
        _lzSend(_dstEid, payload, _options, MessagingFee(msg.value, 0), payable(msg.sender));
        emit TokenLaunchedOnRemoteChain(_dstEid, _name, _symbol);
    }

    function _lzReceive(
        Origin calldata /*_origin*/,
        bytes32 /*_guid*/,
        bytes calldata payload,
        address /*_executor*/,
        bytes calldata /*_extraData*/
    ) internal override {
        (string memory _name, string memory _symbol, string memory _metadataURI, address _creator) = abi.decode(
            payload,
            (string, string, string, address)
        );

        // Call the factory to create the token
        if (factory != address(0)) {
            IFactory(factory).createTokenOnRemoteChain(_name, _symbol, _metadataURI, _creator);
            emit TokenCreatedOnRemoteChain(_name, _symbol, _creator);
        }
    }
}

interface IFactory {
    function createTokenOnRemoteChain(
        string memory _name,
        string memory _symbol,
        string memory _metadataURI,
        address _creator
    ) external;
}
