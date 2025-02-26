// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IFundingVault {
    function addLiquidity(address _fundingAccount, address _token, uint256 _amount) external;

    function removeLiquidity(address _account, address _token, uint256 _amount) external;
}
