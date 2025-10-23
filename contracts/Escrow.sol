// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title Escrow (minimal skeleton)
 * @dev 本文件是“能编译的最小骨架”，只负责“创建一笔待托管的交易记录”，
 *      目的是先把合约结构和事件打通（便于后续前端/脚本订阅事件、拿到 escrowId）。
 *
 * 下一步我们会逐步添加：
 *  - buyer 存款 deposit()
 *  - 双方确认 confirmDelivery()
 *  - 合同放款 releaseFunds()
 *  - 超时退款 refundBuyer()
 *
 * 为什么先做 create？
 *  1 便于用事件把 escrowId 传回脚本/前端。
 *  2 先稳定状态机结构，再往里加“转账相关的易错逻辑”能减少调试成本。
 */

 
contract Escrow {
    /// @dev 一个订单的生命周期状态。此处先给出基础枚举，后续函数会用到。
    enum Status { None, Created , Funded/* Delivered, Released, Refunded */ }

    /**
     * @dev Deal 结构体保存一笔交易的核心元数据。
     * - buyer/seller: 参与双方的钱包地址
     * - amount: 约定金额（单位：wei），当前仅记录，不参与转账
     * - deadline: 可选超时时间戳（秒）。当前先存数值，后续 refund 逻辑会用到
     * - status: 订单状态；此版本只会进入 Created
     */
    struct Deal {
        address buyer;
        address seller;
        uint256 amount;
        uint64  deadline;
        Status  status;
    }

    /// @dev 用 keccak256 生成的唯一 ID => Deal
    mapping(bytes32 => Deal) public deals;

    /// @dev 创建成功后发出事件，前端/脚本可监听拿到 id
    event EscrowCreated(
        bytes32 indexed id,
        address indexed buyer,
        address indexed seller,
        uint256 amount,
        uint64  deadline
    );

    /// @dev 买家成功把钱打入合约时触发
    event FundsDeposited(
        bytes32 indexed id,
        address indexed buyer,
        uint256 amount
    );


    /**
     * @notice 创建一笔“待托管”的交易（不收钱，只登记）
     * @param buyer  买家地址（未来只能由 buyer 存款）
     * @param seller 卖家地址（未来放款会打到 seller）
     * @param amount 约定金额（wei）
     * @param deadline 超时时间戳（秒）；为 0 表示不设超时
     * @return id 本次交易的唯一标识（事件里也会带上）
     *
     * 设计要点：
     *  - 这里允许任何人调用来登记（比如你的 DApp 后端账户或前端用户），
     *    但业务上通常由平台/任意一方发起即可。
     *  - id 采用 (buyer, seller, amount, deadline, block.timestamp) 生成，
     *    足够用于 demo 场景；生产环境还会考虑 nonce/自增等冲突避免策略。
     */
    function createEscrow(
        address buyer,
        address seller,
        uint256 amount,
        uint64  deadline
    ) external returns (bytes32 id) {
        require(buyer != address(0) && seller != address(0), "zero address");
        require(amount > 0, "amount=0");

        // 生成一个“几乎不可能重复”的 id（同一秒内完全相同参数才会碰撞）
        id = keccak256(
            abi.encode(buyer, seller, amount, deadline, block.timestamp)
        );

        // 确保不存在同 id 的订单
        require(deals[id].status == Status.None, "escrow exists");

        // 存储到映射
        deals[id] = Deal({
            buyer: buyer,
            seller: seller,
            amount: amount,
            deadline: deadline,
            status: Status.Created
        });

        // 发事件，便于前端/脚本拿到 id
        emit EscrowCreated(id, buyer, seller, amount, deadline);
    }

    /**
    * @notice 买家把约定金额转进合约，订单状态从 Created -> Funded
    * @param id  createEscrow 返回/事件里拿到的唯一订单 id
    *
    * 关键点：
    * - payable：允许随交易携带 ETH（msg.value）
    * - 只有登记的 buyer 能存款
    * - 存款金额必须与 amount 完全一致（避免少打/多打）
    * - 此时不对外转账，ETH 只“锁”在本合约，后续再 release/refund
    */
    function deposit(bytes32 id) external payable {
        Deal storage d = deals[id];

        // 1) 必须是已创建但未资金托管的订单
        require(d.status == Status.Created, "bad status");

        // 2) 只有登记的 buyer 可以打钱
        require(msg.sender == d.buyer, "only buyer");

        // 3) 存款金额必须与约定金额一致
        require(msg.value == d.amount, "wrong value");

        // 4) 状态切换为 Funded；资金此时已在本合约余额里
        d.status = Status.Funded;

        // 5) 发事件，便于前端/脚本更新 UI
        emit FundsDeposited(id, msg.sender, msg.value);
    }

}
