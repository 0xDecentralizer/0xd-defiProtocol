// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DSCEngine dscEngine;
    DecentralizedStableCoin dscToken;
    HelperConfig config;
    address wethUsdPriceFeed;
    address weth;

    function setUp() public {
        deployer = new DeployDSC();
        (dscToken, dscEngine, config) = deployer.run();
        (wethUsdPriceFeed,, weth,, ) = config.activeNetworkConfig();
    }

    function testGetUsdValue() public {
        uint256 amount = 3;
        uint256 expectedUsd = 9_000;
        uint256 actualUsd = dscEngine.getUsdValue(weth, amount);

        assertEq(expectedUsd, actualUsd, "Invalid USD calculation!");
    }
}