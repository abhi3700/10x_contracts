// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {Router} from "../src/Router.sol";

contract RouterScript is Script {
    Router public router;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        // NOTE: This address is for PancakeSwap Infinity CL PoolManager on BSC.
        router = new Router(0xa0FfB9c1CE1Fe56963B0321B32E7A0302114058b);

        vm.stopBroadcast();
    }
}
