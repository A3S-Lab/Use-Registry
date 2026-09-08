# A3S Use Registry

<p align="center">
  <strong>Language / 语言:</strong>
  <a href="README.md">English</a> ·
  <a href="README.zh-CN.md">中文</a>
</p>

[A3S Use](https://github.com/A3S-Lab/Use) 的官方已签名软件包 Registry 部署。

> **状态：** 预引导（pre-bootstrap）。本仓库尚未发布生产信任根或可安装的软件包目录。

## 所有权边界

本仓库负责：经审阅的准入记录、不可变发布产物、软件供应链证据、已签名的 TUF 发布状态，以及 Registry 运维流程。

本仓库不负责：

- 包管理器、Registry 格式，或编写与校验工具；这些属于 A3S Use；
- 软件包源代码或包专用构建；这些保留在各自所属仓库中，例如 A3S MHS；
- 消费者安装权威；每一次 A3S Use 安装各自拥有其选定的源、独立获取的 bootstrap-root 摘要、经审阅的计划、Grants，以及激活状态。

## 信任模型

GitHub 只是传输与审阅面，不是信任根。客户端必须为初始 TUF root 钉住一份独立获取的 SHA-256 摘要，并在安装前验证完整的元数据链与目标摘要。仓库重命名、重定向、分支与 Git 历史均不授予信任权威。

未来的静态 Registry 将发布在 `registry/` 之下。仅当 [A3S Use 路线图](https://github.com/A3S-Lab/Use/blob/main/ROADMAP.md) 中的保管、轮换、过期、撤回、镜像替换与恢复流程实现并审阅完成后，才会加入生产引导材料。
