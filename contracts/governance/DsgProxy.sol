// SPDX-License-Identifier: MIT
pragma solidity =0.6.12;

import "@openzeppelin/contracts/proxy/TransparentUpgradeableProxy.sol";

contract DsgProxy is TransparentUpgradeableProxy {

    constructor(address _logic, address admin_) public TransparentUpgradeableProxy(_logic, admin_, ""){

    }
}