// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../access/interfaces/IAdmin.sol";
import "./interfaces/IFundingVault.sol";

contract FundingVault is IFundingVault, ReentrancyGuard {
    using ECDSA for bytes32;
    using SafeERC20 for IERC20;

    mapping(address => mapping(address => uint256)) public balanceOf; // token => user => balance
    mapping(address => bool) public isHandler;
    mapping(address => bool) public isManager;
    mapping(address => bool) public supportedTokens; // token => supported

    // Admin contract
    IAdmin public admin;

    event Deposited(address indexed token, address indexed from, uint256 amount);
    event Withdrawn(address indexed token, address indexed from, address indexed to, uint256 amount);
    event TransferredToTradingVault(address indexed token, address indexed user, uint256 amount, address tradingAddress, uint256 timestamp);
    event TransferredFromTradingVault(address indexed token, address indexed from, address indexed user, uint256 amount);
    event UserBalanceUpdated(address indexed token, address indexed user, uint256 newBalance);
    event TokenSupportUpdated(address indexed token, bool isSupported);
    event LiquidityAdded(address _token, address _fundingAccount, uint256 _amount);

    constructor(address _admin) {
        require(_admin != address(0));
        admin = IAdmin(_admin);
    }

    modifier onlySupportedToken(address token) {
        require(supportedTokens[token], "Token is not supported");
        _;
    }

    modifier onlyAdmin() {
        require(
            admin.isAdmin(msg.sender),
            "Only admin can call this function."
        );
        _;
    }

    function deposit(address token, uint256 amount) external onlySupportedToken(token) nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        balanceOf[token][msg.sender] += amount;
        emit Deposited(token, msg.sender, amount);
        emit UserBalanceUpdated(token, msg.sender, balanceOf[token][msg.sender]);
    }

    function transferToTradingVault(address token, uint256 amount, address tradingAddress, uint256 timestamp, bytes memory signature) external onlySupportedToken(token) nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        require(balanceOf[token][msg.sender] >= amount, "Insufficient user balance");
        // Verify the signature
        require(
            checkTransferSignature(
                signature,
                msg.sender,
                token,
                amount,
                tradingAddress,
                timestamp
            ),
            "Invalid signature. Verification failed"
        );
        balanceOf[token][msg.sender] -= amount;
        IERC20(token).safeTransfer(tradingAddress, amount);
        emit TransferredToTradingVault(token, msg.sender, amount, tradingAddress, timestamp);
        emit UserBalanceUpdated(token, msg.sender, balanceOf[token][msg.sender]);
    }

    function depositAndTransferToTradingVault(address token, uint256 amount, address tradingAddress, uint256 timestamp, bytes memory signature) external onlySupportedToken(token) nonReentrant {
        require(amount > 0, "Amount must be greater than 0");

        // Deposit the amount
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        emit Deposited(token, msg.sender, amount);

        // Verify the signature
        require(checkTransferSignature(signature, msg.sender, token, amount, tradingAddress, timestamp), "Invalid signature. Verification failed");

        // Transfer to trading vault
        IERC20(token).safeTransfer(tradingAddress, amount);
        emit TransferredToTradingVault(token, msg.sender, amount, tradingAddress, timestamp);
    }

    function transferFromTradingVault(address token, uint256 amount, address user) external onlySupportedToken(token) nonReentrant {
        _validateHandler();
        require(amount > 0, "Amount must be greater than 0");
        require(IERC20(token).balanceOf(msg.sender) >= amount, "Insufficient balance in hot wallet");
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        balanceOf[token][user] += amount;
        emit TransferredFromTradingVault(token, msg.sender, user, amount);
        emit UserBalanceUpdated(token, user, balanceOf[token][user]);
    }

    function batchTransferFromTradingVault(address[] calldata tokens, uint256[] calldata amounts, address[] calldata users) external nonReentrant {
        _validateHandler();
        require(tokens.length == amounts.length && amounts.length == users.length, "Tokens, amounts and users length mismatch");
        for (uint256 i = 0; i < users.length; i++) {
            address token = tokens[i];
            uint256 amount = amounts[i];
            address user = users[i];
            require(supportedTokens[token], "Token is not supported");
            require(amount > 0, "Amount must be greater than 0");
            require(IERC20(token).balanceOf(msg.sender) >= amount, "Insufficient balance in hot wallet");
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
            balanceOf[token][user] += amount;
            emit TransferredFromTradingVault(token, msg.sender, user, amount);
            emit UserBalanceUpdated(token, user, balanceOf[token][user]);
        }
    }

    function withdraw(address token, uint256 amount) external onlySupportedToken(token) nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        require(balanceOf[token][msg.sender] >= amount, "Insufficient user balance");
        balanceOf[token][msg.sender] -= amount;
        IERC20(token).safeTransfer(msg.sender, amount);
        emit Withdrawn(token, address(this), msg.sender, amount);
        emit UserBalanceUpdated(token, msg.sender, balanceOf[token][msg.sender]);
    }

    function withdrawFromTradingAccount(address token, uint256 amount, address user) external onlySupportedToken(token) nonReentrant {
        _validateHandler();
        require(amount > 0, "Amount must be greater than 0");
        require(IERC20(token).balanceOf(msg.sender) >= amount, "Insufficient balance in trading vault");
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(token).safeTransfer(user, amount);
        emit Withdrawn(token, msg.sender, user, amount);
    }

    function batchWithdrawFromTradingVault(address[] calldata tokens, uint256[] calldata amounts, address[] calldata users) external nonReentrant {
        _validateHandler();
        require(tokens.length == amounts.length && amounts.length == users.length, "Tokens, amounts and users length mismatch");
        for (uint256 i = 0; i < users.length; i++) {
            address token = tokens[i];
            uint256 amount = amounts[i];
            address user = users[i];
            require(supportedTokens[token], "Token is not supported");
            require(amount > 0, "Amount must be greater than 0");
            require(IERC20(token).balanceOf(msg.sender) >= amount, "Insufficient balance in hot wallet");
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
            IERC20(token).safeTransfer(user, amount);
            emit Withdrawn(token, msg.sender, user, amount);
        }
    }

    function addLiquidity(address _account, address _token, uint256 _amount) external override onlySupportedToken(_token) nonReentrant {
        _validateManager();
        require(_amount > 0, "Amount must be greater than 0");
        require(balanceOf[_token][_account] >= _amount, "Insufficient user balance");
        balanceOf[_token][_account] -= _amount;
        IERC20(_token).safeTransfer(msg.sender, _amount);
        emit UserBalanceUpdated(_token, _account, balanceOf[_token][_account]);
    }

    function removeLiquidity(address _account, address _token, uint256 _amount) external override onlySupportedToken(_token) nonReentrant {
        _validateManager();
        require(_amount > 0, "Amount must be greater than 0");
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
        balanceOf[_token][_account] += _amount;
        emit UserBalanceUpdated(_token, _account, balanceOf[_token][_account]);
    }

    function setHandler(address _handler, bool _isActive) external onlyAdmin {
        isHandler[_handler] = _isActive;
    }

    function setManager(address _manager, bool _isManager) external onlyAdmin {
        isManager[_manager] = _isManager;
    }

    function updateTokenSupport(address token, bool isSupported) external onlyAdmin {
        supportedTokens[token] = isSupported;
        emit TokenSupportUpdated(token, isSupported);
    }

    function _validateHandler() private view {
        require(isHandler[msg.sender], "FundingVault: forbidden");
    }

    function _validateManager() private view {
        require(isManager[msg.sender], "FundingVault: forbidden");
    }

    function getBalance(address token) external view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    function getUserBalance(address token, address user) external view returns (uint256) {
        return balanceOf[token][user];
    }

    // Function to check if admin was the message signer
    function checkTransferSignature(
        bytes memory signature,
        address user,
        address token,
        uint256 amount,
        address tradingAddress,
        uint256 timestamp
    ) public view returns (bool) {
        return
            admin.isAdmin(
            getTransferSigner(
                signature,
                user,
                token,
                amount,
                tradingAddress,
                timestamp
            )
        );
    }

    function getTransferSigner(
        bytes memory signature,
        address user,
        address token,
        uint256 amount,
        address tradingAddress,
        uint256 timestamp
    ) public view returns (address) {
        bytes32 hash = keccak256(
            abi.encodePacked(
                user,
                token,
                amount,
                tradingAddress,
                timestamp,
                address(this)
            )
        );
        bytes32 messageHash = hash.toEthSignedMessageHash();
        return messageHash.recover(signature);
    }
}
