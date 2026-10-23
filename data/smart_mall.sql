-- ============================================================
-- 「智选商城」智能客服系统 - 数据库初始化脚本
-- 库名: smart_mall    字符集: utf8mb4
-- 用法: mysql -uroot -proot < init.sql
-- ============================================================
CREATE DATABASE IF NOT EXISTS `smart_mall` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
USE `smart_mall`;

-- ============================================================
-- 1. 用户表
-- ============================================================
DROP TABLE IF EXISTS `t_user`;
CREATE TABLE `t_user` (
  `id`         BIGINT       NOT NULL AUTO_INCREMENT COMMENT '主键',
  `username`   VARCHAR(50)  NOT NULL COMMENT '登录账号',
  `password`   VARCHAR(64)  NOT NULL COMMENT '密码（MD5 + 盐 mini_mall_2026）',
  `nickname`   VARCHAR(50)  DEFAULT NULL COMMENT '昵称（与订单表 username 对齐）',
  `role`       TINYINT      NOT NULL DEFAULT 0 COMMENT '角色：0 普通用户，1 管理员',
  `status`     TINYINT      NOT NULL DEFAULT 1 COMMENT '状态：0 禁用，1 启用',
  `deleted`    TINYINT      NOT NULL DEFAULT 0 COMMENT '逻辑删除：0 正常，1 已删',
  `create_time`DATETIME     DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `update_time`DATETIME     DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_username` (`username`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='用户表';

-- ============================================================
-- 2. 商品表（管理员 CRUD；与 RAG 知识库无关联）
-- ============================================================
DROP TABLE IF EXISTS `t_product`;
CREATE TABLE `t_product` (
  `id`          BIGINT        NOT NULL AUTO_INCREMENT COMMENT '主键',
  `name`        VARCHAR(100)  NOT NULL COMMENT '商品名称（与订单明细 product_name 对齐）',
  `price`       DECIMAL(10,2) NOT NULL DEFAULT 0.00 COMMENT '售价',
  `category`    VARCHAR(50)   NOT NULL COMMENT '类别：手机/耳机/笔记本...',
  `brand`       VARCHAR(50)   DEFAULT NULL COMMENT '品牌',
  `description` VARCHAR(500)  DEFAULT NULL COMMENT '商品描述',
  `status`      TINYINT       NOT NULL DEFAULT 1 COMMENT '状态：0 下架，1 上架',
  `deleted`     TINYINT       NOT NULL DEFAULT 0 COMMENT '逻辑删除：0 正常，1 已删',
  `create_time` DATETIME      DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `update_time` DATETIME      DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  PRIMARY KEY (`id`),
  KEY `idx_name` (`name`),
  KEY `idx_category` (`category`),
  KEY `idx_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='商品表';

-- ============================================================
-- 3. 订单主表（一对多的"一"）
-- ============================================================
DROP TABLE IF EXISTS `t_order`;
CREATE TABLE `t_order` (
  `id`          BIGINT        NOT NULL AUTO_INCREMENT COMMENT '主键',
  `order_no`    VARCHAR(32)   NOT NULL COMMENT '订单号',
  `user_id`     BIGINT        NOT NULL COMMENT '下单用户 id（关联 t_user.id）',
  `username`    VARCHAR(50)   NOT NULL COMMENT '下单用户名（冗余，便于 AI 查询与展示）',
  `total_amount`DECIMAL(10,2) NOT NULL DEFAULT 0.00 COMMENT '订单总金额',
  `status`      VARCHAR(20)   NOT NULL COMMENT '状态：已支付/已发货/已完成',
  `create_time` DATETIME      DEFAULT CURRENT_TIMESTAMP COMMENT '下单时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_order_no` (`order_no`),
  KEY `idx_user_id` (`user_id`),
  KEY `idx_username` (`username`),
  KEY `idx_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='订单主表';

-- ============================================================
-- 4. 订单明细表（一对多的"多"，一个订单可含多个商品）
-- ============================================================
DROP TABLE IF EXISTS `t_order_item`;
CREATE TABLE `t_order_item` (
  `id`          BIGINT        NOT NULL AUTO_INCREMENT COMMENT '主键',
  `order_id`    BIGINT        NOT NULL COMMENT '所属订单 id（关联 t_order.id）',
  `product_id`  BIGINT        DEFAULT NULL COMMENT '商品 id（关联 t_product.id）',
  `product_name`VARCHAR(100)  NOT NULL COMMENT '商品名称（下单时快照）',
  `price`       DECIMAL(10,2) NOT NULL COMMENT '单价（下单时快照）',
  `quantity`    INT           NOT NULL DEFAULT 1 COMMENT '购买数量',
  `subtotal`    DECIMAL(10,2) NOT NULL COMMENT '小计 = price × quantity',
  PRIMARY KEY (`id`),
  KEY `idx_order_id` (`order_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='订单明细表';

-- ============================================================
-- 5. 会话表（会话元数据，供左侧列表 / 管理端使用）
-- ============================================================
DROP TABLE IF EXISTS `t_session`;
CREATE TABLE `t_session` (
  `id`          BIGINT       NOT NULL AUTO_INCREMENT COMMENT '主键',
  `session_id`  VARCHAR(64)  NOT NULL COMMENT '会话 UUID（= LangChain4j 的 @MemoryId）',
  `user_id`     BIGINT       NOT NULL COMMENT '所属用户 id',
  `title`       VARCHAR(100) NOT NULL DEFAULT '新会话' COMMENT '会话标题（首句截断）',
  `deleted`     TINYINT      NOT NULL DEFAULT 0 COMMENT '逻辑删除：0 正常，1 已删',
  `create_time` DATETIME     DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `update_time` DATETIME     DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '最后活跃时间',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_session_id` (`session_id`),
  KEY `idx_user_id` (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='会话表';

-- ============================================================
-- 6. 消息表（ChatMemoryStore 的落地表，全量覆盖语义）
-- content  = 纯文本，供前端 / 管理端直接展示
-- message_json = 完整 ChatMessage 序列化，供记忆精确重建
-- ★ 不能省: AiMessage 里还有 thinking 字段
-- DeepSeek 思考模式要求它原样回传，否则工具调用第二轮 400
-- ============================================================
DROP TABLE IF EXISTS `t_chat_message`;
CREATE TABLE `t_chat_message` (
  `id`           BIGINT        NOT NULL AUTO_INCREMENT COMMENT '主键',
  `session_id`   VARCHAR(64)   NOT NULL COMMENT '会话 UUID',
  `seq`          INT           NOT NULL COMMENT '窗口内顺序（每次覆盖重排 0..n-1）',
  `role`         VARCHAR(16)   NOT NULL COMMENT '角色：system/user/ai/tool',
  `content`      MEDIUMTEXT    COMMENT '纯文本内容（供展示）',
  `message_json` MEDIUMTEXT    COMMENT '完整 ChatMessage JSON（供记忆重建）',
  `create_time`  DATETIME      DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  PRIMARY KEY (`id`),
  KEY `idx_session_seq` (`session_id`, `seq`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='会话消息表';

-- ============================================================
-- 预置数据
-- 密码算法：MD5(明文 + "mini_mall_2026")
-- admin123  -> 7eca1b0a854dd5dc29995c68a9a4bb02
-- 123456    -> 61bd06a2dc8d29ab50f2b8726f65d4fb
-- ============================================================
INSERT INTO `t_user` (`id`, `username`, `password`, `nickname`, `role`, `status`) VALUES
(1, 'admin',  '7eca1b0a854dd5dc29995c68a9a4bb02', '系统管理员', 1, 1),
(2, 'zhangsan','61bd06a2dc8d29ab50f2b8726f65d4fb','张三',     0, 1),
(3, 'lisi',   '61bd06a2dc8d29ab50f2b8726f65d4fb','李四',     0, 1);

-- 商品：名称与订单明细的 product_name 完全对齐（体现两表关联）
INSERT INTO `t_product` (`id`, `name`, `price`, `category`, `brand`, `description`, `status`) VALUES
(1, '华为Mate 60 Pro',        6999.00, '手机',    '华为', '麒麟9000S芯片，支持卫星通话，6.82英寸OLED屏幕，5000mAh大电池', 1),
(2, '华为FreeBuds Pro 3',     1499.00, '耳机',    '华为', '智慧动态降噪3.0，高清音频传输，30小时超长续航', 1),
(3, 'iPhone 15 Pro Max',      9999.00, '手机',    '苹果', 'A17 Pro芯片，钛金属机身，4800万像素主摄，USB-C接口', 1),
(4, '小米14 Ultra',           6499.00, '手机',    '小米', '骁龙8 Gen3处理器，徕卡光学镜头，90W快充', 1),
(5, '索尼WH-1000XM5',         2899.00, '耳机',    '索尼', '行业领先降噪技术，30小时续航，轻量化设计', 1),
(6, '联想ThinkPad X1 Carbon',10999.00,'笔记本',  '联想', '第13代Intel酷睿i7，16GB内存，1TB固态硬盘，商务办公首选', 1);

-- 订单：第一条订单含 2 个商品，用于体现一对多
INSERT INTO `t_order` (`id`, `order_no`, `user_id`, `username`, `total_amount`, `status`) VALUES
(1, 'S020260101001', 2, 'zhangsan', 8498.00, '已发货'),
(2, 'S020260101002', 2, 'zhangsan', 1499.00, '已完成'),
(3, 'S020260101003', 3, 'lisi',     9999.00, '已支付');

INSERT INTO `t_order_item` (`order_id`, `product_id`, `product_name`, `price`, `quantity`, `subtotal`) VALUES
(1, 1, '华为Mate 60 Pro',    6999.00, 1, 6999.00),
(1, 2, '华为FreeBuds Pro 3', 1499.00, 1, 1499.00),
(2, 2, '华为FreeBuds Pro 3', 1499.00, 1, 1499.00),
(3, 3, 'iPhone 15 Pro Max',  9999.00, 1, 9999.00);

-- ============================================================
-- 校验SQL
-- ============================================================
SELECT '用户' AS 表名, COUNT(*) AS 记录数 FROM t_user
UNION ALL SELECT '商品', COUNT(*) FROM t_product
UNION ALL SELECT '订单', COUNT(*) FROM t_order
UNION ALL SELECT '订单明细', COUNT(*) FROM t_order_item;

-- 验证一对多：订单 1 应查出 2 个商品
SELECT o.order_no, o.total_amount, i.product_name, i.price, i.quantity
FROM t_order o
JOIN t_order_item i ON i.order_id = o.id
WHERE o.id = 1;
