// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Token.sol";
import "./TokenSaleManager.sol";
import "./CrossChainMessenger.sol";
import "./LiquidityPoolManager.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import { OApp, Origin, MessagingFee } from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import { MessagingReceipt } from "@layerzerolabs/oapp-evm/contracts/oapp/OAppSender.sol";
import "hardhat/console.sol";

contract Factory is Ownable {
    uint256 public constant TARGET = 3 ether;
    uint256 public constant TOKEN_LIMIT = 500_000 ether;
    uint256 public constant BASE_REWARD_PERCENTAGE = 3; // 3% reward

    // Pack related variables together to save gas
    uint256 public immutable fee;
    uint256 public totalTokens;
    address public immutable lzEndpoint;
    NativeLiquidityPool public nativeLiquidityPool;

    address[] public tokens;
    //mapping(string => address) public tokenBySymbol;
    mapping(address => TokenSale) public tokenToSale;
    mapping(address => mapping(address => uint256)) public userTokenContributions;
    mapping(address => mapping(address => uint256)) public userEthContributions;
    mapping(address => mapping(address => bool)) public hasClaimedReward;
    mapping(address => address[]) public tokenContributors;

    struct TokenSale {
        address token;
        string name;
        string metadataURI;
        address creator;
        uint256 sold;
        uint256 raised;
        bool isOpen;
        bool isLiquidityCreated;
    }

    TokenSaleManager public tokenSaleManager;
    CrossChainMessenger public crossChainMessenger;
    LiquidityPoolManager public liquidityPoolManager;

    constructor(uint256 _fee, address _lzEndpoint) Ownable(msg.sender) {
        fee = _fee;
        lzEndpoint = _lzEndpoint;
        tokenSaleManager = new TokenSaleManager(msg.sender);
        crossChainMessenger = new CrossChainMessenger(_fee, _lzEndpoint);
        liquidityPoolManager = new LiquidityPoolManager(msg.sender);

        // Set this contract as the factory for the messenger
        crossChainMessenger.setFactory(address(this));
    }

    function setLiquidityPool(address _liquidityPool) external onlyOwner {
        liquidityPoolManager.setLiquidityPool(_liquidityPool);
    }

    function _createToken(
        string memory _name,
        string memory _symbol,
        string memory _metadataURI,
        address _creator
    ) internal returns (address) {
        if (_creator == address(0)) {
            _creator = msg.sender;
        }

        Token token = new Token(_name, _symbol, _metadataURI, _creator, crossChainMessenger.lzEndpoint());
        address tokenAddress = address(token);
        totalTokens++;

        tokenSaleManager.createTokenSale(tokenAddress, _name, _metadataURI, _creator);
        return tokenAddress;
    }

    function create(
        string calldata _name,
        string calldata _symbol,
        string calldata _metadataURI,
        address _creator
    ) external payable {
        require(msg.value >= crossChainMessenger.fee());
        _createToken(_name, _symbol, _metadataURI, _creator);
    }

    function createTokenOnRemoteChain(
        string memory _name,
        string memory _symbol,
        string memory _metadataURI,
        address _creator
    ) external {
        require(msg.sender == address(crossChainMessenger), "Only messenger can call");
        _createToken(_name, _symbol, _metadataURI, _creator);
    }

    function buy(address _token, uint256 _amount) external payable {
        uint256 price = tokenSaleManager.getPriceForTokens(_token, _amount);
        tokenSaleManager.buyTokens(_token, _amount, price);
    }

    function triggerLiquidityCreation(address _token) internal {
        TokenSale memory sale = tokenToSale[_token];
        require(!sale.isLiquidityCreated);

        Token memeTokenCt = Token(_token);
        uint256 tokenBalance = memeTokenCt.balanceOf(address(this));

        (address[] memory contributors, uint256[] memory contributorAmounts) = tokenSaleManager.getContributors(_token);

        liquidityPoolManager.createLiquidity(_token, tokenBalance, sale.raised, contributors, contributorAmounts);
        tokenSaleManager.markLiquidityCreated(_token);
    }

    function calculateReward(address _token, address user) internal view returns (uint256) {
        if (
            !tokenToSale[_token].isLiquidityCreated ||
            hasClaimedReward[_token][user] ||
            userTokenContributions[_token][user] == 0
        ) {
            return 0;
        }

        uint256 userTokens = userTokenContributions[_token][user];
        TokenSale memory sale = tokenToSale[_token];
        return (sale.raised * BASE_REWARD_PERCENTAGE * userTokens) / (sale.sold * 100);
    }

    function claimReward(address _token) public {
        require(tokenToSale[_token].isLiquidityCreated);
        require(!hasClaimedReward[_token][msg.sender]);
        require(userTokenContributions[_token][msg.sender] > 0);

        uint256 reward = calculateReward(_token, msg.sender);
        require(reward > 0);

        hasClaimedReward[_token][msg.sender] = true;
        Token(_token).mint(msg.sender, reward); // distribute token to LPs
    }

    function withdraw(uint256 _amount) external onlyOwner {
        (bool success, ) = payable(owner()).call{ value: _amount }("");
        require(success);
    }

    function getTokenSale(uint256 _index) external view returns (TokenSale memory) {
        require(_index < tokens.length);
        return tokenToSale[tokens[_index]];
    }

    function getCost(uint256 _sold) internal pure returns (uint256) {
        uint256 floor = 0.0001 ether; // starting price of a token
        uint256 step = 0.0001 ether; // each time increase by this amount in price
        uint256 increment = 10000 ether;

        return (step * (_sold / increment)) + floor;
    }

    function getContributors(address _token) internal view returns (address[] memory, uint256[] memory) {
        address[] memory contributors = tokenContributors[_token];
        uint256[] memory contributions = new uint256[](contributors.length);

        for (uint256 i = 0; i < contributors.length; i++) {
            contributions[i] = userEthContributions[_token][contributors[i]];
        }

        return (contributors, contributions);
    }

    function getPriceForTokens(address _token, uint256 _amount) public view returns (uint256) {
        TokenSale memory sale = tokenToSale[_token];
        require(_amount >= 1 ether && _amount <= 10000 ether);
        require(sale.isOpen);

        return getCost(sale.sold) * (_amount / 10 ** 18);
    }

    // function getTokenBySymbol(string memory _symbol) public view returns (address) {
    //     return tokenBySymbol[_symbol];
    // }

    function quote(
        uint32 _dstEid,
        string memory _name,
        string memory _symbol,
        string memory _metadataURI,
        address _creator,
        bytes calldata _options,
        bool _payInLzToken
    ) public view returns (uint256 nativeFee, uint256 lzTokenFee) {
        return crossChainMessenger.quote(_dstEid, _name, _symbol, _metadataURI, _creator, _options, _payInLzToken);
    }

    function sendLaunchToRemoteChain(
        uint32 _dstEid,
        string calldata _name,
        string calldata _symbol,
        string calldata _metadataURI,
        address _creator,
        bytes calldata _options
    ) external payable {
        crossChainMessenger.sendLaunchToRemoteChain(_dstEid, _name, _symbol, _metadataURI, _creator, _options);
    }
}
