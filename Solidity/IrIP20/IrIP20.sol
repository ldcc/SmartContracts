pragma solidity ^0.4.24;

import "./IrIP20Interface.sol";

contract IrIP20 is IrIP20Interface {

    uint256 public constant decimals = 18;

    constructor(string _name, string _symbol, uint256 _supply, uint256 _costmin, uint256 _costmax, uint8 _costpc, bool _extend) public payable {
        require(_costpc > 0 && _costpc < 100);
        require(_costmin > 0 && _costmin <= _costmax);
        name = _name;
        symbol = _symbol;
        supply = _supply * 10 ** decimals;
        costmin = _costmin;
        costmax = _costmax;
        costpc = _costpc;
        extend = _extend;
        founder = msg.sender;
        balances[msg.sender] = supply;
        licensees[msg.sender][address(0)] = true;
        licensees[msg.sender][address(this)] = true;
    }

    function balanceOf(address _owner) external view returns (uint256) {
        return balances[_owner];
    }

    function allowanceOf(address _owner, address _spender) external view returns (uint256) {
        return allowed[_owner][_spender];
    }

    function licenseOf(address _licensee, address _currency) external view returns (bool) {
        return licensees[_licensee][_currency];
    }

    function approve(address _spender, uint256 _value) public {
        allowed[msg.sender][_spender] = _value;
        emit Approval(msg.sender, _spender, _value);
    }

    function licensing(address _licensee, address _currency, bool _value) public {
        if (_value) {
            require(msg.sender == founder);
        } else {
            require(msg.sender == _licensee);
            require(licensees[_licensee][_currency]);
        }
        licensees[_licensee][_currency] = _value;
        emit Licensing(msg.sender, _licensee, _currency, _value);
    }

    function _transfer(address _from, address _to, uint256 _value) private {
        require(_value > costmin);
        require(balances[_from] >= _value);
        uint256 oldTo = balances[_to];
        balances[_from] -= _value;
        _value = _deduction(_value);
        balances[_to] += _value;
        assert(oldTo < balances[_to]);
    }

    function _deduction(uint256 _value) private returns (uint256) {
        uint256 oldThis = balances[this];
        uint256 v = uint256(_value * costpc);
        uint256 cost = uint256(v / 100);
        if (cost < costmin) {
            cost = costmin;
        }
        if (cost > costmax) {
            cost = costmax;
        }
        require(v >= _value && _value >= cost);
        balances[this] += cost;
        assert(oldThis < balances[this]);
        return _value - cost;
    }

    function transfer(address _to, uint256 _value) public {
        _transfer(msg.sender, _to, _value);
        emit Transfer(msg.sender, _to, _value);
    }

    function transferFrom(address _from, address _to, uint256 _value) public {
        require(allowed[_from][msg.sender] > 0);
        require(allowed[_from][msg.sender] >= _value);
        _transfer(_from, _to, _value);
        emit Transfer(_from, _to, _value);
        allowed[_from][msg.sender] -= _value;
    }

    function mulTransfer(address[] _tos, uint256[] _values) public {
        require(_tos.length == _values.length);
        for (uint256 i = 0; i < _tos.length; i++) {
            transfer(_tos[i], _values[i]);
        }
    }

    function withdraw(address _to, address _currency, uint256 _value) public {
        require(msg.sender == founder || licensees[msg.sender][_currency]);
        if (_currency == address(0)) {
            require(_value > 0);
            require(address(this).balance >= _value);
            _to.transfer(_value);
        } else if (_currency == address(this)) {
            _transfer(_currency, _to, _value);
        } else {
            bytes4 signature = bytes4(keccak256("transfer(address,uint256)"));
            require(_currency.call.gas(90000)(signature, _to, _value));
        }
        emit Withdraw(_to, _currency, _value);
    }

    function extendSupply(uint256 _value) public {
        require(msg.sender == founder);
        require(extend);
        require(_value > 0);
        uint256 extendValue = _value * 10 ** decimals;
        uint256 oldSupply = supply;
        uint256 oldThis = balances[this];
        supply += extendValue;
        balances[this] += extendValue;
        assert(supply > oldSupply);
        assert(balances[this] > oldThis);
        emit ExtendSupply(_value);
    }
}
