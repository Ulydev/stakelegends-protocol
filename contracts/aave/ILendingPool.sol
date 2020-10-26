pragma solidity >=0.5.0;

abstract contract ILendingPool {

    function deposit(address _reserve, uint256 _amount, uint16 _referralCode) virtual external payable;

}
