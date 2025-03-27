// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { OFT } from "@layerzerolabs/oft-evm/contracts/OFT.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract Token is OFT {

    address public creator;
    string public metadataURI; // Stores IPFS metadata JSON URI
    uint256 public constant _totalSupply = 1_000_000 ether;  // Fixed total supply
    // // Add mapping to track unique holders
    // mapping(address => bool) public isHolder;
    // uint256 public totalHolders;

    constructor(
        string memory _name,
        string memory _symbol,
        string memory _metadataURI,
        address _creator,
        address _lzEndpoint
    ) OFT(_name, _symbol, _lzEndpoint, _creator) Ownable(_creator) {
        initializeToken(_metadataURI, _creator);
    }

    function initializeToken(
        string memory _metadataURI,
        address _creator
    ) internal {
        creator = _creator;
        metadataURI = _metadataURI;
        _mint(msg.sender, _totalSupply);
    }
    
    function mint(address receiver, uint256 mintQty) external onlyOwner {
        _mint(receiver, mintQty);
    }


    // function burn(uint burnQty, address from) external {
    //     require(msg.sender == owner, "Burn can only be called by the owner");
    //     _burn(from, burnQty);
    // }

    // function _update(address from, address to, uint256 amount) internal virtual override{
    //     super._update(from, to, amount);

    //     if(from != address(0) && balanceOf(from) == 0){
    //         isHolder[from] = false;
    //         totalHolders--;
    //     }
        
    //     if(to != address(0) && !isHolder[to]){
    //         isHolder[to] = true;
    //         totalHolders++;
    //     }
    // }

    // function getTotalHolders() external view returns (uint256){
    //     return totalHolders;
    // }
}