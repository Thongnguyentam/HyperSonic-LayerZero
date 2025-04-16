// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { OFT } from "@layerzerolabs/oft-evm/contracts/OFT.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract Token is OFT {
    address public creator;
    string public metadataURI;

    constructor(
        address _creator,
        string memory _name,
        string memory _symbol,
        string memory _metadataURI,
        uint256 _totalSupply,
        address _lzEndpoint,
        address _delegate
    ) OFT(_name, _symbol, _lzEndpoint, _delegate) Ownable(_delegate) {
        creator = _creator;
        metadataURI = _metadataURI;
        if (_totalSupply > 0) {
            _mint(msg.sender, _totalSupply);
        }
    }

    // Override mint to add owner check
    function mint(address receiver, uint256 mintQty) external {
        require(msg.sender == owner(), "Mint can only be called by the owner");
        _mint(receiver, mintQty);
    }

    // Override burn from ERC20Burnable to add owner check
    function burn(uint256 amount) public virtual {
        require(msg.sender == owner() || msg.sender == _msgSender(), "Not authorized to burn");
        _burn(_msgSender(), amount);
    }

    // Override burnFrom to add owner check
    function burnFrom(address account, uint256 amount) public virtual {
        require(msg.sender == owner() || msg.sender == account, "Not authorized to burn");
        _spendAllowance(account, _msgSender(), amount);
        _burn(account, amount);
    }
}