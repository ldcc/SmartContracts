pragma solidity >=0.4.22 <0.6.0;

import "./StockInterface.sol";

contract Stock is StockInterface {

    uint256 public constant decimals = 18;

    constructor(string memory _name, string memory _symbol, uint256 _supply, uint256 _costmin, uint256 _costmax, uint8 _costpc, bool _extend) public {
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
        licensees[msg.sender][address(0)] = true;
        licensees[msg.sender][address(this)] = true;
        holderMap[msg.sender].active = true;
        holderMap[msg.sender].amount = supply;
        holderMap[msg.sender].frees = supply;
        holderMap[address(this)].active = true;
        holderList.push(msg.sender);
        holderList.push(address(this));
    }


    /// Implementations

    function balanceOf(address _owner) external view returns (uint256 balance) {
        return this.shareOf(_owner, 1);
    }

    function shareOf(address _owner, uint8 _type) external view returns (uint256 share) {
        Holder memory h = holderMap[_owner];
        if (_type == 1) {
            return h.amount;
        } else if (_type == 2) {
            return h.frees;
        } else {
            return h.amount - h.frees;
        }
    }

    function allowanceOf(address _owner, address _spender) external view returns (uint256 remaining) {
        return allowed[_owner][_spender];
    }

    function licenseOf(address _licensee, address _currency) external view returns (bool licensed) {
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

    function transfer(address _to, uint256 _value) public {
        transfer(_to, _value, 0);
    }

    function transfer(address _to, uint256 _value, uint256 _lockPeriod) public {
        _transfer(msg.sender, _to, _value, _lockPeriod);
        emit Transfer(msg.sender, _to, _value);
    }

    function transferFrom(address _from, address _to, uint256 _value) public {
        transferFrom(_from, _to, _value, 0);
    }

    function transferFrom(address _from, address _to, uint256 _value, uint256 _lockPeriod) public {
        require(allowed[_from][msg.sender] > 0);
        require(allowed[_from][msg.sender] >= _value);
        _transfer(_from, _to, _value, _lockPeriod);
        emit Transfer(_from, _to, _value);
        allowed[_from][msg.sender] -= _value;
    }

    function mulTransfer(address[] memory _tos, uint256[] memory _values) public {
        uint256[] memory _lockPeriods = new uint256[](_tos.length);
        mulTransfer(_tos, _values, _lockPeriods);
    }

    function mulTransfer(address[] memory _tos, uint256[] memory _values, uint256[] memory _lockPeriods) public {
        require(_tos.length == _values.length && _tos.length == _lockPeriods.length);
        for (uint256 i = 0; i < _tos.length; i++) {
            transfer(_tos[i], _values[i], _lockPeriods[i]);
        }
    }

    function withdraw(address payable _to, address _currency, uint256 _value) public {
        require(msg.sender == founder || licensees[msg.sender][_currency]);
        _withdraw(_to, _currency, _value);
        emit Withdraw(_to, _currency, _value);
    }

    function extendSupply(uint256 _value) public {
        require(msg.sender == founder);
        require(extend);
        require(_value > 0);
        Holder storage holder = holderMap[address(this)];
        uint256 oldSupply = supply;
        uint256 oldAmount = holder.amount;
        uint256 oldFrees = holder.frees;
        uint256 extVal = _value * 10 ** decimals;
        supply += extVal;
        holder.amount += extVal;
        holder.frees += extVal;
        assert(supply > oldSupply);
        assert(holder.amount > oldAmount);
        assert(holder.frees > oldFrees);
        emit ExtendSupply(extVal);
    }

    function payDividend(address _currency) public {
        require(msg.sender == founder);
        uint256 thisBalance = address(this).balance;
        for (uint256 i = 1; i < holderList.length; i++) {
            address addr = holderList[i];
            if (holderMap[addr].amount > 0) {
                uint8 percent = uint8(holderMap[addr].amount * 100 / supply);
                _withdraw(address(uint160(addr)), _currency, percent * thisBalance / 100);
            }
        }
        emit PayDividend(msg.sender, _currency);
    }

    function _withdraw(address payable _to, address _currency, uint256 _value) internal {
        if (_currency == address(0)) {
            require(_value > 0);
            require(address(this).balance >= _value);
            _to.transfer(_value);
        } else if (_currency == address(this)) {
            _transfer(_currency, _to, _value, 0);
        } else {
            bytes memory payload = abi.encodeWithSignature("transfer(address,uint256)", _to, _value);
            (bool success,) = _currency.call.gas(90000)(payload);
            require(success);
        }
    }

    function _transfer(address _from, address _to, uint256 _value, uint256 _lockPeriod) private {
        require(_value > costmin);
        Holder storage hf = holderMap[_from];
        require(hf.active);
        require(hf.amount >= _value);
        if (hf.frees < _value) {
            _upgradeHolder(hf);
        }
        require(hf.frees >= _value);
        Holder storage ht = holderMap[_to];
        if (!ht.active) {
            holderList.push(_to);
            ht.active = true;
        }

        // transfer
        uint256 oldHtAmount = ht.amount;
        hf.amount -= _value;
        hf.frees -= _value;
        _value = _deduction(_value);
        ht.amount += _value;
        if (_lockPeriod > 0) {
            Share memory share = Share({
                locks : _value,
                liftedPeriod : _lockPeriod + now});
            ht.shares.push(share);
        } else {
            ht.frees += _value;
        }
        assert(oldHtAmount < ht.amount);
    }

    function _deduction(uint256 _value) private returns (uint256) {
        Holder storage holder = holderMap[address(this)];
        uint256 oldAmount = holder.amount;
        uint256 oldFrees = holder.frees;
        uint256 v = uint256(_value * costpc);
        uint256 cost = uint256(v / 100);
        if (cost < costmin) {
            cost = costmin;
        }
        if (cost > costmax) {
            cost = costmax;
        }
        require(v >= _value && _value >= cost);
        holder.amount += cost;
        holder.frees += cost;
        assert(holder.amount > oldAmount);
        assert(holder.frees > oldFrees);
        return _value - cost;
    }

    function _upgradeHolder(Holder storage _h) private {
        uint256 unlocks = 0;
        for (uint8 i = 0; i < _h.shares.length; i++) {
            if (_h.shares[i].locks == 0) {
                continue;
            }
            if (now >= _h.shares[i].liftedPeriod) {
                unlocks += _h.shares[i].locks;
                delete _h.shares[i];
            }
        }
        if (unlocks > 0) {
            _h.frees += unlocks;
        }
    }
}
