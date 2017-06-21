pragma solidity ^0.4.11;

import "./Base.sol";

//ToDo: write tests for methods with modifier validMsgDataLen(20+32)

contract ERC20 {

    function totalSupply() constant returns (uint256 totalSupply) {}
    function balanceOf(address _owner) constant returns (uint256 balance);
    function transfer(address _to, uint256 _value) returns (bool success);
    function transferFrom(address _from, address _to, uint256 _value) returns (bool success);
    function approve(address _spender, uint256 _value) returns (bool success);
    function allowance(address _owner, address _spender) constant returns (uint256 remaining);

    event Transfer(address indexed _from, address indexed _to, uint256 _value);
    event Approval(address indexed _owner, address indexed _spender, uint256 _value);

}

contract ERC20ModuleSupport {
    function _fulfillPreapprovedPayment(address _from, address _to, uint _value, address msg_sender) public returns(bool success);
    function _fulfillPayment(address _from, address _to, uint _value, uint subId, address msg_sender) public returns (bool success);
    function _mintFromDeposit(address owner, uint amount) public;
    function _burnForDeposit(address owner, uint amount) public returns(bool success);
}

contract ERC20Impl is ERC20, Base {

    function transfer(address _to, uint256 _value) isRunningOnly validMsgDataLen(20+32) returns (bool success) {
        if (balances[msg.sender] >= _value && balances[_to] + _value > balances[_to]) {
            balances[msg.sender] -= _value;
            balances[_to] += _value;
            Transfer(msg.sender, _to, _value);
            return true;
        } else { return false; }
    }

    function transferFrom(address _from, address _to, uint256 _value) isRunningOnly validMsgDataLen(20+20+32) returns (bool success) {
        if (balances[_from] >= _value && allowed[_from][msg.sender] >= _value && balances[_to] + _value > balances[_to]) {
            balances[_to] += _value;
            balances[_from] -= _value;
            allowed[_from][msg.sender] -= _value;
            Transfer(_from, _to, _value);
            return true;
        } else { return false; }
    }

    function balanceOf(address _owner) constant returns (uint256 balance) {
        return balances[_owner];
    }

    function approve(address _spender, uint256 _value) isRunningOnly validMsgDataLen(20+32) returns (bool success) {
        allowed[msg.sender][_spender] = _value;
        Approval(msg.sender, _spender, _value);
        return true;
    }

    function allowance(address _owner, address _spender) constant returns (uint256 remaining) {
        return allowed[_owner][_spender];
    }

    mapping (address => uint256) balances;
    mapping (address => mapping (address => uint256)) allowed;

    uint256 public totalSupply;
    bool    public isRunning = false;

    modifier onlyHolder(address holder) {
        if (balanceOf(holder) == 0) throw;
        _;
    }

    modifier isRunningOnly() {
        if (!isRunning) throw;
        _;
    }

    modifier isNotRunningOnly() {
        if (isRunning) throw;
        _;
    }

}
