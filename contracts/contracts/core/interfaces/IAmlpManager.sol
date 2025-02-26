// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IAmlpManager {
    function amlp() external view returns (address);

    function addLiquidity(uint256 _amount) external;

    function addLiquidityFromVault(uint256 _amount) external;

    function cancelAddLiquidity(address _account, uint256 _amount, uint8 returnType, uint256 _txId) external;

    function removeLiquidityToWallet(uint256 _amlpAmount, bytes memory signature, uint256 timestamp, uint256 nonce) external;

    function removeLiquidityToVault(uint256 _amlpAmount, bytes memory signature, uint256 timestamp, uint256 nonce) external;

    function cancelRemoveLiquidity(address _account, uint256 _amlpAmount, uint256 _txId) external;

    function batchProcessAMLP(address[] calldata addresses, uint8[] calldata isMint, uint256[] calldata tokenAmount, uint256[] calldata redeemAmount, uint256 TVL, uint256 batchId) external;
}
