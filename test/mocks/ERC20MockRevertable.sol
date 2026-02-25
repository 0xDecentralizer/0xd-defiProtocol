// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.30;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ERC20MockRevertable is ERC20 {
    
    bool sohuldTransferFromReturnFalse;

    constructor() ERC20("ERC20Mock", "E20M") {}

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) external {
        _burn(account, amount);
    }

    function setTransferFromRetrunFalse() public {
        sohuldTransferFromReturnFalse = true;
    }

    function setTransferFromRetrunTrue() public {
        sohuldTransferFromReturnFalse = false;
    }
    
    function transferFrom(address from, address to, uint256 value) public override returns (bool) {
        if (sohuldTransferFromReturnFalse) {
            return false;
        }
        super.transferFrom(from, to, value);
    }
}
