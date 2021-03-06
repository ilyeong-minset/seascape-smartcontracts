pragma solidity 0.6.7;

import "./openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "./openzeppelin/contracts/access/Ownable.sol";
import "./openzeppelin/contracts/math/SafeMath.sol";
import "./openzeppelin/contracts/utils/Counters.sol";
import "./NFTFactory.sol";

contract Staking is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Counters for Counters.Counter;

    uint256 scaler = 10**18;
	
    NFTFactory nftFactory;
    
    IERC20 public CWS;

    Counters.Counter private sessionId;

    /// @dev Total amount of Crowns stored for all sessions
    uint256 rewardSupply = 0;
    
    struct Session {
	address stakingToken;
        uint256 totalReward;
	uint256 period;
	uint256 startTime;
	uint256 generation;
	uint256 claimed;
	uint256 amount;
	uint256 rewardUnit;     // Reward per second = totalReward/period
    }

    struct Balance {
	uint256 amount;
	uint256 claimed;
	uint256 claimedTime;
	bool minted;
    }

    constructor(IERC20 _CWS) public {
	CWS = _CWS;

	// Starts at value 1. 
	sessionId.increment();
    }

    mapping(address => uint256) public lastSessionIds;
    mapping(uint256 => Session) public sessions;
    mapping(uint256 => mapping(address => Balance)) public balances;
    mapping(uint256 => mapping(address => uint)) public depositTime;

    event SessionStarted(address indexed stakingToken, uint256 id, uint256 reward, uint256 startTime, uint256 endTime, uint256 generation);
    event Deposited(address indexed stakingToken, address indexed owner, uint256 id, uint256 amount, uint256 startTime, uint256 totalStaked);
    event Claimed(address indexed stakingToken, address indexed owner, uint256 id, uint256 amount, uint256 claimedTime);
    event Withdrawn(address indexed stakingToken, address indexed owner, uint256 id, uint256 amount, uint256 startTime, uint256 totalStaked);
    
    //--------------------------------------------------
    // Only owner
    //--------------------------------------------------

    /// @notice Starts a staking session for a finit _period of
    /// time, starting from _startTime. The _totalReward of
    /// CWS tokens will be distributed in every second. It allows to claim a
    /// a _generation Seascape NFT.
    function startSession(address _tokenAddress,
			  uint256 _totalReward,
			  uint256 _period,
			  uint256 _startTime,
			  uint256 _generation) external onlyOwner {

	require(_tokenAddress != address(0),          "Seascape Staking: Staking token should not be equal to 0");
	require(_startTime > block.timestamp,         "Seascape Staking: Seassion should start in the future");
	require(_period > 0,                          "Seascape Staking: Lasting period of session should be greater than 0");
	require(_totalReward > 0,                     "Seascape Staking: Total reward of tokens to share should be greater than 0");

	uint256 _lastId = lastSessionIds[_tokenAddress];
	if (_lastId > 0) {
	    require(isStartedFor(_lastId)==false, "Seascape Staking: Can't start when session is active");
	}

	uint256 _sessionId = sessionId.current();

	uint256 newSupply = rewardSupply.add(_totalReward);
	// Amount of tokens to reward should be in the balance already
	require(CWS.balanceOf(address(this)) >= newSupply, "Seascape Staking: Not enough balance of Crowns for reward");

	uint256 _rewardUnit = _totalReward.div(_period);
	
	sessions[_sessionId] = Session(_tokenAddress, _totalReward, _period, _startTime, _generation, 0, 0, _rewardUnit);

	sessionId.increment();
	rewardSupply = newSupply;
	lastSessionIds[_tokenAddress] = _sessionId;

	emit SessionStarted(_tokenAddress, _sessionId, _totalReward, _startTime, _startTime + _period, _generation);
    }
 

    function isStartedFor(uint256 _sessionId) internal view returns(bool) {
	if (sessions[_sessionId].totalReward == 0) {
	    return false;
	}

	if (now > sessions[_sessionId].startTime + sessions[_sessionId].period) {
	    return false;
	}

	return true;
    }
    
    
    /// @notice Sets a NFT factory that will mint a token for stakers
    function setNFTFactory(address _address) external onlyOwner {
	nftFactory = NFTFactory(_address);
    }


    //--------------------------------------------------
    // Only staker
    //--------------------------------------------------

    /// @notice Deposits _amount of LP token
    /// of type _token into Staking contract.
    function deposit(uint256 _sessionId, uint256 _amount) external {
	require(_amount > 0,              "Seascape Staking: Amount to deposit should be greater than 0");
	require(_sessionId > 0,           "Seascape Staking: Session is not started yet!");
	require(isStartedFor(_sessionId), "Seascape Staking: Session is not active");

	IERC20 _token = IERC20(sessions[_sessionId].stakingToken);
	
	require(_token.balanceOf(msg.sender) >= _amount,
		"Seascape Staking: Not enough LP tokens to deposit");
	require(_token.transferFrom(msg.sender, address(this), _amount) == true,
		"Seascape Staking: Failed to transfer LP tokens into contract");

	Session storage _session  = sessions[_sessionId];
	Balance storage _balance  = balances[_sessionId][msg.sender];
	uint _depositTime = depositTime[_sessionId][msg.sender];

	bool _minted             = false;
	if (_depositTime > _session.startTime) {
	    _minted = _balance.minted;
	}
		
	if (_balance.amount > 0) {
	    claim(_sessionId);
	    _balance.amount = _amount.add(_balance.amount);
	    _balance.minted = _minted;
	} else {
	    // If user withdrew all LP tokens, but deposited before for the session
	    // Means, that player still can't mint more token anymore.
            balances[_sessionId][msg.sender] = Balance(_amount, 0, block.timestamp, _minted);
	}
	
	_session.amount                        = _session.amount.add(_amount);
	depositTime[_sessionId][msg.sender]    = block.timestamp;
       
        emit Deposited(_session.stakingToken, msg.sender, _sessionId, _amount, block.timestamp, _session.amount);
    }


    function claim(uint256 _sessionId) public {
	Session storage _session = sessions[_sessionId];
	Balance storage _balance = balances[_sessionId][msg.sender];

	require(_balance.amount > 0, "Seascape Staking: No deposit was found");
	
	uint256 _interest = calculateInterest(_sessionId, msg.sender);

	require(CWS.transfer(msg.sender, _interest) == true,
		"Seascape Staking: Failed to transfer reward CWS token");
		
	_session.claimed     = _session.claimed.add(_interest);
	_balance.claimed     = _balance.claimed.add(_interest);
	_balance.claimedTime = block.timestamp;
	rewardSupply         = rewardSupply.sub(_interest);

	emit Claimed(_session.stakingToken, msg.sender, _sessionId, _interest, block.timestamp);
    }

    function calculateInterest(uint256 _sessionId, address _owner) internal view returns(uint256) {
	Session storage _session = sessions[_sessionId];
	Balance storage _balance = balances[_sessionId][_owner];

	// How much of total deposit is belong to player as a floating number
	if (_balance.amount == 0 || _session.amount == 0) {
	    return 0;
	}

	uint256 _sessionCap = block.timestamp;
	if (isStartedFor(_sessionId) == false) {
	    _sessionCap = _session.startTime.add(_session.period);
	}

	uint256 _portion = _balance.amount.mul(scaler).div(_session.amount);
	
       	uint256 _interest = _session.rewardUnit.mul(_portion).div(scaler);

	// _balance.startTime is misleading.
	// Because, it's updated in every deposit time or claim time.
	uint256 _earnPeriod = _sessionCap.sub(_balance.claimedTime);
	
	return _interest.mul(_earnPeriod);
    }

    /// @notice Withdraws _amount of LP token
    /// of type _token out of Staking contract.
    function withdraw(uint256 _sessionId, uint256 _amount) external {
	Balance storage _balance  = balances[_sessionId][msg.sender];

	require(_balance.amount >= _amount, "Seascape Staking: Exceeds the balance that user has");

	claim(_sessionId);

	IERC20 _token = IERC20(sessions[_sessionId].stakingToken);

	require(_token.transfer(msg.sender, _amount) == true, "Seascape Staking: Failed to transfer token from contract to user");
	
	_balance.amount = _balance.amount.sub(_amount);
	sessions[_sessionId].amount = sessions[_sessionId].amount.sub(_amount);

	emit Withdrawn(sessions[_sessionId].stakingToken, msg.sender, _sessionId, _amount, block.timestamp, sessions[_sessionId].amount);
    }

    /// @notice Mints an NFT for staker. One NFT per session, per token.
    function claimNFT(uint256 _sessionId) external {
	require(isStartedFor(_sessionId), "Seascape Staking: No active session");

	Balance storage _balance = balances[_sessionId][msg.sender];
	require(_balance.claimed.add(_balance.amount) > 0, "Seascape Staking: Deposit first");
	require(_balance.minted == false, "Seascape Staking: Already minted");

	uint256 _tokenId = nftFactory.mint(msg.sender, sessions[_sessionId].generation);
	require(_tokenId > 0, "NFT Rush: failed to mint a token");
	
	balances[_sessionId][msg.sender].minted = true;
    }


    //--------------------------------------------------
    // Public methods
    //--------------------------------------------------

    /// @notice Returns amount of Token staked by _owner
    function stakedBalanceOf(uint256 _sessionId, address _owner) external view returns(uint256) {
	return balances[_sessionId][_owner].amount;
    }

    /// @notice Returns amount of CWS Tokens earned by _address
    function earned(uint256 _sessionId, address _owner) external view returns(uint256) {
	uint256 _interest = calculateInterest(_sessionId, _owner);
	return balances[_sessionId][_owner].claimed.add(_interest);
    }

    /// @notice Returns amount of CWS Tokens that _address could claim.
    function claimable(uint256 _sessionId, address _owner) external view returns(uint256) {
	return calculateInterest(_sessionId, _owner);
    }

    /// @notice Returns total amount of Staked LP Tokens
    function stakedBalance(uint256 _sessionId) external view returns(uint256) {
	return sessions[_sessionId].amount;
    }
}


