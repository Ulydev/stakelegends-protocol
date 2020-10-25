//SPDX-License-Identifier: MIT

// Stake Legends

pragma solidity ^0.5.0;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/upgrades/contracts/Initializable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "../aave-protocol/contracts/interfaces/ILendingPoolAddressesProvider.sol";
import "../aave-protocol/contracts/lendingpool/LendingPool.sol";
import "../aave-protocol/contracts/lendingpool/LendingPoolCore.sol";
import "../aave-protocol/contracts/tokenization/AToken.sol";

import "@chainlink/contracts/src/v0.6/ChainlinkClient.sol";

contract SeasonStaking is Ownable, Initializable, ChainlinkClient {
    
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 internal constant REGISTRATION_FEE = 1 ether;
    address internal constant AAVE_ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    string internal constant VALIDATION_URI = "https://localhost:3000/validate";
    string internal constant RANK_URI = "https://localhost:3000/rank";

    uint256 internal constant N_WINNERS = 5;

    EnumerableSet.AddressSet public participants;
    mapping (address => bool) public hasRedeemed;

    uint256 public estimatedStartTimestamp;
    uint256 public estimatedEndTimestamp;

    enum State { Registering, Started, Ended }
    State public state;

    uint256 public initialContractBalance;

    ILendingPoolAddressesProvider private _aaveAddressesProvider;
    address private _chainlinkOracle;
    string private _getUintJobId;
    string private _getBoolJobId;
    uint256 internal constant CHAINLINK_FEE = 0.1 * 10 ** 18; // 0.1 LINK

    struct IdentityRequest {
        address _address;
        string _username;
    }
    mapping (bytes32 => IdentityRequest) private _identityRequests;
    mapping (bytes32 => address) private _redeemRequests;
    mapping (address => string) public usernameByAddress;
    mapping (address => string) public addressByUsername;

    /* Modifiers */

    modifier whenRegistering {
        require(state == Registering, "The season is not in the registration phase");
        _;
    }

    modifier whenStarted {
        require(state == Started, "The season has not started yet");
        _;
    }

    modifier whenEnded {
        require(state == Ended, "The season is still running");
        _;
    }

    function checkIdentityStatus(address _address, string _username) internal {
        require(bytes(usernameByAddress[_address]).length == 0, "User already has a username");
        require(addressByUsername[_username] == address(0), "Username already has an owner");
    }

    function checkRedeemStatus(address _address) internal {
        require(participants.contains(_address), "User is not registered");
        require(!hasRedeemed[_address], "User has already redeemed");
    }

    /* Initializer */

    function initialize(address aaveLendingPoolAddressesProviderAddress, address chainlinkOracle, bytes32 getUintJobId, bytes32 getBoolJobId) public initializer {
        _aaveAddressesProvider = new ILendingPoolAddressesProvider(aaveLendingPoolAddressesProviderAddress);

        _chainlinkOracle = chainlinkOracle;
        _getUintJobId = getUintJobId;
        _getBoolJobId = getBoolJobId;

        state = Ended;
    }

    /* Owner */

    function openRegistration(uint256 _estimatedStartTimestamp) external onlyOwner whenEnded {
        state = Registering;
        estimatedStartTimestamp = _estimatedStartTimestamp;
    }

    function startSeason(uin256 _estimatedEndTimestamp) external onlyOwner whenRegistering {
        state = Started;
        estimatedEndTimestamp = _estimatedEndTimestamp;
        initialContractBalance = address(this).balance; // Save contract balance for future reference
        getLendingPool().deposit{ value: address(this).balance }(AAVE_ETH_ADDRESS, msg.value, 0); // Deposit contract ETH balance on Aave
    }

    function endSeason() external onlyOwner whenStarted {
        state = Ended;
        getAETHToken().redeem(-1); // Redeem all initial ETH + interests
    }

    /* Public */

    function register() payable external whenRegistering {
        require(bytes(usernameByAddress[msg.sender]).length > 0, "User has no username");
        require(msg.value == REGISTRATION_FEE, "Incorrect registration fee");
        require(!participants.contains(msg.sender), "User already registered");
        participants.add(msg.sender);
        hasRedeemed[msg.sender] = false;
    }

    function claimUsername(string _username) public {
        checkIdentityStatus(msg.sender, _username);
        bytes32 requestId = requestValidateUsername(msg.sender, _username);
        _identityRequests[requestId] = IdentityRequest(msg.sender, _username);
    }

    function redeem() payable external whenEnded {
        checkRedeemStatus(msg.sender);
        bytes32 requestId = requestRedeem(msg.sender);
        _redeemRequests[requestId] = msg.sender;
    }

    /* Chainlink requests */

    function requestValidateUsername(address _address, string _username) internal returns (bytes32) {
        Chainlink.Request memory request = buildChainlinkRequest(_getBoolJobId, address(this), this.fulfillValidateUsername.selector);
        request.add("get", VALIDATION_URI);
        request.add("queryParams", abi.encodePacked("address=", string(_address), "&username=", _username));
        request.add("path", "valid");
        return sendChainlinkRequestTo(_chainlinkOracle, request, CHAINLINK_FEE);
    }

    function requestRedeem(address _address) internal returns (bytes32) {
        Chainlink.Request memory request = buildChainlinkRequest(_getUintJobId, address(this), this.fulfillRedeem.selector);
        request.add("get", RANK_URI);
        request.add("queryParams", abi.encodePacked("username=", string(_address)));
        request.add("path", "rank");
        return sendChainlinkRequestTo(_chainlinkOracle, request, CHAINLINK_FEE);
    }

    /* Chainlink callbacks */

    function fulfillValidateUsername(bytes32 _requestId, bool _valid) public recordChainlinkFulfillment(_requestId) {
        IdentityRequest identityRequest = _identityRequests[_requestId];
        string _username = identityRequest._username;
        address _address = identityRequest._address;
        delete _identityRequests[_requestId];

        checkIdentityStatus(_address, _username);
        require(_valid, "Identity couldn't be verified");

        usernameByAddress[_address] = _username;
        addressByUsername[_username] = _address;
    }

    function fulfillRedeem(bytes32 _requestId, uint256 rank) public recordChainlinkFulfillment(_requestId) {
        address _address = _redeemRequests[_requestId];
        delete _redeemRequests[_requestId];

        checkRedeemStatus(_address);

        participants.remove(_address);
        hasRedeemed[_address] = true;
        uint256 redeemableAmount = REGISTRATION_FEE.add(eligiblePrize(rank));
        (bool success, ) = address(uint160(_address)).call.value(redeemableAmount)(); // Explicit conversion to payable
        require(success, "Redeem failed");
    }

    /* Private */

    function getLendingPool() returns (LendingPool) {
        return LendingPool(_aaveAddressesProvider.getLendingPool());
    }

    function getLendingPoolCore() returns (LendingPoolCore) {
        return LendingPoolCore(_aaveAddressesProvider.getLendingPoolCore());
    }

    function getAETHToken() returns (AToken) {
        return AToken(getLendingPoolCore().getReserveATokenAddress(AAVE_ETH_ADDRESS));
    }

    /* Views */

    function eligiblePrize(uint256 rank) external view returns (uint256) {
        if (rank >= N_WINNERS) {
            return 0;
        } else {
            return generatedInterests().div(N_WINNERS); // Interests equally distributed among top N players
        }
    }

    function generatedInterests() external view returns (uint256) {
        return getAETHToken().balanceOf(address(this)).sub(initialContractBalance);
    }

}
