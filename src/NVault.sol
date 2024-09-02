// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

error TransferFailed();

import {Ownable} from "../lib/solady/src/auth/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract NVault is Ownable {
    using SafeERC20 for IERC20;



    event FeeReceived(address sender, uint256 amount);


    receive() external payable {
        emit FeeReceived(msg.sender, msg.value);
    }

    function reciveFee() external payable {
        emit FeeReceived(msg.sender, msg.value);
    }


    function withdraw() external onlyOwner {
        address wallet1 = 0x55566CC462F8A2634B4Ce8927fD9904B0E470497;
        address wallet2 = 0x269A0edB6885A6481157977020596200425FdAaf;

        uint256 totalBalance = address(this).balance;
        uint256 wallet1Amount = totalBalance / 2;
        uint256 wallet2Amount = totalBalance - wallet1Amount;

        (bool wallet1Success,) = wallet1.call{value: wallet1Amount}("");
        if (!wallet1Success) revert TransferFailed();

        (bool wallet2Success,) = wallet2.call{value: wallet2Amount}("");
        if (!wallet2Success) revert TransferFailed();
    }

    function withdrawERC20(IERC20 token) external onlyOwner {
        uint256 balance = token.balanceOf(address(this));
        token.safeTransfer(owner(), balance);
    }
}