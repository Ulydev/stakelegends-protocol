pragma solidity >=0.5.0;

abstract contract ILendingPoolAddressesProvider {

    function getLendingPool() virtual public view returns (address);
    function getLendingPoolCore() virtual public view returns (address payable);

}