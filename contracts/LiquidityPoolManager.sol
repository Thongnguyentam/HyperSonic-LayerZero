// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Token.sol";
import "./NativeLiquidityPool.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract LiquidityPoolManager is Ownable {
    NativeLiquidityPool public nativeLiquidityPool;

    event LiquidityPoolSet(address indexed pool);
    event LiquidityCreated(address indexed token, uint256 tokenAmount, uint256 ethAmount);

    constructor(address initialOwner) Ownable(initialOwner) {}

    function setLiquidityPool(address _liquidityPool) external onlyOwner {
        nativeLiquidityPool = NativeLiquidityPool(_liquidityPool);
        emit LiquidityPoolSet(_liquidityPool);
    }

    function createLiquidity(
        address _token,
        uint256 _tokenAmount,
        uint256 _ethAmount,
        address[] memory _contributors,
        uint256[] memory _contributorAmounts
    ) external onlyOwner {
        require(address(nativeLiquidityPool) != address(0), "Liquidity pool not set");

        Token(_token).approve(address(nativeLiquidityPool), _tokenAmount);
        nativeLiquidityPool.addLiquidity{ value: _ethAmount }(_token, _tokenAmount, _contributors, _contributorAmounts);

        emit LiquidityCreated(_token, _tokenAmount, _ethAmount);
    }
}
