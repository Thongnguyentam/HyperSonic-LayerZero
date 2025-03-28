// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Token.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract TokenSaleManager is Ownable {
    uint256 public constant TARGET = 3 ether;
    uint256 public constant TOKEN_LIMIT = 500_000 ether;
    uint256 public constant BASE_REWARD_PERCENTAGE = 3; // 3% reward

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

    mapping(address => TokenSale) public tokenToSale;
    mapping(address => mapping(address => uint256)) public userTokenContributions;
    mapping(address => mapping(address => uint256)) public userEthContributions;
    mapping(address => mapping(address => bool)) public hasClaimedReward;
    mapping(address => address[]) public tokenContributors;
    address[] public tokens;

    event TokenSaleCreated(address indexed token, string name, address creator);
    event TokensBought(address indexed token, address buyer, uint256 amount);
    event RewardClaimed(address indexed token, address user, uint256 amount);

    constructor(address initialOwner) Ownable(initialOwner) {}

    function createTokenSale(
        address _token,
        string memory _name,
        string memory _metadataURI,
        address _creator
    ) external onlyOwner {
        tokens.push(_token);
        tokenToSale[_token] = TokenSale(_token, _name, _metadataURI, _creator, 0, 0, true, false);
        emit TokenSaleCreated(_token, _name, _creator);
    }

    function buyTokens(address _token, uint256 _amount, uint256 _price) external payable {
        TokenSale storage sale = tokenToSale[_token];
        require(sale.token != address(0) && sale.isOpen);
        require(_amount >= 1 ether && _amount <= 10000 ether);
        require(msg.value >= _price);

        if (userTokenContributions[_token][msg.sender] == 0) {
            tokenContributors[_token].push(msg.sender);
        }
        userTokenContributions[_token][msg.sender] += _amount;
        userEthContributions[_token][msg.sender] += msg.value;

        Token(_token).transfer(msg.sender, _amount);

        sale.sold += _amount;
        sale.raised += msg.value;

        if (sale.sold >= TOKEN_LIMIT || sale.raised >= TARGET) {
            sale.isOpen = false;
        }

        emit TokensBought(_token, msg.sender, _amount);
    }

    function calculateReward(address _token, address user) public view returns (uint256) {
        if (
            !tokenToSale[_token].isLiquidityCreated ||
            hasClaimedReward[_token][user] ||
            userTokenContributions[_token][user] == 0
        ) {
            return 0;
        }

        uint256 userTokens = userTokenContributions[_token][user];
        TokenSale storage sale = tokenToSale[_token];
        return (sale.raised * BASE_REWARD_PERCENTAGE * userTokens) / (sale.sold * 100);
    }

    function claimReward(address _token) public {
        require(tokenToSale[_token].isLiquidityCreated);
        require(!hasClaimedReward[_token][msg.sender]);
        require(userTokenContributions[_token][msg.sender] > 0);

        uint256 reward = calculateReward(_token, msg.sender);
        require(reward > 0);

        hasClaimedReward[_token][msg.sender] = true;
        Token(_token).mint(msg.sender, reward);
        emit RewardClaimed(_token, msg.sender, reward);
    }

    function getCost(uint256 _sold) public pure returns (uint256) {
        uint256 floor = 0.0001 ether;
        uint256 step = 0.0001 ether;
        uint256 increment = 10000 ether;
        return (step * (_sold / increment)) + floor;
    }

    function getPriceForTokens(address _token, uint256 _amount) public view returns (uint256) {
        TokenSale storage sale = tokenToSale[_token];
        require(_amount >= 1 ether && _amount <= 10000 ether);
        require(sale.isOpen);
        return getCost(sale.sold) * (_amount / 10 ** 18);
    }

    function getContributors(address _token) public view returns (address[] memory, uint256[] memory) {
        address[] memory contributors = tokenContributors[_token];
        uint256[] memory contributions = new uint256[](contributors.length);

        for (uint256 i = 0; i < contributors.length; i++) {
            contributions[i] = userEthContributions[_token][contributors[i]];
        }

        return (contributors, contributions);
    }

    function getTokenSale(uint256 _index) public view returns (TokenSale memory) {
        require(_index < tokens.length);
        return tokenToSale[tokens[_index]];
    }

    function markLiquidityCreated(address _token) external onlyOwner {
        tokenToSale[_token].isLiquidityCreated = true;
    }
}
