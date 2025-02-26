// SPDX-License-Identifier: MIT

import "./interfaces/IFundingVault.sol";
import "./interfaces/IAmlpManager.sol";
import "../tokens/interfaces/IMintable.sol";
import "../access/Governable.sol";
import "../access/interfaces/IAdmin.sol";

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

pragma solidity ^0.8.0;

contract AmlpManager is ReentrancyGuard, Governable, IAmlpManager {
    using ECDSA for bytes32;
    using SafeERC20 for IERC20;

    uint256 public constant PRICE_PRECISION = 10 ** 30;
    uint256 public constant AMLP_DECIMALS = 10 ** 18;
    IFundingVault public fundingVault;
    address public override amlp;
    address public usdt;
    address public exVault;

    // Admin contract
    IAdmin public admin;

    mapping(address => uint256) public userDeposits;
    mapping(address => uint256) public userWithdraws;
    mapping(uint256 => bool) public batchIds;
    mapping(uint256 => bool) public txIds;

    bool public inPrivateMode;
    mapping(address => bool) public isHandler;

    event PoolDeposit(address indexed account, uint256 amount, uint8 _type);
    event PoolWithdraw(address indexed account, uint256 amlpAmount, uint8 _type, uint256 nonce);
    event CancelAddLiquidity(address indexed account, uint256 amount, uint8 _type);
    event CancelRemoveLiquidity(address indexed account, uint256 amlpAmount);

    event AddLiquidity(
        address account,
        uint256 usdtAmount,
        uint256 amlpAmount,
        uint256 TVL
    );

    event RemoveLiquidity(
        address account,
        uint256 usdtAmount,
        uint256 amlpAmount,
        uint256 TVL
    );

    constructor(
        address _amlp,
        address _fundingVault,
        address _exVault,
        address _usdt,
        address _admin
    ) {
        gov = msg.sender;
        amlp = _amlp;
        usdt = _usdt;
        exVault = _exVault;
        fundingVault = IFundingVault(_fundingVault);
        require(_admin != address(0), 'AmlpManager: invalid _admin');
        admin = IAdmin(_admin);
    }

    modifier onlyInPrivateMode() {
        require(!inPrivateMode, "AmlpManager: action not enabled");
        _;
    }

    function setInPrivateMode(bool _inPrivateMode) external onlyGov {
        inPrivateMode = _inPrivateMode;
    }

    function setHandler(address _handler, bool _isActive) external onlyGov {
        isHandler[_handler] = _isActive;
    }

    function setExVault(address _exVault) external onlyGov {
        exVault = _exVault;
    }

    function addLiquidity(uint256 _amount) external override nonReentrant onlyInPrivateMode {
        require(_amount > 0, "AmlpManager: invalid _amount");

        IERC20(usdt).safeTransferFrom(msg.sender, address(this), _amount);
        userDeposits[msg.sender] += _amount;

        emit PoolDeposit(msg.sender, _amount, 0);
    }

    function addLiquidityFromVault(uint256 _amount) external override nonReentrant onlyInPrivateMode {
        fundingVault.addLiquidity(msg.sender, usdt, _amount);
        userDeposits[msg.sender] += _amount;

        emit PoolDeposit(msg.sender, _amount, 1);
    }

    function cancelAddLiquidity(address _account, uint256 _amount, uint8 _type, uint256 _txId) external override {
        _validateHandler();
        require(_type == 0 || _type == 1, "AmlpManager: invalid _type");
        require(!txIds[_txId], "TE");

        txIds[_txId] = true;

        if (_type == 0) {
            _cancelAddLiquidityToWallet(_account, _amount);
        } else {
            _cancelAddLiquidityToVault(_account, _amount);
        }
    }

    function _cancelAddLiquidityToWallet(address _account, uint256 _amount) private {
        require(userDeposits[_account] >= _amount, "AmlpManager: insufficient deposit");
        require(IERC20(usdt).balanceOf(address(this)) >= _amount, "AmlpManager: insufficient balance");

        userDeposits[_account] -= _amount;
        IERC20(usdt).safeTransfer(_account, _amount);

        emit CancelAddLiquidity(_account, _amount, 0);
    }

    function _cancelAddLiquidityToVault(address _account, uint256 _amount) private {
        require(userDeposits[_account] >= _amount, "AmlpManager: insufficient deposit");
        require(IERC20(usdt).balanceOf(address(this)) >= _amount, "AmlpManager: insufficient balance");

        userDeposits[_account] -= _amount;
        IERC20(usdt).approve(address(fundingVault), _amount);
        fundingVault.removeLiquidity(_account, usdt, _amount);

        emit CancelAddLiquidity(_account, _amount, 1);
    }

    function removeLiquidityToWallet(uint256 _amlpAmount, bytes memory signature, uint256 timestamp, uint256 nonce) external override nonReentrant onlyInPrivateMode {
        require(block.timestamp > timestamp, "AmlpManager: remove amlp cooldown duration not yet passed");
        require(checkRemoveLiquiditySignature(signature, msg.sender, _amlpAmount, timestamp, nonce), "Invalid signature. Verification failed");
        _poolWithdraw(_amlpAmount);
        emit PoolWithdraw(msg.sender, _amlpAmount, 0, nonce);
    }

    function removeLiquidityToVault(uint256 _amlpAmount, bytes memory signature, uint256 timestamp, uint256 nonce) external override nonReentrant onlyInPrivateMode {
        require(block.timestamp > timestamp, "AmlpManager: remove amlp cooldown duration not yet passed");
        _poolWithdraw(_amlpAmount);
        require(checkRemoveLiquiditySignature(signature, msg.sender, _amlpAmount, timestamp, nonce), "Invalid signature. Verification failed");
        emit PoolWithdraw(msg.sender, _amlpAmount, 1, nonce);
    }

    function _poolWithdraw(uint256 _amlpAmount) private {
        require(_amlpAmount > 0, "AmlpManager: invalid _amlpAmount");

        userWithdraws[msg.sender] += _amlpAmount;
        IERC20(amlp).safeTransferFrom(msg.sender, address(this), _amlpAmount);
    }

    function cancelRemoveLiquidity(address _account, uint256 _amlpAmount, uint256 _txId) external override nonReentrant {
        _validateHandler();
        require(!txIds[_txId], "AmlpManager: transaction already executed");

        txIds[_txId] = true;
        _cancelPoolWithdraw(_account, _amlpAmount);

        emit CancelRemoveLiquidity(_account, _amlpAmount);
    }

    function _cancelPoolWithdraw(address _account, uint256 _amlpAmount) private {
        require(userWithdraws[_account] >= _amlpAmount, "AmlpManager: insufficient withdraw amount");
        require(IERC20(amlp).balanceOf(address(this)) >= _amlpAmount, "AmlpManager: insufficient balance");

        userWithdraws[_account] -= _amlpAmount;
        IERC20(amlp).safeTransfer(_account, _amlpAmount);
    }

    function batchProcessAMLP(
        address[] calldata addresses,
        uint8[] calldata isMint,
        uint256[] calldata tokenAmount,
        uint256[] calldata redeemAmount,
        uint256 TVL,
        uint256 batchId
    ) external override nonReentrant {
        _validateHandler();
        require(addresses.length > 0, "AmlpManager: invalid addresses length");
        require(addresses.length == isMint.length, "AmlpManager: invalid token length");
        require(isMint.length == tokenAmount.length, "AmlpManager: invalid tokenAmount length");
        require(TVL >= 0, "AmlpManager: invalid TVL");
        require(!batchIds[batchId], "BE");

        batchIds[batchId] = true;

        uint256 USDTAmount = 0;
        uint256 lpTotalSupply = IERC20(amlp).totalSupply();

        if (TVL == 0) require(lpTotalSupply == 0, "AmlpManager: TVL must be > 0");

        for (uint256 i = 0; i < addresses.length; i++) {
            if (isMint[i] == 0) {
                _addLiquidity(addresses[i], tokenAmount[i], TVL, lpTotalSupply);
                USDTAmount += tokenAmount[i];
            } else {
                _removeLiquidity(addresses[i], tokenAmount[i], redeemAmount[i], TVL, isMint[i]);
            }
        }
        IERC20(usdt).safeTransfer(exVault, USDTAmount);
    }

    function _addLiquidity(
        address _account,
        uint256 _usdtAmount,
        uint256 TVL,
        uint256 totalSupply
    ) private {
        require(_usdtAmount > 0, "AmlpManager: invalid _amount");
        require(userDeposits[_account] >= _usdtAmount, "AmlpManager: insufficient deposit");

        uint256 shares = (totalSupply == 0) ? _usdtAmount * PRICE_PRECISION / AMLP_DECIMALS : (_usdtAmount * totalSupply) / TVL;

        userDeposits[_account] -= _usdtAmount;
        IMintable(amlp).mint(_account, shares);

        emit AddLiquidity(_account, _usdtAmount, shares, TVL);
    }

    function _removeLiquidity(
        address _account,
        uint256 _amlpAmount,
        uint256 redeemAmount,
        uint256 TVL,
        uint8 _redeemType
    ) private {
        require(_amlpAmount > 0, "AmlpManager: invalid _amlpAmount");
        require(userWithdraws[_account] >= _amlpAmount, "AmlpManager: insufficient withdraw amount");

        userWithdraws[_account] -= _amlpAmount;
        IMintable(amlp).burn(address(this), _amlpAmount);

        require(IERC20(usdt).balanceOf(address(this)) >= redeemAmount, "AmlpManager: insufficient USDT balance");

        if (_redeemType == 1) {
            IERC20(usdt).safeTransfer(_account, redeemAmount);
        } else if (_redeemType == 2) {
            IERC20(usdt).approve(address(fundingVault), redeemAmount);
            fundingVault.removeLiquidity(_account, usdt, redeemAmount);
        } else {
            revert("AmlpManager: invalid redeemType");
        }

        emit RemoveLiquidity(_account, redeemAmount, _amlpAmount, TVL);
    }

    function _validateHandler() private view {
        require(isHandler[msg.sender], "AmlpManager: forbidden");
    }


    function checkRemoveLiquiditySignature(
        bytes memory signature,
        address user,
        uint256 lpAmount,
        uint256 timestamp,
        uint256 nonce
    ) public view returns (bool) {
        return
            admin.isAdmin(
            getRemoveLiquiditySigner(signature, user, lpAmount, timestamp, nonce)
        );
    }

    function getRemoveLiquiditySigner(
        bytes memory signature,
        address user,
        uint256 lpAmount,
        uint256 timestamp,
        uint256 nonce
    ) public view returns (address) {
        bytes32 hash = keccak256(
            abi.encodePacked(
                user,
                lpAmount,
                timestamp,
                nonce
            )
        );
        bytes32 messageHash = hash.toEthSignedMessageHash();
        return messageHash.recover(signature);
    }

}
