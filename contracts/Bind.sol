// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
interface DeerNode{
    function addNode(address _node) external;
}
contract Bind is Ownable{
    address public defaultReferrer;
    mapping(address => User) public userMap;
    address[] public users;
    DeerNode deerNode;
    mapping(address => bool) public operators;
    mapping(address => bool) public isNode;
    struct User{
        bool active;
        address referrer;
        uint subNum;
        address[] subordinates;
    }

    constructor(address _referrer) {
        defaultReferrer = _referrer;
        userMap[defaultReferrer].active = true;
        users.push(defaultReferrer);
    }

    function setOperator(address[] memory operatorList, bool flag) public onlyOwner{
        for(uint256 i=0;i<operatorList.length;i++){
            operators[operatorList[i]] = flag;
        }
    }

    modifier onlyOperator() {
        require(operators[msg.sender], 'Bind: Caller is not the operator');
        _;
    }

    //操作者合约调用
    function bindRelationshipExternal(address account, address referrer) public onlyOperator {
        _bindRelationship(account, referrer);
    }

    //前端绑定按钮调用
    function bindRelationship(address referrer) public {
        _bindRelationship(msg.sender, referrer);
        if(userMap[referrer].subordinates.length >= 30 && !isNode[referrer]){
            deerNode.addNode(referrer);
            isNode[referrer] = true;
        }
    }

    function _bindRelationship(address account, address referrer) internal {
        if (userMap[account].active || userMap[account].referrer != address(0)) return;
        if (!userMap[referrer].active && userMap[referrer].referrer == address(0)) {
            referrer = defaultReferrer;
        }
        userMap[account].referrer = referrer;
        userMap[account].active = true;
        userMap[referrer].subordinates.push(account);
        userMap[referrer].subNum++;
        users.push(account);
    }

    function isActive(address account) public view returns(bool){
        return userMap[account].active;
    }

    function getReferrer(address account) public view returns(address){
        return userMap[account].referrer == address(0) ? defaultReferrer : userMap[account].referrer;
    }

    function getLength() public view returns(uint){
        return users.length;
    }

    function getList(uint start, uint length) public view returns(address[] memory addrs, address[] memory referrers){
        uint256 end = (start+length) < users.length ? (start+length) : users.length;
        length = end > start ? end - start : 0;
        addrs = new address[](length);
        referrers = new address[](length);
        for(uint i=start; i<end; i++){
            addrs[i-start] = users[i];
            referrers[i-start] = userMap[users[i]].referrer;
        }
    }

    function getSubordinates(address account) public view returns(address[] memory){
        return userMap[account].subordinates;
    }

    function getSubordinatesList(address account, uint start, uint length) public view returns(address[] memory addrs){
        User memory user = userMap[account];
        uint256 end = (start+length) < user.subNum ? (start+length) : user.subNum;
        length = end > start ? end - start : 0;
        addrs = new address[](length);
        for(uint i=start; i<end; i++){
            addrs[i-start] = user.subordinates[i];
        }
    }
}