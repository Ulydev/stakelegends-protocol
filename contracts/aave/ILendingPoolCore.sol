pragma solidity >=0.5.0;

abstract contract ILendingPoolCore {

    function getReserveATokenAddress(address _reserve) virtual public view returns (address);

}
