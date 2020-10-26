pragma solidity >=0.5.0;

abstract contract IAToken {

    function redeem(uint256 _amount) virtual external;
    function balanceOf(address _user) virtual public view returns(uint256);

}
