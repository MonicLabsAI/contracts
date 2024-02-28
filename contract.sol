pragma solidity >=0.5.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


contract GatorContract {
    IERC20 public GTR;

    constructor(address tokenaddress) {
        GTR = IERC20(tokenaddress);
    }

    struct Model {
        string name;
        uint256 id;
        uint256 minstake;
        uint256 minsimilarity;
        uint256 slashpercent;
        string extra;
        bool rewards;
        address[] rewardsTotalVotersFor;
        address[] rewardsTotalVotersAgainst;
        int256 rewardsTotalVotes;
    }

    struct Request {
        bytes32 id;
        address origin;
        string prompt;
        uint256 totalConfirmations;
        uint256 confirmations;
        uint256 model;
        uint256 price;
        bool fulfilled;
        string[] responses;
        address[] responders;
    }

    mapping(uint256 => Model) public models;
    mapping(bytes32 => Request) public requests;
    mapping(address => uint256) public stakes;

    uint256[] internal modelids;

    uint256 public totalstakes;

    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);

    event RequestCreated(bytes32 indexed requestId, address indexed origin, string prompt, uint256 confirmations, uint256 model, uint256 bid, uint256 entropy);
    event RequestFulfilled(bytes32 indexed requestId, address[] responders, string response, uint256 responseCount, uint256 totalProfit);

    function registerModel(string memory name, uint256 id, uint256 minstake, uint64 minsimilarity, uint256 slashpercent, string memory extra) public {
        require(bytes(models[id].name).length == 0, "Model already exists");

        models[id].name = name;
        models[id].id = id;
        models[id].minstake = minstake;
        models[id].minsimilarity = minsimilarity;
        models[id].slashpercent = slashpercent;
        models[id].extra = extra;
        models[id].rewards = false;

        modelids.push(id);
    }

    function createRequest(string memory prompt, uint256 totalConfirmations, uint256 bid, uint256 model) public payable returns (bytes32) {
        bytes32 requestId = keccak256(abi.encodePacked(msg.sender, prompt, totalConfirmations, bid, model, block.number));
        
        Request storage request = requests[requestId];
        request.origin = msg.sender;
        request.prompt = prompt;
        request.totalConfirmations = totalConfirmations;
        request.model = model;
        request.id = requestId;
        
        emit RequestCreated(requestId, msg.sender, prompt, totalConfirmations, model, bid, block.number);

        GTR.transferFrom(msg.sender, address(this), bid);

        return requestId;
    }
    
    function submitResponse(bytes32 requestId, uint256 modelId, string memory response) public {
        require(getStake(msg.sender) >= models[modelId].minstake, "Insufficient token stake");

        Request storage request = requests[requestId];

        require(request.fulfilled == false, "Request already completed");
        require(request.model == modelId, "Incorrect model ID");

        request.responses.push(response);
        request.responders.push(msg.sender);
        request.confirmations +=1;

        if (request.totalConfirmations == 1) {
            stakeAdd(msg.sender, request.price);
            request.fulfilled = true;
            emit RequestFulfilled(request.id, request.responders, response, request.confirmations, request.price);
            return;
        }

        if (request.totalConfirmations <= request.confirmations) {
            return;
        }

        if (areAllStringsSame(request.responses) == true) {
            for (uint256 i = 0; i <= request.responders.length; i++) {
                if (models[modelId].rewards == true && GTR.balanceOf(address(this)) >= (((request.price / request.totalConfirmations) * 2) + (request.price / request.totalConfirmations))) {
                    stakeAdd(request.responders[i], (request.price / request.totalConfirmations) * 2);
                }
                stakeAdd(request.responders[i], request.price / request.totalConfirmations);
            }

            request.fulfilled = true;
            emit RequestFulfilled(request.id, request.responders, response, request.confirmations, request.price);
        } else {
            string memory majorityString = getMajorityStringInList(request.responses);
            for (uint256 i = 0; i <= request.responders.length; i++) {
                uint256 stringSimilarity = compareStrings(majorityString, request.responses[i]);
                if (stringSimilarity >= models[modelId].minsimilarity) {
                    stakeSubtract(request.responders[i], (models[modelId].slashpercent * stringSimilarity));
                }
            }

            request.fulfilled = true;
            emit RequestFulfilled(request.id, request.responders, response, request.confirmations, request.price);
        }
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
    function stake(uint256 _amount) external {
        require(_amount > 0, "Amount must be greater than 0");
        require(GTR.transferFrom(msg.sender, address(this), _amount), "Transfer failed");
        
        stakes[msg.sender] += _amount;
        totalstakes += _amount;
        
        emit Staked(msg.sender, _amount);
    }
    function unstake(uint256 _amount) external {
        require(_amount > 0, "Amount must be greater than 0");
        require(stakes[msg.sender] >= _amount, "Insufficient stake");
        
        stakes[msg.sender] -= _amount;
        totalstakes -= _amount;
        
        require(GTR.transfer(msg.sender, _amount), "Transfer failed");
        
        emit Unstaked(msg.sender, _amount);
    }

    function stakeAdd(address _address, uint256 _amount) internal {
        stakes[_address] += _amount;
        totalstakes += _amount;
    }
    function stakeSubtract(address _address, uint256 _amount) internal {
        stakes[_address] -= _amount;
        totalstakes -= _amount;
    }

    function getStake(address _address) public view returns (uint256) {
        return stakes[_address];
    }

    function transferStake(address to, uint256 amount) public {
        require(getStake(msg.sender) >= amount);
        require(amount > 0, "Amount should be greater than 0");

        stakeSubtract(msg.sender, amount);
        stakeAdd(to, amount);
    }


    /*****         Rewards         *****/
    function voteForModelRewards(uint256 modelId) public {
        models[modelId].rewardsTotalVotersFor.push(msg.sender);
        models[modelId].rewardsTotalVotes = totalVotesFor(modelId) - totalVotesAgainst(modelId);

        if (models[modelId].rewardsTotalVotes > 0) {
            models[modelId].rewards = true;
        }
    }

    function voteAgainstModelRewards(uint256 modelId) public {
        models[modelId].rewardsTotalVotersAgainst.push(msg.sender);
        models[modelId].rewardsTotalVotes = totalVotesFor(modelId) - totalVotesAgainst(modelId);

        if (models[modelId].rewardsTotalVotes > 0) {
            models[modelId].rewards = true;
        }
    }

    function totalVotesFor(uint256 modelId) public view returns (int256) {
        int256 totalVotes_ = 0;
        Model memory model = models[modelId];
        for (uint256 i = 0; i < model.rewardsTotalVotersFor.length; i++) {
            totalVotes_+=int256(GTR.balanceOf(model.rewardsTotalVotersFor[i]));
        }

        return totalVotes_;
    }

    function totalVotesAgainst(uint256 modelId) public view returns (int256) {
        int256 totalVotes_ = 0;
        Model memory model = models[modelId];
        for (uint256 i = 0; i < model.rewardsTotalVotersAgainst.length; i++) {
            totalVotes_+=int256(GTR.balanceOf(model.rewardsTotalVotersAgainst[i]));
        }

        return totalVotes_;
    }



    /*****         Helpers         *****/
    function getMajorityStringInList(string[] memory stringsArray) public pure returns (string memory) {
        uint256 maxCount = 0;
        string memory majorityString;

        for (uint256 i = 0; i < stringsArray.length; i++) {
            string memory currentString = stringsArray[i];
            uint256 currentCount = 0;

            for (uint256 j = 0; j < stringsArray.length; j++) {
                if (keccak256(bytes(currentString)) == keccak256(bytes(stringsArray[j]))) {
                    currentCount++;
                }
            }

            if (currentCount > maxCount) {
                maxCount = currentCount;
                majorityString = currentString;
            }
        }

        return majorityString;
    }

    function areAllStringsSame(string[] memory stringsArray) public pure returns (bool) {
        require(stringsArray.length > 0, "Array should not be empty");

        string memory firstString = stringsArray[0];
        
        for (uint i = 1; i < stringsArray.length; i++) {
            if (keccak256(bytes(firstString)) != keccak256(bytes(stringsArray[i]))) {
                return false;
            }
        }
        
        return true;
    }

    function compareStrings(string memory _str1, string memory _str2) public pure returns (uint256) {
        bytes memory str1 = bytes(_str1);
        bytes memory str2 = bytes(_str2);
        
        uint256 minLength = str1.length < str2.length ? str1.length : str2.length;
        uint256 matchingCharacters = 0;
        
        for (uint256 i = 0; i < minLength; i++) {
            if (str1[i] == str2[i]) {
                matchingCharacters++;
            }
        }

        uint256 similarityPercentage = (matchingCharacters * 100) / minLength;
        return similarityPercentage;
    }
}
