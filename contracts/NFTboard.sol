// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

interface INFT is IERC721Enumerable{
    function mintTo(address _to) external;
    function tokensOfOwner(address owner, uint256 start, uint256 length) view external returns(uint256[] memory tokenIds);
}

contract NFTBoard is Ownable,IERC721Receiver {
    using SafeMath for uint256;
    //质押总量
    uint256 _totalSupply;
    //地址质押数量
    mapping(address => uint256) _balances;
    //董事会席位：{
    //     最后快照索引
    //     获得奖励
    // }
    struct Boardseat {
        uint256 lastSnapshotIndex;
        uint256 rewardEarned;
    }
    //董事会快照{
    //     时间
    //     已接收奖励
    //     每份质押奖励
    //}
    struct BoardSnapshot {
        uint256 time;
        uint256 rewardReceived;
        uint256 rewardPerShare;
    }
    //质押代币
    INFT public nft;
    //奖励代币
    IERC20 public rewardToken;
    //操作员
    mapping(address => bool) public operators;
    //董事
    mapping(address => Boardseat) private directors;
    //快照数组
    BoardSnapshot[] private boardHistory;

    mapping(address => uint[]) public _ownerIndex;

    constructor(address _nft, address _rewardToken) {
        nft = INFT(_nft);
        rewardToken = IERC20(_rewardToken);
        operators[_rewardToken] = true;
        BoardSnapshot memory genesisSnapshot = BoardSnapshot({
            time: block.number,
            rewardReceived: 0,
            rewardPerShare: 0
        });
        boardHistory.push(genesisSnapshot);
    }

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    modifier onlyOperator() {
        require(operators[msg.sender], 'Boardroom: Caller is not the operator');
        _;
    }

    function setOperator(address[] memory operatorList, bool flag) public onlyOwner{
        for(uint256 i=0;i<operatorList.length;i++){
            operators[operatorList[i]] = flag;
        }
    }

    //管理员可提取外部代币和NFT，一般是不让领取奖励币和质押的NFT，特定情况可去掉限制条件
     function withdrawForeignTokens(address token, address to, uint256 amount) onlyOwner public returns (bool) {
         require(token!=address(rewardToken), 'Wrong token!');
         return IERC20(token).transfer(to, amount);
     }

     function withdrawForeignNFT(address _nft, address to, uint256 tokenId) onlyOwner public {
         require(_nft!=address(nft), 'Wrong NFT!');
         INFT(_nft).transferFrom(address(this), to, tokenId);
     }

    modifier updateReward(address director) {
        if (director != address(0)) {
            Boardseat memory seat = directors[director];
            seat.rewardEarned = earned(director);
            seat.lastSnapshotIndex = latestSnapshotIndex();
            directors[director] = seat;
        }
        _;
    }

    function latestSnapshotIndex() public view returns (uint256) {
        return boardHistory.length.sub(1);
    }

    function getLatestSnapshot() internal view returns (BoardSnapshot memory) {
        return boardHistory[latestSnapshotIndex()];
    }

    function getLastSnapshotIndexOf(address director) public view returns (uint256){
        return directors[director].lastSnapshotIndex;
    }

    function getLastSnapshotOf(address director)internal view returns (BoardSnapshot memory) {
        return boardHistory[getLastSnapshotIndexOf(director)];
    }

    function rewardPerShare() public view returns (uint256) {
        return getLatestSnapshot().rewardPerShare;
    }

    function earned(address director) public view returns (uint256) {
        uint256 latestRPS = getLatestSnapshot().rewardPerShare;
        uint256 storedRPS = getLastSnapshotOf(director).rewardPerShare;

        uint256 rewardEarned = balanceOf(director)
            .mul(latestRPS.sub(storedRPS)).div(1e18)
            .add(directors[director].rewardEarned);
        return rewardEarned;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */
    function stake(uint256 amount) public updateReward(msg.sender) {
        require(amount > 0, 'Boardroom: Cannot stake 0');
        require(amount <= nft.balanceOf(msg.sender), 'Boardroom: Stake amount exceeds balance');
        uint256[] memory tokenIds = nft.tokensOfOwner(msg.sender, 0, amount);
        for(uint256 i;i<tokenIds.length;i++){
            nft.transferFrom(msg.sender, address(this), tokenIds[i]);
            _ownerIndex[msg.sender].push(tokenIds[i]);
        }
        _totalSupply = _totalSupply.add(amount);
        _balances[msg.sender] = _balances[msg.sender].add(amount);
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) public updateReward(msg.sender) {
        require(amount > 0, 'Boardroom: Cannot withdraw 0');
        uint256 directorShare = _balances[msg.sender];
        require(
            directorShare >= amount,
            'Boardroom: withdraw request greater than staked amount'
        );
        uint256 length = _ownerIndex[msg.sender].length;
        for(uint256 i;i<amount;i++){
            nft.transferFrom(address(this), msg.sender, _ownerIndex[msg.sender][length-1-i]);
            _ownerIndex[msg.sender].pop();
        }
        _totalSupply = _totalSupply.sub(amount);
        _balances[msg.sender] = directorShare.sub(amount);
        emit Withdrawn(msg.sender, amount);
    }

    function getReward() public updateReward(msg.sender) {
        uint256 reward = directors[msg.sender].rewardEarned;
        if (reward > 0) {
            directors[msg.sender].rewardEarned = 0;
            rewardToken.transfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    function addNewSnapshot(uint256 amount) private{
        // Create & add new snapshot
        uint256 prevRPS = getLatestSnapshot().rewardPerShare;
        uint256 nextRPS = prevRPS.add(amount.mul(1e18).div(totalSupply()));

        BoardSnapshot memory newSnapshot = BoardSnapshot({
            time: block.number,
            rewardReceived: amount,
            rewardPerShare: nextRPS
        });
        boardHistory.push(newSnapshot);
    }

    function allocateWithToken(uint256 amount) external{
        require(amount > 0, 'Boardroom: Cannot allocate 0');
        if(totalSupply() > 0){
            addNewSnapshot(amount);
            if(amount>0) rewardToken.transferFrom(msg.sender, address(this), amount);
            emit RewardAdded(msg.sender, amount);
        }
    }

    function allocate(uint256 amount) external onlyOperator{
        require(amount > 0, 'Boardroom: Cannot allocate 0');
        if(totalSupply() > 0){
            addNewSnapshot(amount);
            emit RewardAdded(msg.sender, amount);
        }
    }

    function getOwnerIndexLength(address owner) public view returns(uint){
        return _ownerIndex[owner].length;
    }

    function getOwnerIndexList(address owner, uint256 start, uint256 length) view public returns(uint256[] memory tokenIds){
        uint256 end = (start+length) < _ownerIndex[owner].length ? (start+length) : _ownerIndex[owner].length;
        length = end > start ? end - start : 0;
        tokenIds = new uint[](length);
        for(uint i=start; i<end; i++){
            tokenIds[i-start] = _ownerIndex[owner][i];
        }
    }

    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardAdded(address indexed user, uint256 reward);
    event OnERC721Received(address,address,uint256,bytes);

    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data) external override returns (bytes4){
        emit OnERC721Received(operator,from,tokenId,data);
        return bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"));
        // return IERC721Receiver.onERC721Received.selector;
    }
}