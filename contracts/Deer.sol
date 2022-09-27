// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract Fomo10 {}

contract Fomo100 {}

interface IBoard {
    function allocateWithToken(uint256 amount) external;

    function allocate(uint256 amount) external;
}

contract Deer is Context, IERC20, IERC20Metadata {
    using SafeMath for uint256;
    mapping(address => uint256) private _balances;

    mapping(address => mapping(address => uint256)) private _allowances;

    uint256 private _totalSupply = 2100 * 1e4 * 1e18;
    string private _name = "Deer";
    string private _symbol = "deer";
    uint8 private _decimals = 18;

    address private LPPool;
    uint256 public LPPoolFee = 3;

    //买入手续费
    Fomo10 fomo10;
    Fomo100 fomo100;
    IBoard private node;
    uint256 public fomo10Fee = 2;
    uint256 public fomo100Fee = 3;
    uint256 public nodeFee = 2;

    //卖出手续费
    address private ecology;
    IBoard private NFTBoard;
    IBoard private DeerBoard;
    uint256 public ecologyFee = 3;
    uint256 public NFTBoardFee = 2;
    uint256 public DeerBoardFee = 2;

    //手续费交付地址
    mapping(address => bool) isDelivers;
    //pair合约地址
    mapping(address => bool) isPair;

    constructor() {}

    //设置交付地址
    function setDelivers(address[] memory _delivers, bool flag) public {
        for (uint256 i = 0; i < _delivers.length; i++) {
            isDelivers[_delivers[i]] = flag;
        }
    }

    //设置交易池地址
    function setPairs(address[] memory _pairs, bool flag) public {
        for (uint256 i = 0; i < _pairs.length; i++) {
            isDelivers[_pairs[i]] = flag;
        }
    }

    //设置pool地址
    function seetPools(
        address _LPPool,
        address _node,
        address _ecology,
        address _NFTBoard,
        address _DeerBoard
    ) public {
        LPPool = _LPPool;
        node = IBoard(_node);
        ecology = _ecology;
        NFTBoard = IBoard(_NFTBoard);
        DeerBoard = IBoard(_DeerBoard);
    }

    //转账
    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");

        _beforeTokenTransfer(from, to, amount);
        if (isDelivers[from] || isDelivers[to]) {
            _basictransfer(from, to, amount);
        } else if (isPair[from]) {
            _selltransfer(from, to, amount);
        } else if (isPair[to]) {
            _buytransfer(from, to, amount);
        } else {
            _basictransfer(from, to, amount);
        }

        _afterTokenTransfer(from, to, amount);
    }

    //无手续费转账
    function _basictransfer(
        address from,
        address to,
        uint256 amount
    ) internal {
        uint256 fromBalance = _balances[from];
        require(
            fromBalance >= amount,
            "ERC20: transfer amount exceeds balance"
        );
        _balances[from] = fromBalance - amount;
        _balances[to] += amount;
        emit Transfer(from, to, amount);
    }

    //买入手续费转账
    function _buytransfer(
        address from,
        address to,
        uint256 amount
    ) internal {
        uint256 fromBalance = _balances[from];
        require(
            fromBalance >= amount,
            "ERC20: transfer amount exceeds balance"
        );
        _balances[from] = fromBalance - amount;

        uint256 toLPPool = amount.mul(LPPoolFee).div(100);
        uint256 tofomo10 = amount.mul(fomo10Fee).div(100);
        uint256 tofomo100 = amount.mul(fomo100Fee).div(100);
        uint256 tonode = amount.mul(nodeFee).div(100);

        _balances[LPPool] += toLPPool;
        emit Transfer(from, LPPool, toLPPool);

        _balances[address(fomo10)] += tofomo10;
        emit Transfer(from, address(fomo10), tofomo10);

        _balances[address(fomo100)] += tofomo100;
        emit Transfer(from, address(fomo100), tofomo100);

        node.allocateWithToken(tonode);
        emit Transfer(from, address(DeerBoard), tonode);

        amount = amount - toLPPool - tofomo10 - tofomo100 - tonode;
        _balances[to] += amount;
        emit Transfer(from, to, amount);
    }

    //卖出手续费转账
    function _selltransfer(
        address from,
        address to,
        uint256 amount
    ) internal {
        uint256 fromBalance = _balances[from];
        require(
            fromBalance >= amount,
            "ERC20: transfer amount exceeds balance"
        );
        _balances[from] = fromBalance - amount;

        uint256 toLPPool = amount.mul(LPPoolFee).div(100);
        uint256 toecology = amount.mul(ecologyFee).div(100);
        uint256 toNFTBoard = amount.mul(NFTBoardFee).div(100);
        uint256 toDeerBoard = amount.mul(DeerBoardFee).div(100);

        _balances[LPPool] += toLPPool;
        emit Transfer(from, LPPool, toLPPool);

        _balances[ecology] += toecology;
        emit Transfer(from, ecology, toecology);

        NFTBoard.allocateWithToken(toNFTBoard);
        emit Transfer(from, address(NFTBoard), toNFTBoard);

        DeerBoard.allocateWithToken(toDeerBoard);
        emit Transfer(from, address(DeerBoard), toDeerBoard);

        amount = amount - toLPPool - toecology - toNFTBoard - toDeerBoard;
        _balances[to] += amount;
        emit Transfer(from, to, amount);
    }

    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");

        _beforeTokenTransfer(address(0), account, amount);

        _totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);

        _afterTokenTransfer(address(0), account, amount);
    }

    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from the zero address");

        _beforeTokenTransfer(account, address(0), amount);

        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        unchecked {
            _balances[account] = accountBalance - amount;
        }
        _totalSupply -= amount;

        emit Transfer(account, address(0), amount);

        _afterTokenTransfer(account, address(0), amount);
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _spendAllowance(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        uint256 currentAllowance = allowance(owner, spender);
        if (currentAllowance != type(uint256).max) {
            require(
                currentAllowance >= amount,
                "ERC20: insufficient allowance"
            );
            unchecked {
                _approve(owner, spender, currentAllowance - amount);
            }
        }
    }

    function name() public view virtual override returns (string memory) {
        return _name;
    }

    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account)
        public
        view
        virtual
        override
        returns (uint256)
    {
        return _balances[account];
    }

    function transfer(address to, uint256 amount)
        public
        virtual
        override
        returns (bool)
    {
        address owner = _msgSender();
        _transfer(owner, to, amount);
        return true;
    }

    function allowance(address owner, address spender)
        public
        view
        virtual
        override
        returns (uint256)
    {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount)
        public
        virtual
        override
        returns (bool)
    {
        address owner = _msgSender();
        _approve(owner, spender, amount);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, amount);
        _transfer(from, to, amount);
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue)
        public
        virtual
        returns (bool)
    {
        address owner = _msgSender();
        _approve(owner, spender, allowance(owner, spender) + addedValue);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue)
        public
        virtual
        returns (bool)
    {
        address owner = _msgSender();
        uint256 currentAllowance = allowance(owner, spender);
        require(
            currentAllowance >= subtractedValue,
            "ERC20: decreased allowance below zero"
        );
        unchecked {
            _approve(owner, spender, currentAllowance - subtractedValue);
        }

        return true;
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {}

    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {}
}
