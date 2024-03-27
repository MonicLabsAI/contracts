// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract GatorContract is ReentrancyGuard {
    IERC20 public AGG;

    address public verifier;
    address public treasury;

    modifier onlyVerifier() {
        require(msg.sender == verifier, "Only the Verifier can call this function.");
        _;
    }

    modifier onlyTreasury() {
        require(msg.sender == treasury, "Only the Treasury can call this function.");
        _;
    }

    constructor(address tokenaddress, address _verifier, address _treasury) {
        AGG = IERC20(tokenaddress);
        verifier = _verifier;
        treasury = _treasury;
    }

    struct Model {
        string name;
        uint256 id;
        uint256 minstake;
        string extra;
        uint256 rewards;
    }

    struct Request {
        bytes32 id;
        address origin;
        string prompt;
        uint256 model;
        uint256 bid;
        bool fulfilled;
        string response;
        uint256 entropy;
        uint256 timestamp;
    }

    mapping(uint256 => Model) public models;
    mapping(bytes32 => Request) public requests;
    mapping(address => uint256) public stakes;

    uint256[] public modelids;
    uint256 public totalstakes;
    
    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);

    event RequestCreated(bytes32 indexed requestId, uint256 modelId, address origin, string prompt, uint256 bid, uint256 entropy);
    event RequestFulfilled(bytes32 indexed requestId, uint256 modelId, address responder, string response);

    event ModelRegistered(uint256 modelid, address indexed registrant);

    function registerModel(string memory name, uint256 id, uint256 minStake, string memory extra) public {
        require(models[id].id == 0, "Model with that ID already registered.");
        require(AGG.transferFrom(msg.sender, treasury, 1), "Could not pay model registration fee");

        models[id] = Model(name, id, minStake, extra, 0);
        modelids.push(id);

        emit ModelRegistered(id, msg.sender);
    }

    function createRequest(uint256 modelId, string memory prompt, uint256 bid, uint256 entropy) public returns (bytes32) {
        require(models[modelId].id != 0, "Model ID does not exist.");
        require(AGG.transferFrom(msg.sender, address(this), bid), "Cannot transfer bid");
        
        bytes32 requestId = keccak256(abi.encodePacked(msg.sender, modelId, prompt, bid, entropy, block.timestamp));
        
        requests[requestId] = Request(requestId, msg.sender, prompt, modelId, bid, false, "", entropy, block.timestamp);
        
        emit RequestCreated(requestId, modelId, msg.sender, prompt, bid, entropy);
                
        return requestId;
    }
    
    function fulfillRequest(bytes32 requestId, string memory response) public nonReentrant {
        Request storage request = requests[requestId];

        require(models[request.model].id != 0);
        require(stakes[msg.sender] >= models[request.model].minstake, "Insufficient token stake.");
        require(!request.fulfilled, "Request already fulfilled.");

        request.response = response;
        request.fulfilled = true;
        stakes[msg.sender] += request.bid;
        totalstakes += request.bid;

        emit RequestFulfilled(requestId, request.model, msg.sender, response);
    }

    function getRequest(bytes32 requestId) public view returns (Request memory) {
        return requests[requestId];
    }
    function getModel(uint256 modelId) public view returns (Model memory) {
        return models[modelId];
    }
    function getAllModels() public view returns (uint256[] memory) {
        return modelids;
    }


    /*****        Staking        *****/
    function stake(uint256 _amount) external nonReentrant {
        require(_amount > 0, "Insufficient stake amount");
        require(AGG.transferFrom(msg.sender, address(this), _amount), "Transfer failed");
        
        stakes[msg.sender] += _amount;
        totalstakes += _amount;
        
        emit Staked(msg.sender, _amount);
    }
    function unstake(uint256 _amount) external nonReentrant {
        require(_amount > 0, "Invalid unstake amount");
        require(stakes[msg.sender] >= _amount, "Insufficient stake balance");

        stakes[msg.sender] -= _amount;
        totalstakes -= _amount;
        
        require(AGG.transfer(msg.sender, _amount), "Transfer failed");
        
        emit Unstaked(msg.sender, _amount);
    }

    function slashStake(address _address, uint256 _amount) public onlyVerifier {
        require(_amount <= stakes[_address], "The slash amount is greater than the balance of the address");
        
        stakes[_address] -= _amount;
        totalstakes -= _amount;

        AGG.transfer(0x000000000000000000000000000000000000dEaD, _amount);
    }

    function transferStake(address to, uint256 amount) public {
        require(to != 0x000000000000000000000000000000000000dEaD, "Cannot transfer stake to burn address");
        require(to != address(this), "Cannot transfer stake to own contract");

        require(stakes[msg.sender] >= amount, "");
        require(amount > 0, "Amount should be greater than 0");

        stakes[msg.sender] -= amount;
        stakes[to] += amount;
    }

    function burnStake(uint256 amount) public {
        stakes[msg.sender] -= amount;
        totalstakes -= amount;

        AGG.transferFrom(address(this), 0x000000000000000000000000000000000000dEaD, amount);
    }


    /*****        Owner        *****/
    function changeVerifier(address newVerifier) public onlyVerifier {
        require(newVerifier != address(0), "New owner is the zero address");
        verifier = newVerifier;
    }
    function transferTreasury(address newTreasury) public onlyTreasury {
        require(newTreasury != address(0), "New owner is the zero address");
        treasury = newTreasury;
    }
}
