// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {Diamond} from "../src/Diamond.sol";

contract DeployDiamond is Script {
    function run() external returns (Diamond diamond) {
        address owner = vm.envAddress("OWNER");

        vm.startBroadcast();
        diamond = new Diamond(owner);
        vm.stopBroadcast();

        console.log("Diamond deployed at:", address(diamond));
        console.log("Owner:", owner);
    }
}
