// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployDSC is Script {
    address[] collaterals;
    address[] priceFeeds;
    DSCEngine dscEngine;
    DecentralizedStableCoin dscToken;


    function run() external returns (DecentralizedStableCoin, DSCEngine, HelperConfig) {
        HelperConfig config = new HelperConfig();
        (address wethPriceFeed, address wbtcPriceFeed, address weth, address wbtc, uint256 deployerKey) = config.activeNetworkConfig();
        collaterals = [weth, wbtc];
        priceFeeds = [wethPriceFeed, wbtcPriceFeed];

        vm.startBroadcast(deployerKey);
        dscToken = new DecentralizedStableCoin(msg.sender);
        dscEngine = new DSCEngine(collaterals, priceFeeds, address(dscToken));
        dscToken.transferOwnership(address(dscEngine));
        vm.stopBroadcast();

        return (dscToken, dscEngine, config);
    }
}