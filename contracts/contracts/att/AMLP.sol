// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../tokens/MintableBaseToken.sol";

contract AMLP is MintableBaseToken {
    constructor() public MintableBaseToken("Antarctic Market Making Liquidity Pool Token", "AMLP", 0) {
    }

    function id() external pure returns (string memory _name) {
        return "AMLP";
    }
}
