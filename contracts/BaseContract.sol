// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

contract BaseContract is Ownable {
    address public immutable lzEndpoint;
    uint256 public immutable fee;

    constructor(uint256 _fee, address _lzEndpoint) Ownable(msg.sender) {
        fee = _fee;
        lzEndpoint = _lzEndpoint;
    }

    function withdraw(uint256 _amount) external onlyOwner {
        (bool success, ) = payable(owner()).call{ value: _amount }("");
        require(success);
    }
}
