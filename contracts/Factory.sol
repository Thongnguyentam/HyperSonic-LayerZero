// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Token.sol";
import "./NativeLiquidityPool.sol";
import { OApp, Origin, MessagingFee } from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { MessagingReceipt } from "@layerzerolabs/oapp-evm/contracts/oapp/OAppSender.sol";
import "hardhat/console.sol";
contract Factory is OApp {
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

    constructor(uint256 _fee, address _lzEndpoint) OApp(_lzEndpoint, msg.sender) Ownable(msg.sender) {
        fee = _fee;
        lzEndpoint = _lzEndpoint;
    }

    function setLiquidityPool(address _liquidityPool) external onlyOwner {
        nativeLiquidityPool = NativeLiquidityPool(_liquidityPool);
    }

    function _createToken(
        string memory _name, 
        string memory _symbol,
        string memory _metadataURI,
        address _creator
    ) internal returns (address) {
        // console.log("current contract:", address(this));
        // console.log("total tokens before creation:", totalTokens);
        // If creator is zero address, set it to msg.sender
        if (_creator == address(0)) {
            _creator = msg.sender;
        }

        // console.log("Attempting to create token with params:");
        // console.log("- creator:", _creator);
        // console.log("- name:", _name);
        // console.log("- symbol:", _symbol);
        // console.log("- metadataURI:", _metadataURI);
        // console.log("- lzEndpoint:", lzEndpoint);

        Token token = new Token(_name, _symbol,_metadataURI, _creator, lzEndpoint);

        address tokenAddress = address(token);
        // console.log("Token successfully created at:", tokenAddress);
        tokens.push(tokenAddress);
        totalTokens++;
        tokenToSale[tokenAddress] = TokenSale(
            tokenAddress,
            _name,
            _metadataURI,
            _creator,
            0, // sold
            0, // raised
            true, // isOpen
            false // isLiquidityCreated
        );
        
        return tokenAddress;
    }

    function create(
        string calldata _name,
        string calldata _symbol,
        string calldata _metadataURI,
        address _creator
    ) external payable {
        require(msg.value >= fee);
        _createToken(_name, _symbol, _metadataURI, _creator);
    }

    function buy(address _token, uint256 _amount) external payable {
        TokenSale storage sale = tokenToSale[_token];
        require(sale.token != address(0) && sale.isOpen);
        require(_amount >= 1 ether && _amount <= 10000 ether);
        
        uint256 price = getCost(sale.sold) * (_amount / 1e18);
        require(msg.value >= price);

        // Record the contribution
        if (userTokenContributions[_token][msg.sender] == 0) {
            tokenContributors[_token].push(msg.sender); // Store unique contributors
        }
        userTokenContributions[_token][msg.sender] += _amount;
        userEthContributions[_token][msg.sender] += msg.value;
        
        // transfer tokens to the buyer's wallet
        Token(_token).transfer(msg.sender, _amount);
        
        // Update the sale
        sale.sold += _amount;
        sale.raised += msg.value;
        // Make sure fund raising goal isn't met, since if its met we don't want people to keep buy tokens
        if (sale.sold >= TOKEN_LIMIT || sale.raised >= TARGET){
            sale.isOpen = false;
            if (!sale.isLiquidityCreated){
                triggerLiquidityCreation(_token);
                sale.isLiquidityCreated = true;
            }
        }
    }

    function triggerLiquidityCreation(address _token) internal {
        TokenSale storage sale = tokenToSale[_token];
        require(!sale.isLiquidityCreated); 
        Token memeTokenCt = Token(_token);
        uint256 tokenBalance = memeTokenCt.balanceOf(address(this));

        (address[] memory contributors, uint256[] memory contributorAmounts) = getContributors(_token);

        memeTokenCt.approve(address(nativeLiquidityPool), tokenBalance);
        nativeLiquidityPool.addLiquidity{value: sale.raised}(_token, tokenBalance, contributors, contributorAmounts);
    }

    function calculateReward(address _token, address user) internal view returns (uint256) {
        if (!tokenToSale[_token].isLiquidityCreated || 
            hasClaimedReward[_token][user] ||
            userTokenContributions[_token][user] == 0) {
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
        Token(_token).mint(msg.sender, reward); // distribute token to LPs

    }

    function withdraw(uint256 _amount) external onlyOwner{
        (bool success, ) = payable(owner()).call{value: _amount}("");
        require(success);
    }
    
    function getTokenSale(uint256 _index) external view returns (TokenSale memory){
        require(_index < tokens.length);
        return tokenToSale[tokens[_index]];
    }

    function getCost(uint256 _sold) internal pure returns(uint256){
        uint256 floor = 0.0001 ether; // starting price of a token
        uint256 step = 0.0001 ether; // each time increase by this amount in price
        uint256 increment = 10000 ether;

        return (step * (_sold / increment)) + floor;
    }

    function getContributors(address _token) internal view returns (address[] memory, uint256[] memory){
        address[] memory contributors = tokenContributors[_token];
        uint256[] memory contributions = new uint256[](contributors.length);

        for (uint256 i = 0; i < contributors.length; i++) {
            contributions[i] = userEthContributions[_token][contributors[i]];
        }

        return (contributors, contributions);
    }

    function getPriceForTokens(address _token, uint256 _amount) public view returns (uint256) {
        TokenSale storage sale = tokenToSale[_token];
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
    ) external payable{
        bytes memory payload = abi.encode(_name, _symbol, _metadataURI, _creator);
        _lzSend(_dstEid, payload, _options, MessagingFee(msg.value, 0), payable(msg.sender));
    }

    function _lzReceive(
        Origin calldata /*_origin*/,
        bytes32 /*_guid*/,
        bytes calldata payload,
        address /*_executor*/,
        bytes calldata /*_extraData*/
    ) internal override {
        (
            string memory _name, 
            string memory _symbol, 
            string memory _metadataURI, 
            address _creator
        ) = abi.decode(payload, (string, string, string, address));
        _createToken(_name, _symbol, _metadataURI, _creator);
    }

} 