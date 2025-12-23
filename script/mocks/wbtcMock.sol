// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.30;

import {MockERC20} from "@chainlink/contracts/src/v0.8/vendor/forge-std/src/mocks/MockERC20.sol";

contract MockCollateral is MockERC20 {
    constructor() {
        initialize("Wrapped Bitcoin", "wBTC", 8);

    }
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}