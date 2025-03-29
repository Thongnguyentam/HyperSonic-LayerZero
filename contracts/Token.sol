// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { OFT } from "@layerzerolabs/oft-evm/contracts/OFT.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import "hardhat/console.sol";

contract Token is OFT {

    address public creator;
    string public metadataURI; // Stores IPFS metadata JSON URI
    uint256 public constant _totalSupply = 1_000_000 ether;  // Fixed total supply
    uint32 public eid;
    constructor(
        string memory _name,
        string memory _symbol,
        address _creator,
        address _lzEndpoint
    ) OFT(_name, _symbol, _lzEndpoint, _creator) Ownable(_creator) { }

    function initializeToken(
        string memory _metadataURI,
        address _creator,
        uint32 _eid
    ) external {
        console.log("Initializing token");
        console.log("Token creator: ", _creator);
        console.log("Token eid: ", _eid);
        console.log("Token metadataURI: ", _metadataURI);
        eid = _eid;
        creator = _creator;
        metadataURI = _metadataURI;
        _credit(msg.sender, _totalSupply, _eid);
    }

    function mint(address receiver, uint256 mintQty) external onlyOwner {
        require(receiver != address(0), "Cannot mint to zero address");
        _credit(receiver, mintQty, eid);
    }

}