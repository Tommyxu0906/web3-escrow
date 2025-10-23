// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Escrow.sol";

/**
 * @title BuyerProxy
 * @dev 一个最小的“买家代理合约”，用于从它自己的地址发起 deposit。
 *      这样我们在测试里把 buyer 设置为这个代理的地址，即可不使用 cheatcodes。
 */
contract BuyerProxy {
    // 允许接收 ETH，方便在测试里给它打钱
    receive() external payable {}

    /**
     * @notice 从本合约（作为 buyer）调用 Escrow.deposit，并携带指定金额
     */
    function depositAsBuyer(address escrow, bytes32 id, uint256 amount) external {
        Escrow(escrow).deposit{value: amount}(id);
    }
}

/**
 * @title EscrowTest
 * @dev 使用纯 Solidity 测试 Escrow 的 createEscrow 和 deposit 流程
 *      通过 BuyerProxy 模拟“买家地址”发送交易，不依赖 vm.prank/ethers/viem。
 */
contract EscrowTest {
    function test_CreateAndDeposit() public {
        // 1) 部署被测合约
        Escrow e = new Escrow();

        // 2) 部署买家代理合约；把它当作 buyer
        BuyerProxy buyer = new BuyerProxy();
        address seller = address(0xCAFE);
        uint256 amount = 0.01 ether;
        uint64 deadline = uint64(block.timestamp + 300);

        // 3) 创建订单（不转钱）。注意：createEscrow 允许任何人调用
        bytes32 id = e.createEscrow(address(buyer), seller, amount, deadline);
        require(id != bytes32(0), "id should not be zero");

        // 4) 给“买家代理”打钱（让它有钱可付）
        (bool okFund, ) = address(buyer).call{value: amount}("");
        require(okFund, "fund buyer failed");

        // 5) 记录存款前余额（合约余额应为 0）
        uint256 beforeBal = address(e).balance;
        require(beforeBal == 0, "escrow balance should start at 0");

        // 6) 让“买家代理”作为 buyer 调用 deposit，携带正确金额
        //    注意：msg.sender 将是 BuyerProxy 的地址（与 create 时登记的一致）
        buyer.depositAsBuyer(address(e), id, amount);

        // 7) 合约余额应增加到 amount，资金被锁定
        uint256 afterBal = address(e).balance;
        require(afterBal == amount, "escrow balance should equal amount after deposit");
    }

    // 允许测试合约接收和中转 ETH（上面的 call 需要有余额从当前合约发出）
    receive() external payable {}
}
