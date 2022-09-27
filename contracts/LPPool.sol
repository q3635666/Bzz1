// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";

contract LPTokenWrapper {
    using SafeMath for uint256;
    //ERC20质押代币
    IERC20 public _lpt;
    //总量
    uint256 private _totalSupply;
    //地址>余额
    mapping(address => uint256) private _balances;
    //获取总量
    function totalSupply() public view returns (uint256) {  
        return _totalSupply;
    }
    //获取地址质押代币数量
    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }
    //质押代币
    function stake(uint256 amount) public virtual {
        _totalSupply = _totalSupply.add(amount);
        _balances[msg.sender] = _balances[msg.sender].add(amount);
        _lpt.transferFrom(msg.sender, address(this), amount);
    }
    //提取代币
    function withdraw(uint256 amount) public virtual {
        _totalSupply = _totalSupply.sub(amount);
        _balances[msg.sender] = _balances[msg.sender].sub(amount);
        _lpt.transfer(msg.sender, amount);
    }
}

contract LPPool is LPTokenWrapper, Ownable {
    using SafeMath for uint256;
    //ERC20收益代币
    IERC20 public _rewardToken;
    //流动池每日收益数量
    uint256 public _reward;
    //时间常量：一天
    uint256 public constant DURATION = 1 days;
    //最后更新时间
    uint256 public lastUpdateTime;
    //每个质押代币的收益
    uint256 public rewardPerTokenStored;
    mapping(address => uint256) public userRewardPerTokenPaid;
    //用户总收益
    mapping(address => uint256) public rewards;

    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);

    constructor(address lpt, address rewardToken, uint256 reward) {
        _lpt = IERC20(lpt);
        _rewardToken = IERC20(rewardToken);
        _reward = reward;
    }
    //更新地址收益 传入地址
    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = block.timestamp;
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }
    //返回每份质押收益
    function rewardPerToken() public view returns (uint256) {
        if (totalSupply() == 0) {
            return rewardPerTokenStored;
        }
        uint nowTime = block.timestamp;
        //流动池每秒代币收益
        uint rewardRate = _reward.div(DURATION);
        return
        rewardPerTokenStored.add(
            nowTime
            .sub(lastUpdateTime)
            .mul(rewardRate)
            .mul(1e18)
            .div(totalSupply())
        );
    }
    //获取用户收益
    function earned(address account) public view returns (uint256) {
        return
        balanceOf(account)
        .mul(rewardPerToken().sub(userRewardPerTokenPaid[account]))
        .div(1e18)
        .add(rewards[account]);
    }

    // stake visibility is public as overriding LPTokenWrapper's stake() function
    function stake(uint256 amount) public override updateReward(msg.sender) {
        require(amount > 0, 'Cannot stake 0');
        super.stake(amount);
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) public override updateReward(msg.sender) {
        require(amount > 0, 'Cannot withdraw 0');
        super.withdraw(amount);
        emit Withdrawn(msg.sender, amount);
    }

    function exit() external {
        withdraw(balanceOf(msg.sender));
        getReward();
    }

    function getReward() public updateReward(msg.sender) {
        uint256 reward = earned(msg.sender);
        if (reward > 0) {
            rewards[msg.sender] = 0;
            _rewardToken.transfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    function changeReward(uint reward) external onlyOwner updateReward(address(0)) {
        _reward = reward;
        emit RewardAdded(reward);
    }

    function withdrawForeignTokens(address token, address to, uint256 amount) onlyOwner public returns (bool) {
        return IERC20(token).transfer(to, amount);
    }
}