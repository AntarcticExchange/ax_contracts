//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IAdmin {
    function setAdmin(address _admin) external;
    function isAdmin(address user) external view returns (bool);
}
