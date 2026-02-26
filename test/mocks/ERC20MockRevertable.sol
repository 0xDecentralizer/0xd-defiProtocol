// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.30;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ERC20MockRevertable is ERC20 {
    
    bool public shouldRevert;

    constructor() ERC20("ERC20Mock", "E20M") {}

    function mint(address account, uint256 amount) external returns (bool) {
        if (shouldRevert) {
            return false;
        }
        _mint(account, amount);
        return true;
    }

    function burn(address account, uint256 amount) external {
        _burn(account, amount);
    }

    function setShouldRevertTrue() public {
        shouldRevert = true;
    }

    function setShouldRevertFalse() public {
        shouldRevert = false;
    }
    
    function transferFrom(address from, address to, uint256 value) public override returns (bool) {
        return false;
    }
}
