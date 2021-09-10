// SPDX-License-Identifier: MIT
pragma solidity =0.6.12;

import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IDsgToken.sol";

interface IvDsg {
    function donate(uint256 dsgAmount) external;
}

contract vDsgTreasury is Ownable {

    using EnumerableSet for EnumerableSet.AddressSet;
    EnumerableSet.AddressSet private _callers;

    address public vdsg;
    address public dsg;

    constructor(address _dsg, address _vdsg) public {
        dsg = _dsg;
        vdsg = _vdsg;
    }

    function sendToVDSG() external onlyCaller {
        uint256 _amount = IDsgToken(dsg).balanceOf(address(this));

        require(_amount > 0, "vDsgTreasury: amount exceeds balance");

        IDsgToken(dsg).approve(vdsg, _amount);
        IvDsg(vdsg).donate(_amount);
    }

    function emergencyWithdraw(address _token) public onlyOwner {
        require(IERC20(_token).balanceOf(address(this)) > 0, "vDsgTreasury: insufficient contract balance");
        IERC20(_token).transfer(msg.sender, IERC20(_token).balanceOf(address(this)));
    }

    function addCaller(address _newCaller) public onlyOwner returns (bool) {
        require(_newCaller != address(0), "Treasury: address is zero");
        return EnumerableSet.add(_callers, _newCaller);
    }

    function delCaller(address _delCaller) public onlyOwner returns (bool) {
        require(_delCaller != address(0), "Treasury: address is zero");
        return EnumerableSet.remove(_callers, _delCaller);
    }

    function getCallerLength() public view returns (uint256) {
        return EnumerableSet.length(_callers);
    }

    function isCaller(address _caller) public view returns (bool) {
        return EnumerableSet.contains(_callers, _caller);
    }

    function getCaller(uint256 _index) public view returns (address) {
        require(_index <= getCallerLength() - 1, "Treasury: index out of bounds");
        return EnumerableSet.at(_callers, _index);
    }

    modifier onlyCaller() {
        require(isCaller(msg.sender), "Treasury: not the caller");
        _;
    }
}